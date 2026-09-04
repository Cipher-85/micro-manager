import Foundation

/// Shared names and labels for pad actions. The Keys editor and the menu
/// both read this so a new dispatched herdr name only has to be listed once.
public enum PadCatalog {

    public static let herdrNames = [
        "next_tab",
        "previous_tab",
        "new_tab",
        "zoom",
        "split_vertical",
        "split_horizontal",
        "focus_pane_left",
        "focus_pane_right",
        "focus_pane_up",
        "focus_pane_down",
        "next_workspace",
        "previous_workspace",
    ]

    public static func herdrHelp(_ name: String) -> String {
        switch name {
        case "next_tab": return "Cycle tabs in the focused Herdr window"
        case "previous_tab": return "Previous tab in the focused Herdr window"
        case "new_tab": return "New tab in the focused Herdr window"
        case "zoom": return "Zoom the focused pane"
        case "split_vertical": return "Split the focused pane right"
        case "split_horizontal": return "Split the focused pane down"
        case "focus_pane_left": return "Focus the pane to the left"
        case "focus_pane_right": return "Focus the pane to the right"
        case "focus_pane_up": return "Focus the pane above"
        case "focus_pane_down": return "Focus the pane below"
        case "next_workspace": return "Next Herdr workspace"
        case "previous_workspace": return "Previous Herdr workspace"
        default: return "Herdr: \(name)"
        }
    }

    public static func herdrTitle(_ name: String) -> String {
        switch name {
        case "next_tab": return "Next tab"
        case "previous_tab": return "Previous tab"
        case "new_tab": return "New tab"
        case "zoom": return "Zoom pane"
        case "split_vertical": return "Split right"
        case "split_horizontal": return "Split down"
        case "focus_pane_left": return "Focus left"
        case "focus_pane_right": return "Focus right"
        case "focus_pane_up": return "Focus up"
        case "focus_pane_down": return "Focus down"
        case "next_workspace": return "Next workspace"
        case "previous_workspace": return "Previous workspace"
        default: return name
        }
    }

    public static func shortLabel(_ action: PadAction) -> String {
        switch action {
        case .focusSlot(let slot): return "\(slot)"
        case .herdr: return "H"
        case .injectPrompt: return "M"
        case .gitButlerStatus: return "S"
        case .gitButlerLand: return "L"
        case .voice: return "V"
        case .effort(let step) where step > 0: return "+"
        case .effort: return "−"
        case .model(.north): return "N"
        case .model(.west): return "W"
        case .model(.south): return "S"
        case .model(.east): return "E"
        case .unbound: return ""
        }
    }
}
