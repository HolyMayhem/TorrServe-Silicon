import Foundation

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
