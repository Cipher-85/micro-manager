import Foundation
import WLKit

/// Closes the focused pane, tab, or workspace after a land-style confirm.
///
/// The close key is deliberately two presses: the first shows what would be
/// closed, the second runs it. Closing is not easily reversible, so a single
/// stray key press must never do it. Any other pad key while the confirmation
/// is up cancels — reaching for a different key is the closest thing a pad
/// has to "no".
@MainActor
final class ClosePanelController {

    static let shared = ClosePanelController()

    enum Phase {
        case idle
        /// Window up, still working out what would be closed. The close key is
        /// ignored here: confirming a target you have not seen is not consent.
        case loading
        case confirming
        case running
        case finished
    }

    private(set) var phase: Phase = .idle
    /// The herdr name being confirmed, if any.
    private(set) var armed: String?
    var isConfirming: Bool { phase == .loading || phase == .confirming }

    private let panel = FloatingPanel()
    private var targetID: String?
    private var generation = 0

    init() {
        panel.preferredWidth = 460
        panel.onDismissRequested = { [weak self] in
            guard let self, self.phase != .running else { return }
            self.close()
        }
    }

    // MARK: - Key handling

    /// The mapped close action: opens the confirmation, confirms it, or
    /// dismisses the finished report. Ignored while a close is running.
    func handleCloseKey(_ name: String) {
        switch phase {
        case .idle: openConfirmation(name)
        case .loading: break
        case .confirming:
            guard name == armed else { return }
            Task { await runClose() }
        case .running: break
        case .finished: close()
        }
    }

    /// Any other pad key. Returns true when the press cancelled the pending
    /// confirmation, in which case it must not also do its usual job.
    func handleOtherKey() -> Bool {
        switch phase {
        case .loading, .confirming:
            close()
            return true
        case .idle, .running, .finished:
            return false
        }
    }

    func close() {
        panel.close()
        phase = .idle
        armed = nil
        targetID = nil
        generation += 1
    }

    // MARK: - Confirmation

    private func openConfirmation(_ name: String) {
        phase = .loading
        armed = name
        panel.present()
        panel.render(title: "…", subtitle: "", body: PanelHTML.note("Looking up…"), footer: "")
        generation += 1
        let generation = self.generation
        Task { [weak self] in
            let prepared = await Self.prepare(name)
            guard let self, self.generation == generation, self.phase == .loading else { return }
            switch prepared {
            case .blocked(let title, let message):
                self.phase = .finished
                self.panel.render(
                    title: title,
                    subtitle: "",
                    body: PanelHTML.note(message),
                    footer: "press the same key again to dismiss"
                )
            case .ready(let title, let kind, let targetID):
                self.targetID = targetID
                self.phase = .confirming
                self.panel.render(
                    title: title,
                    subtitle: "",
                    body: "<pre>will close this \(kind):\n\n  "
                        + AnsiHTML.escapeHTML(title) + "</pre>",
                    footer: "press the same key again to close — any other key cancels"
                )
            }
        }
    }

    private enum Preparation {
        case blocked(title: String, message: String)
        case ready(title: String, kind: String, targetID: String)
    }

    private static func prepare(_ name: String) async -> Preparation {
        do {
            switch name {
            case "close_pane":
                guard let agent = try await HerdrClient.focusedAgent() else {
                    return .blocked(
                        title: "No focused agent",
                        message: "Nothing has focus in Herdr right now."
                    )
                }
                guard let paneID = agent.paneID, !paneID.isEmpty else {
                    return .blocked(
                        title: agent.shortName,
                        message: "Herdr did not report a pane id for this agent."
                    )
                }
                return .ready(title: agent.shortName, kind: "pane", targetID: paneID)
            case "close_tab":
                guard let tab = try await HerdrClient.listTabs().first(where: \.focused) else {
                    return .blocked(
                        title: "No focused tab",
                        message: "Nothing has focus in Herdr right now."
                    )
                }
                let title = tab.label.isEmpty ? "Tab \(tab.number)" : tab.label
                return .ready(title: title, kind: "tab", targetID: tab.tabID)
            case "close_workspace":
                guard let workspace = try await HerdrClient.listWorkspaces().first(where: \.focused) else {
                    return .blocked(
                        title: "No focused workspace",
                        message: "Nothing has focus in Herdr right now."
                    )
                }
                let title = workspace.label.isEmpty ? workspace.workspaceID : workspace.label
                return .ready(title: title, kind: "workspace", targetID: workspace.workspaceID)
            default:
                return .blocked(title: "Herdr", message: "Unknown close action.")
            }
        } catch {
            return .blocked(title: "Herdr", message: error.localizedDescription)
        }
    }

    // MARK: - Close

    private func runClose() async {
        guard phase == .confirming, let armed, let targetID else { return }
        phase = .running
        generation += 1
        let generation = self.generation
        panel.render(title: "…", subtitle: "", body: "", footer: "closing…")

        do {
            switch armed {
            case "close_pane":
                try await HerdrClient.closePane(paneID: targetID)
            case "close_tab":
                try await HerdrClient.closeTab(tabID: targetID)
            case "close_workspace":
                try await HerdrClient.closeWorkspace(workspaceID: targetID)
            default:
                break
            }
            panel.append(PanelHTML.note("Closed."))
        } catch {
            panel.append(PanelHTML.note(error.localizedDescription))
        }

        guard self.generation == generation else { return }
        phase = .finished
        panel.setFooter("press the same key again to dismiss")
    }
}
