import SwiftUI

struct ScanProgressView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text(headline).font(.title).bold()
            ProgressView(value: fractionComplete)
                .progressViewStyle(.linear)
                .frame(maxWidth: 500)

            VStack(alignment: .leading, spacing: 6) {
                labeled("Files seen", value: "\(vm.progress.filesSeen)")
                labeled("Candidates to hash", value: "\(vm.progress.candidatesToHash)")
                labeled("Files hashed", value: "\(vm.progress.filesHashed)")
                labeled("Bytes hashed", value: humanBytes(vm.progress.bytesHashed))
                if let p = vm.progress.currentPath {
                    labeled("Current", value: p, mono: true)
                }
            }
            .frame(maxWidth: 700)

            Button(role: .destructive) {
                vm.cancelScan()
            } label: {
                Label("Cancel", systemImage: "xmark.circle.fill")
            }
        }
        .padding()
    }

    private var headline: String {
        switch vm.progress.phase {
        case .walking: return "Walking directories…"
        case .hashing: return "Hashing candidates…"
        case .finalizing: return "Finalizing…"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    private var fractionComplete: Double? {
        if vm.progress.candidatesToHash == 0 { return nil }
        return Double(vm.progress.filesHashed) / Double(vm.progress.candidatesToHash)
    }

    @ViewBuilder
    private func labeled(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 180, alignment: .trailing)
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .lineLimit(2).truncationMode(.middle)
        }
    }
}

func humanBytes(_ n: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = Double(n); var u = 0
    while v >= 1024 && u < units.count - 1 { v /= 1024; u += 1 }
    return String(format: v < 10 ? "%.2f %@" : "%.1f %@", v, units[u])
}
