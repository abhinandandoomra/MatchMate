import Foundation

/// The app's navigation vocabulary. `Hashable` so it can drive a
/// `NavigationStack` path owned by the ViewModel rather than by the view.
enum Route: Hashable {
    case detail(uuid: String)
}
