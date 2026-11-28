import Foundation

/// The one line a person sees when sign-in fails. The server's own text stays available as `raw`.
enum SignInFailureText {
    static let busy = "AnyRouter is busy. Try again."
    static let offline = "Could not reach AnyRouter. Check your connection and try again."
    static let declined = "Sign-in was declined."
    static let generic = "Sign-in did not work. Try again."

    static func plain(for raw: String) -> String {
        let text = raw.lowercased()
        if text == busy.lowercased() { return busy }
        let offlineMarkers = ["internet connection", "network connection", "timed out", "could not connect", "offline", "hostname could not be found"]
        if offlineMarkers.contains(where: text.contains) { return offline }
        if text.contains("access_denied") || text.contains("denied") { return declined }
        return generic
    }
}
