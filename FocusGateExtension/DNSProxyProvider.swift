//
//  DNSProxyProvider.swift
//  FocusGateExtension
//
//  DNS proxy that answers NXDOMAIN for blocked domains so browsers fail
//  immediately ("site not found") instead of timing out, and transparently
//  forwards every other query to its original resolver.
//
//  Fail-safe rule: anything this code does not fully understand is
//  forwarded untouched. Only a well-formed query whose name matches the
//  blocklist gets a synthesized answer. The socket filter remains the
//  enforcement backstop for anything that slips through (cached DNS,
//  direct IPs, in-browser DoH).
//

import Foundation
import Network
import NetworkExtension
import os.log

class DNSProxyProvider: NEDNSProxyProvider {

    private let logger = OSLog(subsystem: "dev.turkdogan.FocusGate", category: "DNSProxyProvider")

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        os_log("🚀 DNS proxy starting", log: logger, type: .info)
        // Both providers run in this process; whichever starts first wins.
        ProviderXPCService.shared.start()
        // Stale records from before the proxy existed must not linger
        DNSCacheFlusher.flush()
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("DNS proxy stopping, reason: %d", log: logger, type: .info, reason.rawValue)
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        if let udpFlow = flow as? NEAppProxyUDPFlow {
            udpFlow.open(withLocalEndpoint: nil) { [weak self] error in
                if let error {
                    os_log("Failed to open UDP flow: %{public}@", log: self?.logger ?? .default,
                           type: .error, error.localizedDescription)
                    return
                }
                self?.serveUDPFlow(udpFlow)
            }
            return true
        }

        if let tcpFlow = flow as? NEAppProxyTCPFlow {
            tcpFlow.open(withLocalEndpoint: nil) { [weak self] error in
                if let error {
                    os_log("Failed to open TCP flow: %{public}@", log: self?.logger ?? .default,
                           type: .error, error.localizedDescription)
                    return
                }
                self?.relayTCPFlow(tcpFlow)
            }
            return true
        }

        return false
    }

    // MARK: - UDP (the normal DNS path)

    private func serveUDPFlow(_ flow: NEAppProxyUDPFlow) {
        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self, error == nil,
                  let datagrams, let endpoints, !datagrams.isEmpty else {
                flow.closeReadWithError(nil)
                flow.closeWriteWithError(nil)
                return
            }

            for (datagram, endpoint) in zip(datagrams, endpoints) {
                // DNS flow endpoints are always host endpoints; anything
                // else cannot be forwarded, so skip it.
                guard let hostEndpoint = endpoint as? NWHostEndpoint else { continue }
                self.handleDatagram(datagram, to: hostEndpoint, on: flow)
            }

            // Keep reading until the flow closes
            self.serveUDPFlow(flow)
        }
    }

    private func handleDatagram(_ datagram: Data, to endpoint: NWHostEndpoint, on flow: NEAppProxyUDPFlow) {
        if let qname = DNSMessage.queryName(in: datagram),
           let config = FilterState.shared.config,
           config.blockDecision(for: qname).blocked {
            if let response = DNSMessage.blockedResponse(forQuery: datagram) {
                os_log("DNS blocked (unroutable answer): %{public}@", log: logger, type: .info, qname)
                flow.writeDatagrams([response], sentBy: [endpoint]) { _ in }
                return
            }
            // Could not synthesize a response — fall through and forward;
            // the socket filter will still drop the actual connection.
        }

        forwardDatagram(datagram, to: endpoint, on: flow)
    }

    private func forwardDatagram(_ datagram: Data, to endpoint: NWHostEndpoint, on flow: NEAppProxyUDPFlow) {
        guard let target = Self.connectionEndpoint(from: endpoint) else {
            return
        }

        let connection = NWConnection(to: target, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: datagram, completion: .contentProcessed { _ in })
                connection.receiveMessage { data, _, _, _ in
                    if let data {
                        flow.writeDatagrams([data], sentBy: [endpoint]) { _ in }
                    }
                    connection.cancel()
                }
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))

        // Upstream resolvers answer in milliseconds; reap stragglers so
        // connections cannot pile up.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }

    // MARK: - TCP (rare: large responses, retries after truncation)

    private func relayTCPFlow(_ flow: NEAppProxyTCPFlow) {
        guard let target = Self.connectionEndpoint(from: flow.remoteEndpoint as? NWHostEndpoint) else {
            flow.closeReadWithError(nil)
            flow.closeWriteWithError(nil)
            return
        }

        let connection = NWConnection(to: target, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.pumpFlowToConnection(flow, connection)
                self?.pumpConnectionToFlow(connection, flow)
            case .failed:
                flow.closeReadWithError(nil)
                flow.closeWriteWithError(nil)
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func pumpFlowToConnection(_ flow: NEAppProxyTCPFlow, _ connection: NWConnection) {
        flow.readData { [weak self] data, error in
            guard let data, !data.isEmpty, error == nil else {
                connection.send(content: nil, isComplete: true, completion: .idempotent)
                return
            }
            connection.send(content: data, completion: .contentProcessed { _ in
                self?.pumpFlowToConnection(flow, connection)
            })
        }
    }

    private func pumpConnectionToFlow(_ connection: NWConnection, _ flow: NEAppProxyTCPFlow) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                flow.write(data) { writeError in
                    if writeError == nil {
                        self?.pumpConnectionToFlow(connection, flow)
                    } else {
                        connection.cancel()
                    }
                }
            }
            if isComplete || error != nil {
                flow.closeWriteWithError(nil)
                connection.cancel()
            }
        }
    }

    // MARK: - Endpoint conversion

    private static func connectionEndpoint(from endpoint: NWHostEndpoint?) -> Network.NWEndpoint? {
        guard let host = endpoint else { return nil }
        guard let port = Network.NWEndpoint.Port(host.port) else { return nil }
        return .hostPort(host: Network.NWEndpoint.Host(host.hostname), port: port)
    }
}

// MARK: - Minimal DNS wire format handling

enum DNSMessage {

    /// Extracts the query name from a DNS query, or nil if the datagram is
    /// not a plain query we fully understand (which callers must forward).
    static func queryName(in datagram: Data) -> String? {
        guard datagram.count > 12 else { return nil }

        let flags = UInt16(datagram[2]) << 8 | UInt16(datagram[3])
        guard flags & 0x8000 == 0 else { return nil }          // response, not query
        guard flags & 0x7800 == 0 else { return nil }          // non-standard opcode

        let questionCount = UInt16(datagram[4]) << 8 | UInt16(datagram[5])
        guard questionCount >= 1 else { return nil }

        var labels: [String] = []
        var index = 12
        while index < datagram.count {
            let length = Int(datagram[index])
            if length == 0 { break }
            guard length <= 63, index + 1 + length <= datagram.count else { return nil }
            let labelData = datagram[(index + 1)...(index + length)]
            guard let label = String(data: labelData, encoding: .utf8) else { return nil }
            labels.append(label)
            index += 1 + length
        }
        guard !labels.isEmpty else { return nil }
        return labels.joined(separator: ".").lowercased()
    }

    /// Builds a response for a blocked domain: A answers 0.0.0.0, AAAA
    /// answers ::, everything else gets an empty NOERROR (NODATA).
    /// Pi-hole-style positive answers rather than synthesized NXDOMAIN —
    /// mDNSResponder rejects our NXDOMAIN and hangs in retry backoff,
    /// while a normally-shaped answer takes the same acceptance path as
    /// every forwarded response. Browsers show "can't connect" instantly.
    static func blockedResponse(forQuery query: Data) -> Data? {
        guard let questionEnd = questionSectionEnd(in: query) else { return nil }
        let qtype = UInt16(query[questionEnd - 4]) << 8 | UInt16(query[questionEnd - 3])

        // Keep the FULL query — a query has no answer/authority records, so
        // everything after the question is its additional section (EDNS OPT,
        // cookies). mDNSResponder rejects responses that drop the OPT record
        // (treats them as broken legacy replies and hangs in retry), so the
        // additional section must survive verbatim.
        var response = Data(query)
        response[2] = query[2] | 0x80                          // QR = response
        response[3] = (query[3] & 0x10) | 0x80                 // RA set, CD preserved, RCODE 0

        let rdata: [UInt8]?
        switch qtype {
        case 1:  rdata = [0, 0, 0, 0]                          // A     -> 0.0.0.0
        case 28: rdata = Array(repeating: 0, count: 16)        // AAAA  -> ::
        default: rdata = nil                                   // NODATA
        }

        if let rdata {
            response[6] = 0; response[7] = 1                   // ANCOUNT = 1
            var record: [UInt8] = [0xC0, 0x0C]                 // name: pointer to question
            record += [UInt8(qtype >> 8), UInt8(qtype & 0xFF)] // TYPE echoes the question
            record += [0x00, 0x01]                             // CLASS IN
            record += [0x00, 0x00, 0x00, 0x0A]                 // TTL 10s
            record += [0x00, UInt8(rdata.count)]               // RDLENGTH
            record += rdata
            // Answer section sits between question and additional
            response.insert(contentsOf: record, at: questionEnd)
        }

        return response
    }

    /// Offset just past the first question's QTYPE/QCLASS.
    private static func questionSectionEnd(in datagram: Data) -> Int? {
        guard datagram.count > 12 else { return nil }
        var index = 12
        while index < datagram.count {
            let length = Int(datagram[index])
            if length == 0 {
                let end = index + 1 + 4                        // zero byte + QTYPE + QCLASS
                return end <= datagram.count ? end : nil
            }
            guard length <= 63 else { return nil }
            index += 1 + length
        }
        return nil
    }
}
