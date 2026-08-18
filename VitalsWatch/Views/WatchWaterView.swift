import SwiftUI

/// Water page: today's ring plus quick-add buttons. Writes dietaryWater to
/// Apple Health, which syncs with the phone automatically.
struct WatchWaterView: View {
    @Environment(AppSettings.self) private var settings

    @State private var todayML: Double = 0
    @State private var isLogging = false

    private var progress: Double {
        guard settings.dailyWaterGoalML > 0 else { return 0 }
        return todayML / settings.dailyWaterGoalML
    }

    /// First three quick-add options fit the watch screen.
    private var quickAdds: [Double] {
        Array(settings.quickAddOptions.prefix(3))
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 7, tint: .blue)
                    .frame(width: 72, height: 72)

                VStack(spacing: 0) {
                    Text(settings.formattedVolume(fromMillilitres: todayML))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                    Text("of \(settings.formattedVolume(fromMillilitres: settings.dailyWaterGoalML))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                ForEach(quickAdds, id: \.self) { amount in
                    Button {
                        log(amount)
                    } label: {
                        Text(settings.formattedVolume(fromMillilitres: amount))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(isLogging)
                }
            }
        }
        .padding(.horizontal, 4)
        .task { await refresh() }
    }

    private func log(_ millilitres: Double) {
        isLogging = true
        Task {
            try? await HealthKitService.shared.saveWater(millilitres: millilitres)
            Haptics.light()
            await refresh()
            isLogging = false
        }
    }

    private func refresh() async {
        todayML = (try? await HealthKitService.shared.waterTotalToday()) ?? 0
    }
}
