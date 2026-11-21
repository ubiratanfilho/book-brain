import AppKit
import SwiftUI

struct QuestionField: NSViewRepresentable {
  @Binding var text: String
  let compact: Bool
  let focusRequest: Int
  let send: () -> Void
  let attach: (AttachmentPaste) -> Void
  var pasteboard: NSPasteboard = .general
  @Environment(\.isEnabled) private var isEnabled

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    let editor = context.coordinator.editor
    editor.isRichText = false
    editor.importsGraphics = false
    editor.allowsUndo = true
    editor.drawsBackground = false
    editor.font = .systemFont(ofSize: 14)
    editor.textColor = NSColor(Palette.ink)
    editor.textContainerInset = .zero
    editor.textContainer?.lineFragmentPadding = 0
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.setAccessibilityLabel("Your question")
    editor.delegate = context.coordinator
    scroll.documentView = editor
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    let editor = coordinator.editor
    editor.isEditable = isEnabled
    editor.pasteboard = pasteboard
    editor.attach = attach
    if editor.string != text {
      editor.string = text
      editor.undoManager?.removeAllActions()
      editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
    }
    editor.needsDisplay = true
    if coordinator.lastFocusRequest != focusRequest {
      coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.async { [weak editor] in
        guard let editor, editor.isEditable else { return }
        editor.window?.makeFirstResponder(editor)
      }
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize?
  {
    guard let width = proposal.width else { return nil }
    let editor = context.coordinator.editor
    editor.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    guard let container = editor.textContainer, let layout = editor.layoutManager,
      let font = editor.font
    else { return nil }
    layout.ensureLayout(for: container)
    let line = layout.defaultLineHeight(for: font)
    let height = layout.usedRect(for: container).height
    return CGSize(
      width: width, height: max(line, min(height, line * (compact ? 2 : 5))))
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: QuestionField
    let editor = QuestionTextView()
    var lastFocusRequest: Int

    init(parent: QuestionField) {
      self.parent = parent
      lastFocusRequest = parent.focusRequest
    }

    func textDidChange(_ notification: Notification) {
      parent.text = editor.string
      editor.needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      guard selector == #selector(NSTextView.insertNewline(_:)), !textView.hasMarkedText() else {
        return false
      }
      let modifiers =
        NSApp.currentEvent?.modifierFlags.intersection([.shift, .control, .option, .command]) ?? []
      if modifiers == .shift {
        textView.insertNewlineIgnoringFieldEditor(nil)
      } else if modifiers.isEmpty {
        if NSApp.currentEvent?.isARepeat != true { parent.send() }
      } else {
        return false
      }
      return true
    }
  }
}

final class QuestionTextView: NSTextView {
  var pasteboard: NSPasteboard = .general
  var attach: ((AttachmentPaste) -> Void)?

  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(paste(_:)) {
      // Plain NSTextView disables Paste for image-only and file-only clipboards.
      return isEditable
        && pasteboard.availableType(from: [.png, .tiff, .fileURL, .string]) != nil
    }
    return super.validateUserInterfaceItem(item)
  }

  override func paste(_ sender: Any?) {
    guard isEditable else { return }
    // Only an explicit Paste action reads the clipboard, including images and file URLs.
    if let attachment = AttachmentPaste.read(from: pasteboard) {
      attach?(attachment)
    } else {
      _ = readSelection(from: pasteboard, type: .string)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if string.isEmpty && !hasMarkedText() {
      NSAttributedString(
        string: "What would you like to understand?",
        attributes: [
          .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor,
        ]
      ).draw(at: .zero)
    }
  }
}
