import SwiftUI
import AppKit
import DuplicateFinderCore

struct DuplicatesListView: View {
    @ObservedObject var vm: ScanViewModel
    @State private var showConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            bulkBar
        }
        .confirmationDialog(
            confirmMessage,
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Move \(vm.selection.count) files to Trash", role: .destructive) {
                vm.performTrash()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            if let r = vm.result {
                VStack(alignment: .leading) {
                    Text("\(r.groups.count) duplicate group\(r.groups.count == 1 ? "" : "s")").font(.title2).bold()
                    Text("Wasted: \(humanBytes(r.totalWastedBytes)) · Scanned \(r.filesSeen) files in \(String(format: "%.1fs", r.elapsedSeconds))")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu("Quick select") {
                Button("Keep newest in each group") { vm.keepNewestInAllGroups() }
                Button("Keep oldest in each group") { vm.keepOldestInAllGroups() }
                Divider()
                Button("Select all except first in each group") { vm.selectAllExceptFirst() }
                Button("Clear selection") { vm.clearSelection() }
            }
        }
        .padding()
    }

    private var list: some View {
        List {
            ForEach(vm.result?.groups ?? []) { g in
                Section {
                    ForEach(g.files) { f in
                        FileRow(entry: f, isSelected: Binding(
                            get: { vm.selection.contains(f.url) },
                            set: { on in
                                if on { vm.selection.insert(f.url) } else { vm.selection.remove(f.url) }
                            }
                        ))
                    }
                } header: {
                    GroupHeader(group: g)
                }
            }
        }
        .listStyle(.inset)
    }

    private var bulkBar: some View {
        HStack {
            Text("\(vm.selection.count) selected · frees \(humanBytes(vm.selectedBytes))")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showConfirm = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .keyboardShortcut(.delete)
            .buttonStyle(.borderedProminent)
            .disabled(vm.selection.isEmpty || !vm.groupsWithAllFilesSelected().isEmpty)
        }
        .padding()
    }

    private var confirmMessage: String {
        let bad = vm.groupsWithAllFilesSelected().count
        if bad > 0 {
            return "\(bad) group(s) would lose ALL copies. Deselect at least one file per group."
        }
        return "Move \(vm.selection.count) files (\(humanBytes(vm.selectedBytes))) to the Trash? You can restore them from Finder."
    }
}

private struct GroupHeader: View {
    let group: DuplicateGroup
    var body: some View {
        HStack {
            Image(systemName: iconForKind(group.files.first?.kind))
            Text("\(group.count) copies · \(humanBytes(group.size)) each · wastes \(humanBytes(group.wastedBytes))")
                .font(.headline)
            Spacer()
            Text(group.contentHash.prefix(12) + "…")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func iconForKind(_ k: MediaKind?) -> String {
        switch k {
        case .photo: return "photo"
        case .video: return "video"
        case .document: return "doc.text"
        case .none: return "doc"
        }
    }
}

private struct FileRow: View {
    let entry: FileEntry
    @Binding var isSelected: Bool

    var body: some View {
        HStack {
            Toggle("", isOn: $isSelected).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.url.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let m = entry.modifiedAt {
                    Text("modified \(m.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
    }
}
