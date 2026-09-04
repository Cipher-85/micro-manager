import AppKit
import SwiftUI
import WLKit

/// A titled window for remapping pad keys. Not the Inspector, and not a
/// floating HTML panel — a clickable editor you can leave open.
@MainActor
final class KeysMapWindowController: NSObject, NSWindowDelegate {
    static let shared = KeysMapWindowController()

    private var window: NSWindow?

    func show(bridge: BridgeController) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keys"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(
            rootView: KeysMapView().environmentObject(bridge)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

private enum FormKind: String, CaseIterable, Identifiable {
    case unbound, agent, herdr, macro, stack, land, voice
    case effortPlus, effortMinus
    case modelNorth, modelWest, modelSouth, modelEast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unbound: return "Unbound"
        case .agent: return "Agent slot"
        case .herdr: return "Herdr"
        case .macro: return "Macro"
        case .stack: return "GitButler stack"
        case .land: return "GitButler land"
        case .voice: return "Voice"
        case .effortPlus: return "Effort +1"
        case .effortMinus: return "Effort −1"
        case .modelNorth: return "Model N"
        case .modelWest: return "Model W"
        case .modelSouth: return "Model S"
        case .modelEast: return "Model E"
        }
    }

    init(_ action: PadAction) {
        switch action {
        case .unbound: self = .unbound
        case .focusSlot: self = .agent
        case .herdr: self = .herdr
        case .injectPrompt: self = .macro
        case .gitButlerStatus: self = .stack
        case .gitButlerLand: self = .land
        case .voice: self = .voice
        case .effort(let step) where step >= 0: self = .effortPlus
        case .effort: self = .effortMinus
        case .model(.north): self = .modelNorth
        case .model(.west): self = .modelWest
        case .model(.south): self = .modelSouth
        case .model(.east): self = .modelEast
        }
    }
}

struct KeysMapView: View {
    @EnvironmentObject var bridge: BridgeController
    @State private var draft = PadMap()
    @State private var lastApplied = PadMap()
    @State private var selected = 1
    @State private var kind: FormKind = .agent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pad
            extras
            Divider()
            form
            Divider()
            buttons
        }
        .padding(14)
        .frame(minWidth: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadFromBridge() }
        .onChange(of: selected) { _ in
            kind = FormKind(draft.action(for: selected))
        }
        .onChange(of: bridge.padMap) { newMap in
            if draft == lastApplied {
                draft = newMap
                kind = FormKind(draft.action(for: selected))
            }
            lastApplied = newMap
        }
    }

    private var pad: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Pad.displayRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { id in keyCell(id) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var extras: some View {
        HStack(spacing: 6) {
            Text("Dial").font(.caption).foregroundStyle(.secondary)
            keyCell(13, caption: "cw")
            keyCell(14, caption: "ccw")
            Spacer(minLength: 8)
            Text("Stick").font(.caption).foregroundStyle(.secondary)
            keyCell(15, caption: "n")
            keyCell(16, caption: "w")
            keyCell(17, caption: "s")
            keyCell(18, caption: "e")
        }
    }

    private func keyCell(_ id: Int, caption: String? = nil) -> some View {
        let action = draft.action(for: id)
        let label = caption ?? PadCatalog.shortLabel(action)
        let isSelected = selected == id
        return Button {
            selected = id
        } label: {
            VStack(spacing: 1) {
                Text(label.isEmpty ? "·" : label)
                    .font(.system(.caption, design: .monospaced))
                if caption != nil {
                    Text(PadCatalog.shortLabel(action))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: caption == nil ? 26 : 32)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(bridge.keyColors[id] ?? Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .help(help(for: action))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key \(selected)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Action", selection: kindBinding) {
                ForEach(FormKind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if kind == .agent {
                Picker("Slot", selection: slotBinding) {
                    ForEach(0...5, id: \.self) { slot in
                        Text("\(slot)").tag(slot)
                    }
                }
            }
            if kind == .herdr {
                Picker("Herdr", selection: herdrBinding) {
                    ForEach(PadCatalog.herdrNames, id: \.self) { name in
                        Text(PadCatalog.herdrTitle(name)).tag(name)
                    }
                }
            }
            if kind == .macro {
                TextField("Prompt", text: macroBinding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var buttons: some View {
        HStack {
            Button("Revert") { loadFromBridge() }
            Button("Defaults") {
                draft = PadMap()
                kind = FormKind(draft.action(for: selected))
            }
            Spacer()
            if draft != bridge.padMap {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Save") {
                Task { await bridge.replacePadMap(draft) }
            }
        }
    }

    private var kindBinding: Binding<FormKind> {
        Binding(
            get: { kind },
            set: { kind = $0; apply($0) }
        )
    }

    private var slotBinding: Binding<Int> {
        Binding(
            get: {
                if case .focusSlot(let slot) = draft.action(for: selected) { return slot }
                return 0
            },
            set: { draft.set(.focusSlot($0), for: selected) }
        )
    }

    private var herdrBinding: Binding<String> {
        Binding(
            get: {
                if case .herdr(let name) = draft.action(for: selected) { return name }
                return "next_tab"
            },
            set: { draft.set(.herdr($0), for: selected) }
        )
    }

    private var macroBinding: Binding<String> {
        Binding(
            get: {
                if case .injectPrompt(let text) = draft.action(for: selected) { return text }
                return ""
            },
            set: { text in
                draft.set(text.isEmpty ? .unbound : .injectPrompt(text), for: selected)
            }
        )
    }

    private func apply(_ kind: FormKind) {
        let current = draft.action(for: selected)
        let action: PadAction
        switch kind {
        case .unbound:
            action = .unbound
        case .agent:
            if case .focusSlot(let slot) = current { action = .focusSlot(slot) }
            else { action = .focusSlot(0) }
        case .herdr:
            if case .herdr(let name) = current, PadCatalog.herdrNames.contains(name) {
                action = .herdr(name)
            } else {
                action = .herdr("next_tab")
            }
        case .macro:
            if case .injectPrompt(let text) = current, !text.isEmpty {
                action = .injectPrompt(text)
            } else {
                action = .unbound
            }
        case .stack:
            action = .gitButlerStatus
        case .land:
            action = .gitButlerLand
        case .voice:
            action = .voice
        case .effortPlus:
            action = .effort(step: 1)
        case .effortMinus:
            action = .effort(step: -1)
        case .modelNorth:
            action = .model(.north)
        case .modelWest:
            action = .model(.west)
        case .modelSouth:
            action = .model(.south)
        case .modelEast:
            action = .model(.east)
        }
        draft.set(action, for: selected)
    }

    private func loadFromBridge() {
        draft = bridge.padMap
        lastApplied = bridge.padMap
        kind = FormKind(draft.action(for: selected))
    }

    private func help(for action: PadAction) -> String {
        switch action {
        case .herdr(let name):
            return PadCatalog.herdrHelp(name)
        case .focusSlot(let slot):
            return "Agent slot \(slot)"
        case .injectPrompt(let text):
            return "Type: \(text)"
        case .gitButlerStatus:
            return "GitButler stack for the focused agent"
        case .gitButlerLand:
            return "Land the focused agent's branches onto the target"
        case .voice:
            return "Right command — start or stop Superwhisper"
        case .effort(let step):
            return "Reasoning effort \(step > 0 ? "+1" : "−1")"
        case .model(let direction):
            return "Model \(PadCatalog.shortLabel(.model(direction)))"
        case .unbound:
            return "Unbound"
        }
    }
}
