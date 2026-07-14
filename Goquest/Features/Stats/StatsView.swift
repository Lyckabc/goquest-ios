import SwiftUI
import Charts

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()

    private static let allWorkspacesTag = "__all__"

    var body: some View {
        List {
            if !vm.workspaces.isEmpty {
                Section {
                    Picker("Workspace", selection: Binding(
                        get: { vm.selectedWorkspace?.id ?? Self.allWorkspacesTag },
                        set: { newId in
                            let target = newId == Self.allWorkspacesTag
                                ? nil
                                : vm.workspaces.first { $0.id == newId }
                            Task { await vm.selectWorkspace(target) }
                        }
                    )) {
                        Text("All workspaces").tag(Self.allWorkspacesTag)
                        ForEach(vm.workspaces) { w in
                            Text(w.name).tag(w.id)
                        }
                    }
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open tickets").font(.caption).foregroundStyle(.secondary)
                        Text("\(vm.openCount)").font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "tray.full").font(.title).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if vm.isLoading && vm.status.isEmpty {
                ProgressView()
            } else {
                bucketChart(title: "By status", buckets: vm.status)
                bucketChart(title: "By priority", buckets: vm.priority)
                bucketChart(title: "By type", buckets: vm.type)
            }
        }
        .navigationTitle("Stats")
        .refreshable { await vm.load() }
        .task { await vm.loadWorkspaces() }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { _ in vm.error = nil })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    @ViewBuilder
    private func bucketChart(title: String, buckets: [AggBucket]) -> some View {
        Section(title) {
            if buckets.isEmpty {
                Text("No data").foregroundStyle(.secondary).font(.caption)
            } else {
                Chart(buckets, id: \.key) { b in
                    BarMark(
                        x: .value("Count", b.count),
                        y: .value("Key", displayKey(b.key))
                    )
                    .annotation(position: .trailing) {
                        Text("\(b.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                // 행당 28pt — 버킷 수에 따라 늘어나는 가로 바 차트.
                .frame(height: max(CGFloat(buckets.count) * 28, 44))
                .padding(.vertical, 4)
            }
        }
    }

    /// Server sends "" for NULL/empty group values; underscores read badly.
    private func displayKey(_ key: String) -> String {
        key.isEmpty ? "none" : key.replacingOccurrences(of: "_", with: " ")
    }
}
