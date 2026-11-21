import AppKit
import JavaScriptCore
import MarkdownUI
import SwiftUI
import SwiftUIMath

enum AnswerMath {
  // Protect math before CommonMark consumes the backslashes in \(...\) and \[...\].
  static func markdown(_ source: String) -> String {
    var result = ""
    var cursor = source.startIndex
    while cursor < source.endIndex {
      let remainder = source[cursor...]
      if remainder.first == "`" || remainder.hasPrefix("~~~") {
        let marker = remainder.first!
        let run = remainder.prefix(while: { $0 == marker })
        let end = source.index(cursor, offsetBy: run.count)
        if let close = source.range(of: String(run), range: end..<source.endIndex) {
          result += source[cursor..<close.upperBound]
          cursor = close.upperBound
        } else if run.count >= 3 {
          result += remainder
          break
        } else {
          result += run
          cursor = end
        }
        continue
      }
      // Link destinations and HTML/autolink contents are not mathematical prose.
      if remainder.hasPrefix("](") {
        var end = source.index(cursor, offsetBy: 2)
        var depth = 1
        while end < source.endIndex && depth > 0 {
          if source[end] == "(" { depth += 1 }
          if source[end] == ")" { depth -= 1 }
          if source[end] == "\\" { end = source.index(after: end) }
          if end < source.endIndex { end = source.index(after: end) }
        }
        result += source[cursor..<end]
        cursor = end
        continue
      }
      if remainder.first == "<",
        remainder.range(
          of: #"^<(?:https?://|mailto:|/?[A-Za-z][A-Za-z0-9-]*(?:\s|/?>))"#,
          options: .regularExpression) != nil,
        let end = remainder.firstIndex(of: ">")
      {
        result += source[cursor...end]
        cursor = source.index(after: end)
        continue
      }
      let opening: String
      let closing: String
      let display: Bool
      if remainder.hasPrefix(#"\["#) {
        (opening, closing, display) = (#"\["#, #"\]"#, true)
      } else if remainder.hasPrefix(#"\("#) {
        (opening, closing, display) = (#"\("#, #"\)"#, false)
      } else if remainder.hasPrefix("$$") {
        (opening, closing, display) = ("$$", "$$", true)
      } else if remainder.first == "$" {
        (opening, closing, display) = ("$", "$", false)
      } else {
        result.append(source[cursor])
        cursor = source.index(after: cursor)
        if result.last == "\\", cursor < source.endIndex {
          result.append(source[cursor])
          cursor = source.index(after: cursor)
        }
        continue
      }
      let start = source.index(cursor, offsetBy: opening.count)
      var search = start
      var end: Range<String.Index>?
      while let candidate = source.range(of: closing, range: search..<source.endIndex) {
        let body = source[start..<candidate.lowerBound]
        let after = source[candidate.upperBound...].first
        let escaped =
          source[..<candidate.lowerBound].reversed().prefix(while: { $0 == "\\" }).count % 2 == 1
        if !escaped
          && (opening != "$" || (body.last?.isWhitespace == false && after?.isNumber != true))
        {
          end = candidate
          break
        }
        search = candidate.upperBound
      }
      guard let end, start < end.lowerBound,
        display || !source[start..<end.lowerBound].contains("\n"),
        opening != "$" || source[start].isWhitespace == false
      else {
        result += opening
        cursor = start
        continue
      }
      let equation = MathEquation(latex: String(source[start..<end.lowerBound]), display: display)
      let image = "![](\(equation.url.absoluteString))"
      if display {
        let lineStart =
          source[..<cursor].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
        let prefix = source[lineStart..<cursor]
        let indent = prefix.allSatisfy(\.isWhitespace) ? String(prefix) : ""
        result += "\n\(indent)\n\(indent)\(image)\n\(indent)\n"
      } else {
        result += image
      }
      cursor = end.upperBound
    }
    return result
  }
}

struct MathEquation {
  let latex: String
  let display: Bool

  var url: URL {
    let payload = Data(latex.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
    return URL(string: "book-brain-math://\(display ? "display" : "inline")/\(payload)")!
  }

  init(latex: String, display: Bool) {
    self.latex = latex
    self.display = display
  }

  init?(url: URL?) {
    guard let url, url.scheme == "book-brain-math",
      let mode = url.host, ["inline", "display"].contains(mode),
      let data = Data(
        base64Encoded: String(url.path.dropFirst())
          .replacingOccurrences(of: "-", with: "+")
          .replacingOccurrences(of: "_", with: "/")),
      let latex = String(data: data, encoding: .utf8)
    else { return nil }
    self.init(latex: latex, display: mode == "display")
  }

  @MainActor
  func render() -> NSImage {
    let typesetting = self.typesetting
    let renderer = ImageRenderer(
      content: Math(typesetting.latex)
        .mathFont(.init(name: .latinModern, size: display ? 18 : 14))
        .mathTypesettingStyle(display ? .display : .text)
        .foregroundStyle(.black)
        .fixedSize())
    renderer.scale = 2
    if let image = renderer.nsImage {
      guard typesetting.boxed else { return image }
      let size = NSSize(
        width: ceil(image.size.width) + 12, height: ceil(image.size.height) + 12)
      return NSImage(size: size, flipped: false) { bounds in
        image.draw(in: NSRect(origin: NSPoint(x: 6, y: 6), size: image.size))
        NSColor.black.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        return true
      }
    }
    if let image = Self.extendedMathImage(latex: latex, display: display) { return image }
    // Malformed or unsupported input remains readable.
    let text = NSAttributedString(
      string: latex,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.black,
      ])
    return NSImage(size: text.size(), flipped: false) { _ in
      text.draw(at: .zero)
      return true
    }
  }

  @MainActor private static let renderSVG: JSValue? = {
    guard let url = Bundle.module.url(forResource: "TeXRenderer", withExtension: "js"),
      let script = try? String(contentsOf: url, encoding: .utf8), let context = JSContext()
    else { return nil }
    context.evaluateScript(script)
    return context.objectForKeyedSubscript("renderEquation")
  }()

  @MainActor private static func extendedMathImage(latex: String, display: Bool) -> NSImage? {
    guard let output = renderSVG?.call(withArguments: [latex, display]), output.isString,
      let svg = output.toString()
    else { return nil }
    return NSImage(data: Data(svg.utf8))
  }

  private var typesetting: (latex: String, boxed: Bool) {
    // SwiftUIMath lacks custom operator names; upright text preserves Var(X), etc.
    let source = latex.replacingOccurrences(
      of: #"\\operatorname(?=\s*\{)"#, with: #"\\mathrm"#, options: .regularExpression)
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix(#"\boxed"#) else { return (source, false) }
    let argument = trimmed.dropFirst(#"\boxed"#.count).drop(while: \.isWhitespace)
    guard argument.first == "{" else { return (source, false) }
    let start = argument.index(after: argument.startIndex)
    var cursor = start
    var depth = 1
    while cursor < argument.endIndex {
      let character = argument[cursor]
      if character == "{" { depth += 1 }
      if character == "}" {
        depth -= 1
        if depth == 0 {
          let after = argument.index(after: cursor)
          guard argument[after...].allSatisfy(\.isWhitespace) else { return (source, false) }
          return (String(argument[start..<cursor]), true)
        }
      }
      if character == "\\" { cursor = argument.index(after: cursor) }
      if cursor < argument.endIndex { cursor = argument.index(after: cursor) }
    }
    return (source, false)
  }
}

struct MathImageProvider: ImageProvider {
  @ViewBuilder func makeImage(url: URL?) -> some View {
    if let equation = MathEquation(url: url) {
      MathBlockImage(equation: equation)
    }
  }
}

private struct MathBlockImage: View {
  let equation: MathEquation

  var body: some View {
    let image = equation.render()
    ScrollView(.horizontal) {
      Image(nsImage: image).renderingMode(.template)
        .foregroundStyle(Palette.ink)
        .accessibilityLabel(equation.latex)
    }
    .frame(height: image.size.height)
  }
}

struct MathInlineImageProvider: InlineImageProvider {
  func image(with url: URL, label: String) async -> Image {
    await MainActor.run {
      guard let equation = MathEquation(url: url) else { return Image(nsImage: NSImage()) }
      return Image(nsImage: equation.render()).renderingMode(.template)
    }
  }
}
