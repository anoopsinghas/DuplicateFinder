import SwiftUI
import AppKit
import DuplicateFinderCore

@main
struct DuplicateFinderMacApp: App {
    var body: some Scene {
        WindowGroup("DuplicateFinder") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    positionMainWindow()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}

private func positionMainWindow() {
    DispatchQueue.main.async {
        guard let win = NSApp.windows.first(where: { $0.title == "DuplicateFinder" || !$0.title.isEmpty }) ?? NSApp.windows.first else {
            return
        }
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let w: CGFloat = 1100
            let h: CGFloat = 720
            let x = sf.midX - w / 2
            let y = sf.midY - h / 2
            win.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ContentView: View {
    @StateObject private var vm = ScanViewModel()

    var body: some View {
        NavigationSplitView {
            ScanConfigView(vm: vm)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            switch vm.state {
            case .idle:
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Ready to scan").font(.title2).bold()
                    Text("Pick scan roots on the left, then hit Start.")
                        .foregroundStyle(.secondary)
                }
            case .scanning:
                ScanProgressView(vm: vm)
            case .done:
                DuplicatesListView(vm: vm)
            }
        }
    }
}
