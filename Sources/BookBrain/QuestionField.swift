import AppKit
import SwiftUI

struct QuestionField: View {
  @Binding var text: String
  let compact: Bool
  let send: () -> Void

  var body: some View {
    TextField("What would you like to understand?", text: $text, axis: .vertical)
      .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(compact ? 1...2 : 2...5)
      .accessibilityLabel("Your question")
      .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: [.down, .repeat]) { key in
        // Let the input method finish composing before treating Return as a chat command.
        guard let editor = NSApp.currentEvent?.window?.firstResponder as? NSTextView,
          !editor.hasMarkedText()
        else { return .ignored }
        switch key.modifiers.intersection([.shift, .control, .option, .command]) {
        case .shift:
          editor.insertNewlineIgnoringFieldEditor(nil)
        case []:
          if key.phase == .down { send() }
        default:
          return .ignored
        }
        return .handled
      }
  }
}
