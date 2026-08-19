import SwiftUI
import WidgetKit

/// Home-screen vitals: the key numbers with their usual-range direction.
struct VitalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalsWidget", provider: SnapshotProvider()) { entry in
            VitalsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Vitals")
        .description("Your key vitals and how they compare to your usual range.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct VitalsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: SnapshotEntry

    private var vitals: [WidgetVital] {
        let all = entry.snapshot?.vitals ?? []
        return Array(all.prefix(family == .systemSmall ? 2 : 4))
    }

    var body: some View {
        if vitals.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(.secondary)
                Text("Open Vitals once to fill this in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(vitals) { vital in
                    vitalRow(vital)
                }
                Spacer(minLength: 0)
                if let updated = entry.snapshot?.updatedAt {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func vitalRow(_ vital: WidgetVital) -> some View {
        HStack(spacing: 6) {
            Image(systemName: vital.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(vital.title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(vital.value)
                        .font(.callout.weight(.semibold))
                    Text(vital.unit)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let status = vital.status {
                Image(systemName: statusIcon(status))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor(status))
            }
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "above": "arrow.up.right"
        case "below": "arrow.down.right"
        default: "checkmark"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "above": .orange
        case "below": .teal
        default: .green
        }
    }
}
