import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        HotkeyManager.shared.reload()

        // Re-register hotkeys when styles (and their shortcuts) change.
        CategoriesStore.shared.$categories
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { _ in
                Task { @MainActor in HotkeyManager.shared.reload() }
            }
            .store(in: &cancellables)
    }
}
