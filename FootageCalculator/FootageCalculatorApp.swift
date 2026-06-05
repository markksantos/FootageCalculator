import SwiftUI

@main
struct FootageCalculatorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Persist the window frame across launches. AppKit restores the
                // saved frame for any window with a stable autosave name.
                .background(WindowFrameAutosaver(name: "FootageCalculatorMain"))
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 520, height: 520)
        .commands {
            // Replace the default New Window item — this is a single-window utility.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Attaches a frame autosave name to the hosting `NSWindow` so its size and
/// position are restored on the next launch.
private struct WindowFrameAutosaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
