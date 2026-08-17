import SwiftUI

/// Home tab: everything the watch collected, pulled straight from Apple Health.
struct HealthDashboardView: View {
    @State private var model = HealthDashboardViewModel()
    @State private var showingSettings = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !model.isHealthAvailable {
                        unavailableNotice
                    }

                    NavigationLink {
                        SleepDetailView(lastNight: model.sleep)
                    } label: {
                        SleepCard(summary: model.sleep)
                    }
                    .buttonStyle(.plain)

                    ForEach(VitalSection.allCases) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: section.title)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(model.vitals(in: section)) { kind in
                                    NavigationLink {
                                        VitalDetailView(
                                            kind: kind,
                                            latest: model.reading(for: kind)
                                        )
                                    } label: {
                                        VitalCard(
                                            kind: kind,
                                            reading: model.reading(for: kind)
                                        )
                                    }
                                    .buttonStyle(.plain)
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
