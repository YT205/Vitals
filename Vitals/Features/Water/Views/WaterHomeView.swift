import SwiftData
import SwiftUI

/// Water tab: quick logging, daily progress, and a week of history.
struct WaterHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \WaterEntry.loggedAt, order: .reverse)
    private var allEntries: [WaterEntry]

    @State private var model = WaterViewModel()
    @State private var showingSettings = false
    @State private var showingCustomAmount = false

    private var todayEntries: [WaterEntry] {
        model.entriesToday(from: allEntries)
    }

    private var todayTotal: Double {
        model.total(of: todayEntries)
    }

    private var progress: Double {
        guard settings.dailyWaterGoalML > 0 else { return 0 }
        return todayTotal / settings.dailyWaterGoalML
    }

    private var remaining: Double {
        max(0, settings.dailyWaterGoalML - todayTotal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    progressCard
                    quickAddCard
                    if !todayEntries.isEmpty { todayLogCard }
                    weekCard
                    if let error = model.syncError { syncNotice(error) }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Water")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("Water settings and reminders")
                }
            }
            .sheet(isPresented: $showingSettings) {
                WaterSettingsView()
            }
            .sheet(isPresented: $showingCustomAmount) {
                CustomAmountSheet { millilitres in
                    Task { await model.log(millilitres: millilitres, context: context) }
                }
            }
            // Keep the water widget's total current.
            .task {
                SnapshotPublisher.publishWater(todayML: todayTotal, settings: settings)
            }
            .onChange(of: todayTotal) { _, newTotal in
                SnapshotPublisher.publishWater(todayML: newTotal, settings: settings)
            }
        }
    }

    // MARK: - Cards

    private var progressCard: some View {
        Card {
            VStack(spacing: 16) {
                ProgressRing(progress: progress, lineWidth: 18, tint: .blue) {
                    VStack(spacing: 2) {
                        Text(settings.formattedVolume(fromMillilitres: todayTotal))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("of \(settings.formattedVolume(fromMillilitres: settings.dailyWaterGoalML))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 190, height: 190)
                .padding(.top, 4)

                HStack(alignment: .top) {
                    StatBlock(
                        value: "\(Int((min(progress, 1) * 100).rounded()))%",
                        caption: "Of goal",
                        tint: .blue
                    )
                    StatBlock(
                        value: settings.formattedVolume(fromMillilitres: remaining),
                        caption: remaining > 0 ? "To go" : "Goal hit"
                    )
                    StatBlock(
                        value: "\(todayEntries.count)",
                        caption: "Drinks"
                    )
                }
            }
        }
    }

    private var quickAddCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Add")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(), GridItem(), GridItem()],
                    spacing: 10
                ) {
                    ForEach(settings.quickAddOptions, id: \.self) { amount in
                        Button {
                            Task { await model.log(millilitres: amount, context: context) }
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "drop.fill")
                                    .font(.caption2)
                                Text(settings.formattedVolume(fromMillilitres: amount))
                                    .font(.footnote.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }

                    Button {
                        showingCustomAmount = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption2)
                            Text("Custom")
                                .font(.footnote.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var todayLogCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(todayEntries) { entry in
                    HStack {
                        Image(systemName: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(settings.formattedVolume(fromMillilitres: entry.amountML))
                            .font(.callout)
                        if !entry.savedToHealthKit {
                            Image(systemName: "icloud.slash")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Not synced to Apple Health")
                        }
                        Spacer()
                        Text(entry.loggedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            model.delete(entry, context: context)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete entry")
                    }
                    if entry.id != todayEntries.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last 7 Days")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let totals = model.dailyTotals(from: allEntries)
                let peak = max(settings.dailyWaterGoalML, totals.map(\.total).max() ?? 1)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(totals, id: \.date) { day in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    day.total >= settings.dailyWaterGoalML
                                        ? Color.blue
                                        : Color.blue.opacity(0.4)
                                )
                                .frame(height: max(3, 78 * (day.total / peak)))
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 100, alignment: .bottom)
            }
        }
    }

    private func syncNotice(_ message: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry Health Sync") {
                    Task {
                        await model.retryFailedSyncs(allEntries, context: context)
                    }
                }
                .font(.footnote)
            }
        }
    }
}

/// Sheet for logging an amount that isn't one of the presets.
struct CustomAmountSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double = 0
    let onLog: (Double) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                        Text(settings.volumeUnit.label)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Logged to Apple Health as water.")
                }
            }
            .navigationTitle("Custom Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        onLog(settings.millilitres(fromDisplayVolume: amount))
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }
}

#Preview {
    WaterHomeView()
        .environment(AppSettings())
        .modelContainer(VitalsModelContainer.preview)
}
