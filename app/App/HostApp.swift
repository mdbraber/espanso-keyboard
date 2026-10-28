import OSLog
import UIKit

/// Opens the app you were typing in, which the keyboard names in its `Dictation.Request`. `LSApplicationWorkspace`
/// isn't API: where it won't open the app by its bundle ID, the app's own link does, and with neither the dictation
/// screen stays up for you to swipe back.
enum HostApp {
    static let log = Logger(subsystem: "com.shahidy.hexkeyboard", category: "voice")

    static func open(_ bundle: String) async -> Bool {
        if openByID(bundle) { return true }
        guard let link = links[bundle].flatMap(URL.init(string:)) else { return false }
        log.notice("opening \(bundle, privacy: .public) by link")
        return await UIApplication.shared.open(link)
    }

    private static func openByID(_ bundle: String) -> Bool {
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = type.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
              workspace.responds(to: selector)
        else { return false }
        typealias Open = @convention(c) (NSObject, Selector, NSString) -> Bool
        return unsafeBitCast(workspace.method(for: selector), to: Open.self)(workspace, selector, bundle as NSString)
    }

    /// Links that bring each app back where you were rather than performing an action, from Dictus's `KnownAppSchemes`
    /// (MIT), which measured them: Messages comes back to the conversation only by `ichat://` (`sms://` opens a new
    /// message), and every Safari link opens a blank page or search, so Safari has none.
    private static let links = [
        "ph.telegra.Telegraph": "tg://",
        "net.whatsapp.WhatsApp": "whatsapp-consumer://",
        "com.apple.MobileSMS": "ichat://",
        "com.apple.mobilemail": "message://",
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.reminders": "x-apple-reminderkit://",
        "com.atebits.Tweetie2": "twitter://",
        "com.hammerandchisel.discord": "discord://",
        "com.tinyspeck.chatlyio": "slack://open",
        "com.google.Gmail": "googlegmail://",
        "com.google.chrome.ios": "googlechrome://",
        "com.burbn.instagram": "instagram://",
        "com.facebook.Messenger": "fb-messenger://",
        "org.whispersystems.signal": "sgnl://",
        "com.openai.chat": "com.openai.chat://",
        "com.anthropic.claude": "claude://",
        "com.t3tools.t3code": "t3code://",
        "com.github.stormbreaker.prod": "github://",
        "notion.id": "notion://",
    ]
}
