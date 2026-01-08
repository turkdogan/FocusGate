//
//  RuleSetsView.swift
//  PageBlocker
//
//  UI for managing rule sets and schedules
//

import SwiftUI

struct RuleSetsView: View {
    @EnvironmentObject var configStore: ConfigurationStore
    @State private var selectedRuleSetId: UUID? = nil
    @State private var showingEditor: Bool = false
    @State private var editingRuleSet: RuleSet? = nil

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
                            .onDelete(perform: deleteRuleSets)
                        }
                    }

                    Button("New Rule Set") {
                        createNewRuleSet()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(minWidth: 200, maxWidth: 250)

                Divider()

                // Rule set detail/editor
                if let selectedId = selectedRuleSetId,
                   let ruleSet = configStore.configuration.ruleSets.first(where: { $0.id == selectedId }) {
                    RuleSetDetailView(ruleSet: ruleSet, configStore: configStore)
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

    private func deleteRuleSets(at offsets: IndexSet) {
        for index in offsets {
            let ruleSet = configStore.configuration.ruleSets[index]
            configStore.removeRuleSet(id: ruleSet.id)
        }
    }
}

// MARK: - Rule Set List Item

struct RuleSetListItem: View {
    let ruleSet: RuleSet
    @State private var isActive: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ruleSet.name)
                    .font(.body)

                Text("\(ruleSet.schedules.count) day(s) scheduled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            checkIfActive()
        }
    }

    private func checkIfActive() {
        isActive = ruleSet.isActive(at: Date())
    }
}

// MARK: - Rule Set Detail View

struct RuleSetDetailView: View {
    let ruleSet: RuleSet
    let configStore: ConfigurationStore

    @State private var name: String
    @State private var schedules: [DaySchedule]

    init(ruleSet: RuleSet, configStore: ConfigurationStore) {
        self.ruleSet = ruleSet
        self.configStore = configStore
        _name = State(initialValue: ruleSet.name)
        _schedules = State(initialValue: ruleSet.schedules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name editor
            HStack {
                TextField("Rule Set Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                Button("Save") {
                    saveChanges()
                }
                .disabled(name.isEmpty)
                .buttonStyle(.borderedProminent)
            }

            Divider()

            // Schedule editor
            Text("Schedule")
                .font(.headline)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(DaySchedule.Weekday.allCases, id: \.self) { weekday in
                        DayScheduleEditor(
                            weekday: weekday,
                            schedule: bindingForWeekday(weekday),
                            onUpdate: { updated in
                                updateSchedule(weekday: weekday, schedule: updated)
                            }
                        )
                    }
                }
            }

            Spacer()

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
        .padding()
    }

    private func bindingForWeekday(_ weekday: DaySchedule.Weekday) -> Binding<DaySchedule?> {
        Binding(
            get: {
                schedules.first { $0.weekday == weekday }
            },
            set: { newValue in
                if let newValue = newValue {
                    if let index = schedules.firstIndex(where: { $0.weekday == weekday }) {
                        schedules[index] = newValue
                    } else {
                        schedules.append(newValue)
                    }
                } else {
                    schedules.removeAll { $0.weekday == weekday }
                }
            }
        )
    }

    private func updateSchedule(weekday: DaySchedule.Weekday, schedule: DaySchedule?) {
        if let schedule = schedule {
            if let index = schedules.firstIndex(where: { $0.weekday == weekday }) {
                schedules[index] = schedule
            } else {
                schedules.append(schedule)
            }
        } else {
            schedules.removeAll { $0.weekday == weekday }
        }
    }

    private func saveChanges() {
        var updated = ruleSet
        updated.name = name
        updated.schedules = schedules
        configStore.updateRuleSet(updated)
    }
}

// MARK: - Day Schedule Editor

struct DayScheduleEditor: View {
    let weekday: DaySchedule.Weekday
    @Binding var schedule: DaySchedule?
    let onUpdate: (DaySchedule?) -> Void

    @State private var isEnabled: Bool = false
    @State private var windows: [TimeWindow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(weekday.displayName, isOn: $isEnabled)
                .font(.body)
                .onChange(of: isEnabled) { _, newValue in
                    if newValue {
                        if windows.isEmpty {
                            windows = [TimeWindow(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 17, minute: 0))]
                        }
                        updateSchedule()
                    } else {
                        windows = []
                        schedule = nil
                        onUpdate(nil)
                    }
                }

            if isEnabled {
                VStack(spacing: 8) {
                    ForEach(windows) { window in
                        TimeWindowEditor(
                            window: bindingForWindow(window),
                            onDelete: {
                                deleteWindow(window)
                            }
                        )
                    }

                    Button("Add Time Window") {
                        addWindow()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.leading, 20)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            isEnabled = schedule != nil
            windows = schedule?.windows ?? []
        }
    }

    private func bindingForWindow(_ window: TimeWindow) -> Binding<TimeWindow> {
        Binding(
            get: {
                windows.first { $0.id == window.id } ?? window
            },
            set: { newValue in
                if let index = windows.firstIndex(where: { $0.id == window.id }) {
                    windows[index] = newValue
                    updateSchedule()
                }
            }
        )
    }

    private func addWindow() {
        let newWindow = TimeWindow(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 17, minute: 0))
        windows.append(newWindow)
        updateSchedule()
    }

    private func deleteWindow(_ window: TimeWindow) {
        windows.removeAll { $0.id == window.id }
        if windows.isEmpty {
            isEnabled = false
            schedule = nil
            onUpdate(nil)
        } else {
            updateSchedule()
        }
    }

    private func updateSchedule() {
        let daySchedule = DaySchedule(weekday: weekday, windows: windows)
        schedule = daySchedule
        onUpdate(daySchedule)
    }
}

// MARK: - Time Window Editor

struct TimeWindowEditor: View {
    @Binding var window: TimeWindow
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TimeOfDayPicker(time: $window.start)
            Text("to")
                .foregroundColor(.secondary)
                .font(.caption)
            TimeOfDayPicker(time: $window.end)

            if window.isOvernight {
                Text("(overnight)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Time of Day Picker

struct TimeOfDayPicker: View {
    @Binding var time: TimeOfDay

    var body: some View {
        HStack(spacing: 4) {
            // Hour picker
            Picker("", selection: $time.hour) {
                ForEach(0..<24) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .labelsHidden()
            .frame(width: 60)

            Text(":")

            // Minute picker
            Picker("", selection: $time.minute) {
                ForEach([0, 15, 30, 45], id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .labelsHidden()
            .frame(width: 60)
        }
    }
}

#Preview {
    RuleSetsView()
        .environmentObject(ConfigurationStore())
        .frame(width: 700, height: 500)
}
