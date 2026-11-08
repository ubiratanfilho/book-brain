import AppKit
import SwiftUI
import XCTest

@testable import BookBrain

@MainActor
final class QuestionFieldTests: XCTestCase {
  func testReturnSubmitsAndShiftReturnReplacesSelectionWithANewline() throws {
    for compact in [false, true] {
      var draft = "first OLDlast"
      var sent: [String] = []
      let field = QuestionField(
        text: Binding(get: { draft }, set: { draft = $0 }), compact: compact,
        send: { sent.append(draft) })
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: compact ? 350 : 600, height: 100),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.alphaValue = 0
      window.contentView = NSHostingView(rootView: field)
      window.orderBack(nil)
      defer { window.orderOut(nil) }
      window.contentView?.layoutSubtreeIfNeeded()
      window.selectNextKeyView(nil)
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
      editor.setSelectedRange((draft as NSString).range(of: "OLD"))

      try pressReturn(in: window, modifiers: .shift)
      XCTAssertEqual(draft, "first \nlast")
      XCTAssertTrue(sent.isEmpty)

      try pressReturn(in: window)
      XCTAssertEqual(sent, ["first \nlast"])
      XCTAssertEqual(draft, "first \nlast")
    }
  }

  // Dispatch through the test application's own event queue so the field editor
  // receives a normal key event, without posting keys to any other application.
  private func pressReturn(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: modifiers,
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
          keyCode: 36))
      NSApp.postEvent(event, atStart: true)
      let next = try XCTUnwrap(
        NSApp.nextEvent(
          matching: type == .keyDown ? .keyDown : .keyUp, until: .distantPast,
          inMode: .default, dequeue: true))
      window.sendEvent(next)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  }
}
