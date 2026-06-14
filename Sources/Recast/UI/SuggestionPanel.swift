import AppKit
import SwiftUI
import Combine

/// Observable state for the suggestion popup. The pipeline fills variants in
/// as their parallel requests complete.
@MainActor
final class PanelModel: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let category: String
        var text: String?
        var failed = false
    }

    @Published var original: String
    @Published var items: [Item]
    @Published var selectedCategory: String?

    init(original: String, categories: [String]) {
        self.original = original
        self.items = categories.map { Item(category: $0) }
    }

    func setText(_ text: String, at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].text = text
    }

    func setFailed(at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].failed = true
    }
}

/// Floating, non-activating panel shown near the cursor. Non-activating means
/// focus stays in the app you're typing in.
@MainActor
final class SuggestionPanelController {
    static let shared = SuggestionPanelController()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var resizeCancellable: AnyCancellable?
    private var onDismiss: (() -> Void)?

    func show(
        model: PanelModel,
        onPick: @escaping (String) -> Void,
        onRevert: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        let view = SuggestionsView(
            model: model,
            onPick: onPick,
            onRevert: onRevert,
            onKeep: { [weak self] in self?.close() }
        )
        present(content: AnyView(view), near: NSEvent.mouseLocation)

        // Resize the panel as variants stream in.
        resizeCancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }

        // Esc reverts to the original.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                onRevert()
            }
        }
    }

    func showError(_ message: String) {
        present(
            content: AnyView(ErrorView(message: message, onClose: { [weak self] in self?.close() })),
            near: panel == nil ? NSEvent.mouseLocation : nil
        )
    }

    func close() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        resizeCancellable = nil
        onDismiss?()
        onDismiss = nil
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
    }

    // MARK: - Private

    private func present(content: AnyView, near point: NSPoint?) {
        let hosting = NSHostingController(rootView: content)
        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.contentViewController = hosting
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = hosting
            self.panel = panel
        }

        panel.setContentSize(hosting.view.fittingSize)
        if let point {
            position(panel, near: point)
        }
        panel.orderFrontRegardless()
    }

    private func resizeToFit() {
        guard let panel, let hosting = panel.contentViewController else { return }
        let newSize = hosting.view.fittingSize
        guard newSize.height > 0, abs(newSize.height - panel.frame.height) > 2 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - newSize.height // keep top edge fixed
        frame.size = newSize
        panel.setFrame(frame, display: true, animate: false)
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return }
        var origin = NSPoint(x: point.x + 16, y: point.y - panel.frame.height - 16)
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }
}

// MARK: - Views

private struct ErrorView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recast", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
                Button("OK", action: onClose)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct SuggestionsView: View {
    @ObservedObject var model: PanelModel
    let onPick: (String) -> Void
    let onRevert: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Original", systemImage: "text.quote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.original)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            ForEach(model.items) { item in
                if let text = item.text {
                    variantButton(category: item.category, text: text)
                } else if item.failed {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                        Text("\(item.category) — couldn't generate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(item.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                }
            }

            HStack {
                Button("Revert to original (Esc)", action: onRevert)
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                Button("Keep", action: onKeep)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    @ViewBuilder
    private func variantButton(category: String, text: String) -> some View {
        let isSelected = category == model.selectedCategory
        Button {
            model.selectedCategory = category
            onPick(category)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                }
                Text(text)
                    .font(.callout)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
