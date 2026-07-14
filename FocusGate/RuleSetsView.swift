//
//  RuleSetsView.swift
//  FocusGate
//
//  UI for managing rule sets and schedules
//

import SwiftUI

struct RuleSetsView: View {
    @EnvironmentObject var configStore: ConfigurationStore
    @State private var selectedRuleSetId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rule Sets")
                .font(.title2)
                .bold()

            HStack(spacing: 16) {
                // Rule sets list
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your rule sets")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if configStore.configuration.ruleSets.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("No rule sets")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                    } else {
                        List(selection: $selectedRuleSetId) {
                            ForEach(configStore.configuration.ruleSets) { ruleSet in
                                RuleSetListItem(ruleSet: ruleSet)
                                    .tag(ruleSet.id)
                            }
                        }
                    }

                    HStack {
                        Button {
                            createNewRuleSet()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("New rule set")

                        Button {
                            deleteSelectedRuleSet()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedRuleSetId == nil)
                        .help("Delete selected rule set")

                        Spacer()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(minWidth: 200, maxWidth: 250)

                Divider()

                // Rule set detail/editor
                if let selectedId = selectedRuleSetId,
                   configStore.configuration.ruleSets.contains(where: { $0.id == selectedId }) {
                    RuleSetDetailView(ruleSetId: selectedId)
                        .id(selectedId) // fresh editor state per rule set
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Select a rule set to view details")
                            .foregroundColor(.secondary)
                        Text("or create a new one")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func createNewRuleSet() {
        let newRuleSet = RuleSet(name: "New Rule Set", schedules: [])
        configStore.addRuleSet(newRuleSet)
        selectedRuleSetId = newRuleSet.id
    }

    private func deleteSelectedRuleSet() {
        guard let id = selectedRuleSetId else { return }
        configStore.removeRuleSet(id: id)
        selectedRuleSetId = nil
    }
}

// MARK: - Rule Set List Item

struct RuleSetListItem: View {
    let ruleSet: RuleSet

    var body: some View {
        // TimelineView keeps the "active now" dot honest as time passes
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ruleSet.name)
                        .font(.body)

                    Text(scheduleSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if ruleSet.isActive(at: context.date) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .help("Active now")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var scheduleSummary: String {
        let count = ruleSet.schedules.count
        switch count {
        case 0: return "No schedule"
        case 7: return "Every day"
        default: return "\(count) day\(count == 1 ? "" : "s") scheduled"
        }
    }
}

// MARK: - Rule Set Detail View

struct RuleSetDetailView: View {
    @EnvironmentObject var configStore: ConfigurationStore
    let ruleSetId: UUID

    private var ruleSet: RuleSet? {
        configStore.configuration.ruleSets.first { $0.id == ruleSetId }
    }

    var body: some View {
        if let ruleSet {
            VStack(alignment: .leading, spacing: 16) {
                // Name editor — writes through on every keystroke
                TextField("Rule Set Name", text: nameBinding(ruleSet))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                Divider()

                Text("Schedule")
                    .font(.headline)

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(DaySchedule.Weekday.allCases, id: \.self) { weekday in
                            DayScheduleRow(
                                weekday: weekday,
                                schedule: scheduleBinding(for: weekday, in: ruleSet)
                            )
                        }
                    }
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }

                Spacer(minLength: 0)

                // Sites using this rule set
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blocked sites using this rule set:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let sitesInRuleSet = configStore.configuration.blockedSites.filter { $0.ruleSetId == ruleSet.id }

                    if sitesInRuleSet.isEmpty {
                        Text("No sites assigned to this rule set")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(sitesInRuleSet) { site in
                            Text("• \(site.pattern)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding([.top, .trailing])
        }
    }

    // MARK: - Write-through bindings (no Save button: edits persist immediately)

    private func nameBinding(_ ruleSet: RuleSet) -> Binding<String> {
        Binding(
            get: { ruleSet.name },
            set: { newName in
                var updated = ruleSet
                updated.name = newName
                configStore.updateRuleSet(updated)
            }
        )
    }

    private func scheduleBinding(for weekday: DaySchedule.Weekday, in ruleSet: RuleSet) -> Binding<DaySchedule?> {
        Binding(
            get: {
                ruleSet.schedules.first { $0.weekday == weekday }
            },
            set: { newValue in
                var updated = ruleSet
                updated.schedules.removeAll { $0.weekday == weekday }
                if let newValue {
                    updated.schedules.append(newValue)
                }
                configStore.updateRuleSet(updated)
            }
        )
    }
}

// MARK: - Day Schedule Row

struct DayScheduleRow: View {
    let weekday: DaySchedule.Weekday
    @Binding var schedule: DaySchedule?

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { schedule != nil },
            set: { on in
                schedule = on
                    ? DaySchedule(weekday: weekday,
                                  windows: [TimeWindow(start: TimeOfDay(hour: 9, minute: 0),
                                                       end: TimeOfDay(hour: 17, minute: 0))])
                    : nil
            }
        )
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Fixed-width day column keeps every row aligned
            Toggle(isOn: isEnabled) {
                Text(weekday.displayName)
                    .frame(width: 90, alignment: .leading)
            }
            .toggleStyle(.checkbox)

            if let schedule {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(schedule.windows) { window in
                        TimeWindowRow(
                            window: windowBinding(window),
                            onDelete: { deleteWindow(window) }
                        )
                    }

                    Button {
                        addWindow()
                    } label: {
                        Label("Add hours", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Text("Not scheduled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func windowBinding(_ window: TimeWindow) -> Binding<TimeWindow> {
        Binding(
            get: {
                schedule?.windows.first { $0.id == window.id } ?? window
            },
            set: { newValue in
                guard var current = schedule,
                      let index = current.windows.firstIndex(where: { $0.id == window.id }) else { return }
                current.windows[index] = newValue
                schedule = current
            }
        )
    }

    private func addWindow() {
        guard var current = schedule else { return }
        current.windows.append(TimeWindow(start: TimeOfDay(hour: 9, minute: 0),
                                          end: TimeOfDay(hour: 17, minute: 0)))
        schedule = current
    }

    private func deleteWindow(_ window: TimeWindow) {
        guard var current = schedule else { return }
        current.windows.removeAll { $0.id == window.id }
        schedule = current.windows.isEmpty ? nil : current
    }
}

// MARK: - Time Window Row

struct TimeWindowRow: View {
    @Binding var window: TimeWindow
    var canDelete: Bool = true
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TimeOfDayField(time: $window.start)

            Text("–")
                .foregroundColor(.secondary)

            TimeOfDayField(time: $window.end)

            // Reserved width so the hint appearing never shifts the row
            Text(window.isOvernight ? "overnight" : " ")
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 64, alignment: .leading)
                .help(window.isOvernight
                      ? "Covers this day's late evening AND this day's early morning (e.g. Mon 22:00–24:00 and Mon 00:00–06:00). To also cover the following morning, add the window to the next day."
                      : "")

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help("Remove this time window")
        }
    }
}

// MARK: - Time of Day Field

/// Native compact time field (keyboard editable, locale aware) bridging
/// DatePicker's Date to the model's TimeOfDay.
struct TimeOfDayField: View {
    @Binding var time: TimeOfDay

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: time.hour, minute: time.minute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                time = TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 76)
    }
}

#Preview {
    RuleSetsView()
        .environmentObject(ConfigurationStore())
        .frame(width: 700, height: 500)
}
