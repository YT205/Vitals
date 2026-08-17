import SwiftUI

/// Last night's sleep, with a stacked bar for the stage breakdown.
struct SleepCard: View {
    let summary: SleepSummary?

    private var stages: [(label: String, seconds: TimeInterval, color: Color)] {
        guard let summary else { return [] }
        return [
            ("Deep", summary.deep, .indigo),
            ("Core", summary.core, .blue),
            ("REM", summary.rem, .cyan),
            ("Awake", summary.awake, .orange),
        ].filter { $0.1 > 0 }
    }

    private var stageTotal: TimeInterval {
        stages.reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                    Text("Last Night's Sleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let summary, summary.hasData {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(SleepSummary.formatted(summary.asleep))
                            .font(.largeTitle.weight(.semibold))
                            .contentTransition(.numericText())
                        Text("asleep")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let bedtime = summary.bedtime, let wake = summary.wakeTime {
                        Text("\(bedtime.formatted(date: .omitted, time: .shortened)) to \(wake.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if stageTotal > 0 {
                        stageBar
                        stageLegend
                    }
                } else {
                    Text("--")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text("No sleep recorded since 6pm yesterday. Wear your watch overnight and enable Sleep tracking.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var stageBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(stages, id: \.label) { stage in
                    Capsule()
                        .fill(stage.color)
                        .frame(width: max(2, proxy.size.width * (stage.seconds / stageTotal)))
                }
            }
        }
        .frame(height: 10)
    }

    private var stageLegend: some View {
        HStack(spacing: 14) {
            ForEach(stages, id: \.label) { stage in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 6, height: 6)
                        Text(stage.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(SleepSummary.formatted(stage.seconds))
                        .font(.caption2.weight(.medium))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

extension SleepSummary {
    /// Sample data for previews.
    static var sample: SleepSummary {
        var summary = SleepSummary()
        summary.asleep = 7 * 3600 + 12 * 60
        summary.deep = 62 * 60
        summary.core = 4 * 3600
        summary.rem = 110 * 60
        summary.awake = 18 * 60
        summary.bedtime = Calendar.current.date(
            bySettingHour: 23, minute: 12, second: 0, of: .now
        )
        summary.wakeTime = Calendar.current.date(
            bySettingHour: 6, minute: 44, second: 0, of: .now
        )
        return summary
    }
}

#Preview {
    ScrollView {
        VStack {
            SleepCard(summary: .sample)
            SleepCard(summary: nil)
        }
        .padding()
    }
}
