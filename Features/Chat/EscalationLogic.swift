import Foundation

/// "Ask a cloud model" on a reply a device model could not give (agent design X1): which cloud model, and what the
/// notice says before the chat leaves the device. Never automatic.
enum EscalationLogic {
    static let noticeTitle = String(localized: "Ask a cloud model?")
    static let noticeMessage = String(localized: """
        This chat's messages go to AnyRouter so a cloud model can answer. Memories from chats on this device stay here \
        unless you allowed them in Settings > Memory.
        """)

    /// AnyRouter's router when the account has it, else the first cloud model. Nil when none is usable.
    static func cloudModel(in models: [ModelDescriptor]) -> ModelDescriptor? {
        let cloud = models.filter { $0.source == .anyrouter && $0.isInstalled }
        return cloud.first { $0.id == ModelDescriptor.autoRouterID } ?? cloud.first
    }

    /// A reply written by Apple's model or a model downloaded to this device.
    static func isDeviceReply(modelID: String?) -> Bool {
        modelID.map { !$0.hasPrefix(ModelSource.anyrouter.rawValue + "/") } ?? false
    }

    static func confirmTitle(for model: ModelDescriptor) -> String {
        String(localized: "Ask \(model.shortName)")
    }
}
