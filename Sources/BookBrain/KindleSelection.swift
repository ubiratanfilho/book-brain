import AppKit
import BookBrainCore
import Carbon.HIToolbox

enum KindleSelection {
  static let bundleID = "com.amazon.Lassen"

  @MainActor
  static func copy(in kindle: NSRunningApplication) throws {
    // The window must stay in Kindle until it has published the selection.
    guard kindle.bundleIdentifier == bundleID, !kindle.isTerminated,
      kindle == NSWorkspace.shared.frontmostApplication
    else {
      throw BookBrainError.message("Return to Kindle, select a passage, and press ⌘⇧B.")
    }

    guard let source = CGEventSource(stateID: .privateState),
      let down = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
      let up = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
    else { throw BookBrainError.message("macOS couldn't send the Copy command to Kindle.") }

    // Use only Command, even if Shift is still held from the global shortcut.
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.postToPid(kindle.processIdentifier)
    up.postToPid(kindle.processIdentifier)
  }
}
