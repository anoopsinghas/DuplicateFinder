import SwiftUI
import UniformTypeIdentifiers
import DuplicateFinderCore

struct FilesScanView: View {
    @StateObject private var vm = FilesScanViewModel()
    @State private var showingPicker = false
    @State private var confirmingTrash = false

    var body: some View {
        Group {
            switch vm.state {
            case .idle: idleView
            case .scanning: scanningView
            case .done: resultsView
            }
        }
        .navigationTitle("Files")
        .sheet(isPresented: $showingPicker) {
            FolderPicker { url in
                vm.rootURL = url
                showingPicker = false
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Find duplicate files").font(.title2).bold()
            Text("Pick any folder from Files (iCloud Drive, On My iPhone, third-party providers). Deletion moves files to that provider's Trash.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let root = vm.rootURL {
                VStack(spacing: 4) {
                    Text("Selected folder").font(.caption).foregroundStyle(.secondary)
                    Text(root.lastPathComponent).font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
            }

            Button {
                showingPicker = true
            } label: {
                Label(vm.rootURL == nil ? "Pick a folder" : "Change folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 24)

            Form {
                Section {
                    Toggle("Photos", isOn: $vm.scanPhotos)
                    Toggle("Videos", isOn: $vm.scanVideos)
                    Toggle("Documents", isOn: $vm.scanDocuments)
                } header: {
                    Text("What to scan")
                }
            }
            .frame(maxHeight: 240)
            .scrollDisabled(true)

            Button {
                vm.startScan()
            } label: {
                Text("Start Scan")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.rootURL == nil || vm.kinds.isEmpty)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 20)
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4).padding(.top, 40)
            Text(phaseText).font(.headline)
            VStack(spacing: 4) {
                Text("\(vm.progress.filesSeen) files seen").font(.footnote).foregroundStyle(.secondary)
                if vm.progress.candidatesToHash > 0 {
                    Text("\(vm.progress.filesHashed) / \(vm.progress.candidatesToHash) hashed")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Cancel") { vm.cancelScan() }.padding(.top, 8)
            Spacer()
        }
    }

    private var phaseText: String {
        switch vm.progress.phase {
        case .walking: return "Walking folder…"
        case .hashing: return "Hashing candidates…"
        case .finalizing: return "Finalizing…"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        if let result = vm.result, !result.groups.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(result.groups.count) duplicate groups").font(.headline)
                        Text("\(byteFormatter.string(fromByteCount: result.groups.reduce(Int64(0)) { $0 + $1.wastedBytes })) recoverable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Keep newest, select rest") { vm.keepNewestInAllGroups() }
                        Button("Clear selection") { vm.clearSelection() }
                    } label: {
                        Label("Select", systemImage: "checkmark.circle").labelStyle(.iconOnly)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                List {
                    ForEach(result.groups) { group in
                        Section {
                            ForEach(group.files) { file in
                                FileRow(file: file, selected: vm.selection.contains(file.url)) {
                                    if vm.selection.contains(file.url) { vm.selection.remove(file.url) }
                                    else { vm.selection.insert(file.url) }
                                }
                            }
                        } header: {
                            HStack {
                                Text("\(group.count) × \(byteFormatter.string(fromByteCount: group.size))")
                                Spacer()
                                Text("+\(byteFormatter.string(fromByteCount: group.wastedBytes))")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if !vm.selection.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            confirmingTrash = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Move \(vm.selection.count) to Trash")
                                Spacer()
                                Text(byteFormatter.string(fromByteCount: vm.selectedBytes))
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(safetyOK ? Color.red : Color.gray)
                            .foregroundStyle(.white)
                        }
                        .disabled(!safetyOK)
                    }
                }
            }
            .confirmationDialog(
                "Move \(vm.selection.count) files to Trash?",
                isPresented: $confirmingTrash,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) { vm.performTrash() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Frees \(byteFormatter.string(fromByteCount: vm.selectedBytes)). Recovery depends on the file provider (iCloud Drive keeps deleted items for 30 days).")
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("No duplicates found").font(.title2).bold()
                Button("Scan again") {
                    vm.state = .idle
                    vm.result = nil
                }
            }
            .padding(.top, 60)
        }
    }

    private var safetyOK: Bool { vm.groupsWithAllFilesSelected().isEmpty }
}

private struct FileRow: View {
    let file: FileEntry
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.url.lastPathComponent).font(.subheadline).lineLimit(1)
                    Text(shortDate(file.modifiedAt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch file.kind {
        case .photo: return "photo"
        case .video: return "film"
        case .document: return "doc"
        }
    }

    private func shortDate(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }
}

/// Wraps UIDocumentPickerViewController in folder-selection mode.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()
