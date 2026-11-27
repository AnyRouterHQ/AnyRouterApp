// Prints the window number of the first normal on-screen window owned by the named app, for screencapture -l.
// Usage: swift scripts/mac-window-id.swift <owner name>. Exits 1 when the app has no window yet.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments[1]
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
let match = windows?.first {
    $0[kCGWindowOwnerName as String] as? String == owner && $0[kCGWindowLayer as String] as? Int == 0
}
guard let number = match?[kCGWindowNumber as String] as? Int else { exit(1) }
print(number)
