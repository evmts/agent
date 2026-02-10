import Observation

@Observable @MainActor
final class AppModel {
    var theme: AppTheme = .dark
}
