import MarkdownUI
import SwiftUI

struct AnswerMarkdown: View, Equatable {
  let source: String

  var body: some View {
    Markdown(source)
      .markdownTextStyle(\.text) {
        FontSize(14)
        ForegroundColor(Palette.ink)
      }
      .markdownTextStyle(\.link) {
        ForegroundColor(Palette.green)
        UnderlineStyle(.single)
      }
      .markdownBlockStyle(\.codeBlock) { block in
        block.label
          .markdownTextStyle { FontFamilyVariant(.monospaced) }
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
          .markdownMargin(top: .zero, bottom: .em(1))
      }
      // Displaying a model response must not fetch remote images.
      .markdownImageProvider(.asset)
      .markdownInlineImageProvider(.asset)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
