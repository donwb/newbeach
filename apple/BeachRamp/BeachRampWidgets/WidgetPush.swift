import WidgetKit
import BeachStatus

/// iOS 26 widget push updates: WidgetKit hands the extension a push token,
/// we register it with the API, and the server sends a "content-changed"
/// push whenever the ingester sees a ramp flip — the widget reloads within
/// seconds instead of on WidgetKit's refresh budget. Older iOS keeps the
/// timed refresh plan; nothing here runs there.
@available(iOS 26.0, *)
struct BeachWidgetPushHandler: WidgetPushHandler {
    init() {}

    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let token = pushInfo.token.map { String(format: "%02x", $0) }.joined()
        // Xcode builds talk to APNs sandbox; TestFlight and App Store builds
        // to production. The server keeps one row per token and routes by
        // environment.
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        Task {
            do {
                try await APIClient.shared.registerWidgetPushToken(token, environment: environment)
            } catch {
                // Best-effort: the next token change or reload tries again.
            }
        }
    }
}
