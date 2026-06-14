import Foundation
import AppKit

/// Orchestrates a rewrite. Two modes:
///  - Popup (main shortcut): all styles requested in parallel; the first
///    style is applied the moment it arrives, the popup fills in the rest.
///  - Quick (per-style shortcut): one style, applied silently — no popup.
@MainActor
final class RewritePipeline: ObservableObject {
    static let shared = RewritePipeline()

    @Published var isRunning = false
    @Published var lastError: String?

    private let capture = TextCapture()
    private var currentHistoryID: UUID?
    private var original: String = ""
    private var variantsByCategory: [String: RewriteVariant] = [:]

    func run(quick category: RewriteCategory? = nil) {
        guard !isRunning else { return }
        Task { await runInternal(quick: category) }
    }

    private func runInternal(quick: RewriteCategory?) async {
        Log.write("pipeline: triggered (quick=\(quick?.name ?? "no"), enabled=\(AppState.shared.isEnabled), connected=\(ClaudeAuth.shared.isConnected))")
        guard AppState.shared.isEnabled else { return }
        guard ClaudeAuth.shared.isConnected else {
            showError(RecastError.notConnected.localizedDescription)
            return
        }

        isRunning = true
        lastError = nil
        defer { isRunning = false }

        do {
            let captured = try await capture.capture()
            original = captured.text
            Log.write("pipeline: captured \(captured.text.count) chars from \(captured.appName) (mode=\(captured.mode), ax=\(captured.usedAX))")

            let model = UserDefaults.standard.string(forKey: "rewriteModel") ?? "claude-haiku-4-5"

            if let quick {
                try await runQuick(captured: captured, category: quick, model: model)
            } else {
                await runPopup(captured: captured, model: model)
            }
        } catch {
            Log.write("pipeline: ERROR \(error.localizedDescription)")
            capture.finish()
            showError(error.localizedDescription)
        }
    }

    // MARK: - Quick mode (no popup, no confirmation)

    private func runQuick(captured: CapturedText, category: RewriteCategory, model: String) async throws {
        let variant = try await RewriteService.rewrite(text: captured.text, category: category, model: model)
        try await capture.apply(variant.text)
        capture.finish()
        Log.write("pipeline: quick-applied \(category.name)")

        HistoryStore.shared.add(HistoryEntry(
            date: Date(),
            appName: captured.appName,
            original: captured.text,
            variants: [variant],
            pickedCategory: category.name
        ))
    }

    // MARK: - Popup mode

    private func runPopup(captured: CapturedText, model: String) async {
        let categories = CategoriesStore.shared.categories
        let panelModel = PanelModel(original: captured.text, categories: categories.map(\.name))
        variantsByCategory = [:]
        currentHistoryID = nil

        SuggestionPanelController.shared.show(
            model: panelModel,
            onPick: { [weak self] category in
                Task { await self?.pick(category) }
            },
            onRevert: { [weak self] in
                Task { await self?.revert() }
            },
            onDismiss: { [weak self] in
                self?.capture.finish()
            }
        )

        await withTaskGroup(of: (Int, Result<RewriteVariant, Error>).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask {
                    do {
                        let variant = try await RewriteService.rewrite(text: captured.text, category: category, model: model)
                        return (index, .success(variant))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            for await (index, result) in group {
                switch result {
                case .success(let variant):
                    variantsByCategory[variant.category] = variant
                    panelModel.setText(variant.text, at: index)
                    // Apply the first style as soon as it lands — don't wait
                    // for the others.
                    if index == 0 {
                        try? await capture.apply(variant.text)
                        panelModel.selectedCategory = variant.category
                        Log.write("pipeline: applied first variant (\(variant.category))")
                    }
                case .failure(let error):
                    Log.write("pipeline: variant '\(categories[index].name)' failed: \(error.localizedDescription)")
                    panelModel.setFailed(at: index)
                }
            }
        }

        guard !variantsByCategory.isEmpty else {
            capture.finish()
            showError("All rewrites failed — check your connection and try again.")
            return
        }
        Log.write("pipeline: \(variantsByCategory.count)/\(categories.count) variants ready")

        let entry = HistoryEntry(
            date: Date(),
            appName: captured.appName,
            original: captured.text,
            variants: categories.compactMap { variantsByCategory[$0.name] },
            pickedCategory: panelModel.selectedCategory
        )
        HistoryStore.shared.add(entry)
        currentHistoryID = entry.id
    }

    private func pick(_ category: String) async {
        guard let variant = variantsByCategory[category] else { return }
        do {
            try await capture.apply(variant.text)
            if let id = currentHistoryID {
                HistoryStore.shared.updatePick(id: id, category: category)
            }
        } catch {
            showError(error.localizedDescription)
        }
        capture.finish()
        SuggestionPanelController.shared.close()
    }

    private func revert() async {
        do {
            try await capture.revert(to: original)
            if let id = currentHistoryID {
                HistoryStore.shared.updatePick(id: id, category: nil)
            }
        } catch {
            showError(error.localizedDescription)
        }
        capture.finish()
        SuggestionPanelController.shared.close()
    }

    private func showError(_ message: String) {
        lastError = message
        SuggestionPanelController.shared.showError(message)
    }
}
