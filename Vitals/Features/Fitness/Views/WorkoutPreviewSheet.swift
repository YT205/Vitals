import SwiftData
import SwiftUI

/// What the user chose in the preview. Handled by `FitnessHomeView` after the
/// sheet dismisses, so sheet transitions never overlap.
enum WorkoutPreviewAction {
    case edit
    case start
}

/// Bottom-sheet preview of a workout plan: every exercise with its current
/// sets, reps, rest and last weight. Edit or start from the pinned buttons.
struct WorkoutPreviewSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate
    /// `false` while another workout is already in progress.
    let canStart: Bool
    let onAction: (WorkoutPreviewAction) -> Void

    private var totalSets: Int {
        template.orderedItems.reduce(0) { $0 + $1.displayPlan.count }
    }

    /// Rough duration: per set, assume ~45s of work plus the planned rest.
    private var estimatedMinutes: Int {
        let seconds = template.orderedItems.reduce(0) {
            $0 + $1.displayPlan.count * ($1.restSeconds + 45)
        }
        return max(1, seconds / 60)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top) {
                        StatBlock(value: "\(template.items.count)", caption: "Exercises")
                        StatBlock(value: "\(totalSets)", caption: "Sets")
                        StatBlock(value: "~\(estimatedMinutes) min", caption: "Est. time")
                    }

                    if let last = template.lastPerformedAt {
                        Text("Last done \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Plan") {
                    ForEach(template.orderedItems) { item in
                        itemRow(item)
                    }
                }
            }
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Same table layout as the live workout rows, read-only.
    private func itemRow(_ item: TemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.exerciseName)
                    .font(.body.weight(.medium))
                Spacer()
                Label(
                    "\(WorkoutSession.formatMinutesSeconds(Double(item.restSeconds))) rest",
                    systemImage: "timer"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let alternate = item.alternate {
                Label(
                    "Alternative: \(alternate.exerciseName)",
                    systemImage: "arrow.triangle.branch"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            // Column header, matching SetHeaderRow.
            HStack(spacing: 10) {
                Text("Set")
                    .frame(width: 24)
                Text(settings.weightUnit.label.uppercased())
                    .frame(maxWidth: .infinity)
                Text("")
                    .font(.caption)
                Text("REPS")
                    .frame(maxWidth: .infinity)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)

            ForEach(item.displayPlan, id: \.setNumber) { planSet in
                HStack(spacing: 10) {
                    Text("\(planSet.setNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.gray.opacity(0.15)))

                    Text(
                        planSet.weightKg > 0
                            ? settings.displayWeight(fromKilograms: planSet.weightKg)
                                .formatted(.number.precision(.fractionLength(0...1)))
                            : "--"
                    )
                    .font(.callout)
                    .foregroundStyle(planSet.weightKg > 0 ? .primary : .tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.background.secondary, in: .rect(cornerRadius: 7))

                    Text("x")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("\(planSet.reps)")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(.background.secondary, in: .rect(cornerRadius: 7))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                onAction(.edit)
                dismiss()
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                onAction(.start)
                dismiss()
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStart)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
