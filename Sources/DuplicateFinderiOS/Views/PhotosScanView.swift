import SwiftUI
import Photos
import DuplicateFinderCore

struct PhotosScanView: View {
    @StateObject private var vm = PhotosScanViewModel()
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            switch vm.state {
            case .idle: idleView
            case .needsPermission: permissionView
            case .scanning: scanningView
            case .done: resultsView
            }
        }
        .navigationTitle("Photos")
        .task { vm.checkAuthorization() }
        .alert("Delete Failed", isPresented: .constant(vm.errorMessage != nil), presenting: vm.errorMessage) { _ in
            Button("OK") { vm.errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Find duplicate photos & videos").font(.title2).bold()
            Text("Scans your photo library for exact-content duplicates. Deletion goes to Recently Deleted (30-day recovery).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Form {
                Section {
                    Toggle("Photos", isOn: $vm.includePhotos)
                    Toggle("Videos", isOn: $vm.includeVideos)
                } header: {
                    Text("What to scan")
                }
            }
            .frame(maxHeight: 200)
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
            .disabled(!vm.includePhotos && !vm.includeVideos)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 40)
    }

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Photos access needed").font(.title2).bold()
            Text("DuplicateFinder needs access to your photo library to scan for duplicates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Grant Access") {
                Task { await vm.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.top, 60)
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
                .padding(.top, 40)
            Text(phaseText).font(.headline)
            VStack(spacing: 4) {
                Text("\(vm.progress.filesSeen) items seen").font(.footnote).foregroundStyle(.secondary)
                if vm.progress.candidatesToHash > 0 {
                    Text("\(vm.progress.filesHashed) / \(vm.progress.candidatesToHash) hashed")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("\(byteFormatter.string(fromByteCount: vm.progress.bytesHashed)) processed")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Cancel") { vm.cancelScan() }
                .padding(.top, 8)
            Spacer()
        }
    }

    private var phaseText: String {
        switch vm.progress.phase {
        case .walking: return "Enumerating library…"
        case .hashing: return "Hashing candidates…"
        case .finalizing: return "Finalizing…"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    private var resultsView: some View {
        Group {
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
                            Button("Keep oldest, select rest") { vm.keepOldestInAllGroups() }
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
                                    PhotoRow(file: file, selected: vm.selection.contains(file.assetIdentifier ?? "")) {
                                        toggle(file)
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
                                confirmingDelete = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Move \(vm.selection.count) to Recently Deleted")
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
                    "Move \(vm.selection.count) items to Recently Deleted?",
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Move to Recently Deleted", role: .destructive) {
                        Task { await vm.performDelete() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Frees \(byteFormatter.string(fromByteCount: vm.selectedBytes)). You can restore them from Photos → Albums → Recently Deleted within 30 days.")
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
    }

    private var safetyOK: Bool { vm.groupsWithAllFilesSelected().isEmpty }

    private func toggle(_ file: FileEntry) {
        guard let id = file.assetIdentifier else { return }
        if vm.selection.contains(id) { vm.selection.remove(id) } else { vm.selection.insert(id) }
    }
}

private struct PhotoRow: View {
    let file: FileEntry
    let selected: Bool
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Group {
                    if let img = thumbnail {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(shortDate(file.modifiedAt)).font(.subheadline)
                    Text(file.kind == .video ? "Video" : "Photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .task { await loadThumbnail() }
    }

    private func shortDate(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func loadThumbnail() async {
        guard let id = file.assetIdentifier else { return }
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        guard let asset else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .fastFormat
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false
        let mgr = PHImageManager.default()
        let img: UIImage? = await withCheckedContinuation { cont in
            mgr.requestImage(for: asset, targetSize: CGSize(width: 168, height: 168),
                             contentMode: .aspectFill, options: opts) { image, _ in
                cont.resume(returning: image)
            }
        }
        await MainActor.run { self.thumbnail = img }
    }
}

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()
