import SwiftUI

/// Home tab: everything the watch collected, pulled straight from Apple Health.
struct HealthDashboardView: View {
    @Environment(AppSettings.self) private var settings

    @State private var model = HealthDashboardViewModel()
    @State private var showingSettings = false
    @State private var showingEditMetrics = false
    @State private var showingLogWeight = false
    @State private var showingBodyFat = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// Vitals the user hasn't hidden, per section.
    private func visibleVitals(in section: VitalSection) -> [VitalKind] {
        model.vitals(in: section).filter { settings.isVisible($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !model.isHealthAvailable {
                        unavailableNotice
                    }

                    if settings.showSleepCard {
                        NavigationLink {
                            SleepDetailView(lastNight: model.sleep)
                        } label: {
                            SleepCard(summary: model.sleep)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(VitalSection.allCases) { section in
                        let kinds = visibleVitals(in: section)
                        if !kinds.isEmpty || section == .bodyComposition {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: section.title)

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(kinds) { kind in
                                        NavigationLink {
                                            VitalDetailView(
                                                kind: kind,
                                                latest: model.reading(for: kind)
                                            )
                                        } label: {
                                            VitalCard(
                                                kind: kind,
                                                reading: model.reading(for: kind),
                                                status: model.status(for: kind)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if section == .bodyComposition {
                                    bodyActions
                                }
                            }
                        }
                    }

                    if model.looksLikePermissionProblem {
                        permissionNotice
                    }

                    footer
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Health")
            .background(Color(.systemGroupedBackground))
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditMetrics = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Edit metrics")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingEditMetrics) {
                EditMetricsSheet()
            }
            .sheet(isPresented: $showingLogWeight) {
                LogWeightSheet {
                    Task { await model.refresh() }
                }
            }
            .sheet(isPresented: $showingBodyFat) {
                BodyFatCalculatorView {
                    Task { await model.refresh() }
                }
            }
        }
    }

    /// Log Weight / Body Fat buttons under the Body section. Shown even when
    /// all body cards are hidden, so logging is never unreachable.
    private var bodyActions: some View {
        HStack(spacing: 10) {
            Button {
                showingLogWeight = true
            } label: {
                Label("Log Weight", systemImage: "scalemass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showingBodyFat = true
            } label: {
                Label("Body Fat", systemImage: "percent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var unavailableNotice: some View {
        Card {
            Label {
                Text("Health data isn't available on this device. Run on an iPhone to see your vitals.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var permissionNotice: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("No Health data coming through")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "heart.slash")
                        .foregroundStyle(.red)
                }
                Text("Open Health, go to Sharing, then Apps & Services, tap Vitals and turn on the categories you want to see here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        Group {
            if model.isLoading {
                ProgressView()
                    .padding(.top, 4)
            } else if let lastRefreshed = model.lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HealthDashboardView()
        .environment(AppSettings())
        .modelContainer(VitalsModelContainer.preview)
}
