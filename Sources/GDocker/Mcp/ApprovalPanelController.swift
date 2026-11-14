import AppKit
import Observation
import SwiftUI

/// Shows the approval prompt in a floating panel whenever a request is waiting, and hides it when none is. It is an
/// AppKit panel rather than a SwiftUI scene so it can appear with the main window closed (menu bar mode).
@MainActor
final class ApprovalPanelController {
    private let model: ApprovalModel
    private var panel: NSPanel?

    init(model: ApprovalModel) { self.model = model }

    func start() { observe() }

    func focus() {
        update()
    }

    private func observe() {
        withObservationTracking {
            _ = model.pending.map(\.id)
        } onChange: { [weak self] in
            // onChange runs before the new value lands; look again on the next turn.
            Task { @MainActor in self?.observe() }
        }
        update()
    }

    private func update() {
        guard model.current != nil else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let hosting = panel.contentViewController { panel.setContentSize(hosting.view.fittingSize) }
        if !panel.isVisible { panel.center() }
        // Never take focus: the request is triggered by an AI, not by the user, so a key they happen to be
        // pressing (Return, Space) must not land on the prompt and approve something. Only a mouse click answers.
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = Bundle.l10n.localizedString(forKey: "Approval request", value: nil, table: nil)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        // No close button: the only ways out are answering or the request timing out, so nothing is left dangling.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.contentViewController = NSHostingController(rootView: ApprovalView(model: model))
        return panel
    }
}
