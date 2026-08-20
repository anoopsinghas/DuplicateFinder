import SwiftUI

struct ScanConfigView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan configuration").font(.title2).bold()

            GroupBox("Scan roots") {
                VStack(alignment: .leading) {
                    List {
                        ForEach(vm.roots, id: \.self) { r in
                            HStack {
                                Image(systemName: "folder")
                                Text(r.path).font(.caption).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .onDelete { vm.removeRoots(atOffsets: $0) }
                    }
                    .frame(minHeight: 100, maxHeight: 200)

                    HStack {
                        Button("Add folder…", action: pickFolder)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Media kinds") {
                Toggle("Photos", isOn: $vm.scanPhotos)
                Toggle("Videos", isOn: $vm.scanVideos)
                Toggle("Documents", isOn: $vm.scanDocuments)
            }

            GroupBox("Filters") {
                HStack {
                    Text("Minimum size:")
                    TextField("bytes", value: $vm.minSizeBytes, formatter: NumberFormatter())
                        .frame(width: 100)
                    Text("bytes")
                }
            }

            Spacer()

            Button {
                vm.startScan()
            } label: {
                Label("Start scan", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(vm.roots.isEmpty || vm.kinds.isEmpty || vm.state == .scanning)
        }
        .padding()
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { vm.addRoot(url) }
        }
    }
}
