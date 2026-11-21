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
        text: Binding(get: { draft }, set: { draft = $0 }), compact: compact, focusRequest: 0,
        send: { sent.append(draft) }, attach: { _ in XCTFail("Unexpected attachment") })
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

  func testExplicitPasteHandlesImagesFilesAndPlainTextWithoutWatchingTheClipboard() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    var draft = "first OLDlast"
    var images: [Data] = []
    var files: [[URL]] = []
    let field = QuestionField(
      text: Binding(get: { draft }, set: { draft = $0 }), compact: true, focusRequest: 0,
      send: {},
      attach: { value in
        switch value {
        case .image(let data): images.append(data)
        case .files(let urls): files.append(urls)
        }
      }, pasteboard: pasteboard)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 350, height: 80),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.contentView = NSHostingView(rootView: field)
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    window.contentView?.layoutSubtreeIfNeeded()
    window.selectNextKeyView(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let editor = try XCTUnwrap(window.firstResponder as? QuestionTextView)
    pasteboard.setString("new ", forType: .string)
    editor.setSelectedRange((draft as NSString).range(of: "OLD"))
    editor.paste(nil)
    XCTAssertEqual(draft, "first new last")

    let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
      NSColor.blue.setFill()
      rect.fill()
      return true
    }
    let data = try XCTUnwrap(image.tiffRepresentation)
    pasteboard.clearContents()
    pasteboard.setData(data, forType: .tiff)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertTrue(images.isEmpty)
    let pasteItem = NSMenuItem(
      title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    XCTAssertTrue(editor.validateUserInterfaceItem(pasteItem), "Image-only paste must be enabled")
    let menu = NSMenu(title: "Test Edit Menu")
    pasteItem.target = editor
    menu.addItem(pasteItem)
    menu.update()
    let commandV = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false,
        keyCode: 9))
    XCTAssertTrue(menu.performKeyEquivalent(with: commandV))
    XCTAssertEqual(images, [data])
    XCTAssertEqual(draft, "first new last")

    pasteboard.clearContents()
    let url = URL(fileURLWithPath: "/tmp/synthetic-attachment.pdf")
    pasteboard.writeObjects([url as NSURL])
    XCTAssertTrue(editor.validateUserInterfaceItem(pasteItem), "File-only paste must be enabled")
    editor.paste(nil)
    XCTAssertEqual(files, [[url]])
    XCTAssertEqual(draft, "first new last")
    editor.isEditable = false
    XCTAssertFalse(editor.validateUserInterfaceItem(pasteItem))
    editor.paste(nil)
    XCTAssertEqual(files.count, 1)
  }
}
