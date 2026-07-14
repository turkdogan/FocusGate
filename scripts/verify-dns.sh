#!/bin/bash
set -uo pipefail

# DNS regression guard — run after EVERY extension change.
#
# Tests the browsers' resolution path (dscacheutil -> mDNSResponder), NOT
# dig: dig talks straight to the resolver and masked the port-53
# query-swallowing bug for a full day. See commit 09575ff.
#
# Usage: ./scripts/verify-dns.sh [blocked-domain]
# The blocked domain must be enabled in FocusGate (default: eksisozluk.com).

BLOCKED="${1:-eksisozluk.com}"
FRESH_SUB="rg$RANDOM.$BLOCKED"          # never-cached, matches subdomain rule
ALLOWED="www.wikipedia.org"
PASS=0; FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  PASS  $name"
        PASS=$((PASS+1))
    else
        echo "  FAIL  $name — expected '$expected', got '$actual'"
        FAIL=$((FAIL+1))
    fi
}

# mDNSResponder path with a hard timeout: dscacheutil has none of its own
resolve() {
    local host="$1" timeout_s="$2"
    local out
    out=$( (dscacheutil -q host -a name "$host" & CPID=$!; sleep "$timeout_s"; kill $CPID 2>/dev/null) 2>/dev/null )
    echo "$out"
}

echo "=== FocusGate DNS verification (browsers' path) ==="

echo "[1] Blocked domain resolves to unroutable address in <3s"
check "blocked -> 0.0.0.0" "0.0.0.0" "$(resolve "$BLOCKED" 3)"

echo "[2] Fresh blocked subdomain (no cache possible) in <3s"
check "fresh subdomain -> 0.0.0.0" "0.0.0.0" "$(resolve "$FRESH_SUB" 3)"

echo "[3] Allowed domain resolves normally in <5s"
out=$(resolve "$ALLOWED" 5)
if [[ "$out" == *ip_address* && "$out" != *"0.0.0.0"* ]]; then
    echo "  PASS  allowed resolves"; PASS=$((PASS+1))
else
    echo "  FAIL  allowed domain broken: '$out'"; FAIL=$((FAIL+1))
fi

echo "[4] Connection-level enforcement"
check "blocked connection dropped" "000" "$(curl -sm 4 -o /dev/null -w '%{http_code}' "https://$BLOCKED" 2>/dev/null)"
check "allowed connection open" "200" "$(curl -sm 6 -o /dev/null -w '%{http_code}' "https://$ALLOWED" 2>/dev/null)"

echo "[5] Extension alive"
check "provider process running" "FocusGateExtension" "$(pgrep -fl 'FocusGateExtension$' || echo none)"

echo
echo "=== $PASS passed, $FAIL failed ==="
exit $(( FAIL > 0 ? 1 : 0 ))
