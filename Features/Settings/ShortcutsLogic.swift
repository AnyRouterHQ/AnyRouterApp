import Foundation

/// What the "Shortcuts & Controls" page lists: the ways to reach AnyRouter from outside the app, each with how to add it.
/// Names match the App Shortcuts, controls and share extension in the repo.
enum ShortcutsLogic {
    struct Feature: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let symbol: String
        let summary: String
        let howToAdd: String
    }

    static let features: [Feature] = [
        Feature(
            title: "Siri and Shortcuts",
            symbol: "square.stack.3d.up",
            summary: "Ask AnyRouter, Fix my English, New chat and Start voice work with Siri and Spotlight. Shortcuts also gets Run preset, Summarize, Translate and Ask with model.",
            howToAdd: "Say \"Ask AnyRouter\" to Siri, or open Shortcuts and search for AnyRouter."),
        Feature(
            title: "Control Center and Lock Screen",
            symbol: "switch.2",
            summary: "Controls for New chat, Voice and Paste & fix.",
            howToAdd: "Touch and hold Control Center or the Lock Screen, tap Add a Control, then choose AnyRouter."),
        Feature(
            title: "Action Button",
            symbol: "button.horizontal.top.press",
            summary: "Start a new chat or start voice with one press.",
            howToAdd: "Open the Settings app, tap Action Button, choose Shortcut, then pick New chat or Start voice from AnyRouter."),
        Feature(
            title: "Share sheet",
            symbol: "square.and.arrow.up",
            summary: "Send text, links, PDFs and images from any app to AnyRouter.",
            howToAdd: "Tap Share in an app and choose Ask AnyRouter. If it is missing, tap More and turn it on."),
        Feature(
            title: "Read text from a photo",
            symbol: "text.viewfinder",
            summary: "Read the text in a photo on the device, then translate, summarize or split a bill.",
            howToAdd: "In a chat tap the plus button, choose Read text, then Camera or Photos."),
    ]
}
