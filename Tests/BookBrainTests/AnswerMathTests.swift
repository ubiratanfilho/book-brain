import AppKit
import BookBrainCore
import SwiftUI
import XCTest

@testable import BookBrain

final class AnswerMathTests: XCTestCase {
  private func equations(in source: String) throws -> [MathEquation] {
    let markdown = AnswerMath.markdown(source)
    let pattern = try NSRegularExpression(pattern: #"book-brain-math://[^)\s]+"#)
    return try pattern.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
      .map {
        let range = try XCTUnwrap(Range($0.range, in: markdown))
        return try XCTUnwrap(MathEquation(url: URL(string: String(markdown[range]))))
      }
  }

  func testInlineAndDisplayDelimitersPreserveLatexBeforeMarkdownParsing() throws {
    let latex = #"\frac{a_1^2}{b} \leq \mu"#
    for (source, display) in [
      (#"Use \("# + latex + #"\) here."#, false),
      ("Use $" + latex + "$ here.", false),
      (#"\["# + latex + #"\]"#, true),
      ("$$" + latex + "$$", true),
    ] {
      let equation = try XCTUnwrap(equations(in: source).first)
      XCTAssertEqual(equation.latex, latex)
      XCTAssertEqual(equation.display, display)
    }
    let latexWithReservedCharacters = #"\left. x \right) + λ & y = 20\%"#
    let equation = MathEquation(latex: latexWithReservedCharacters, display: true)
    XCTAssertEqual(MathEquation(url: equation.url)?.latex, latexWithReservedCharacters)
    XCTAssertFalse(equation.url.absoluteString.contains(")"))
  }

  func testCodeEscapesCurrencyAndLinkDestinationsAreNotRewritten() throws {
    for source in [
      #"Use `\(x^2\)` as the source."#,
      "```latex\n\\[x^2\\]\n```",
      "~~~latex\n$$x^2$$\n~~~",
      "```latex\n\\[x^2\\]",
      #"Literal \\(x\\) and \$5; prices are $5 and $10."#,
      #"[A link](https://example.com/$x$)"#,
      #"[A link](https://example.com/(article)/$x$)"#,
      #"<https://example.com/$x$>"#,
    ] {
      XCTAssertEqual(AnswerMath.markdown(source), source)
    }
    XCTAssertNil(MathEquation(url: URL(string: "https://example.com/image.png")))
    XCTAssertNil(MathEquation(url: URL(string: "file:///tmp/image.png")))
    XCTAssertEqual(try equations(in: #"For x < 3, use \(x^2\); otherwise x > 3."#).count, 1)
  }

  func testStreamingWaitsForClosingDelimiterAndRetainsCompletedEquations() throws {
    let source = #"Start with \(x^2\), then \[\frac{a}{b}\] and continue."#
    for end in source.indices {
      let prefix = String(source[..<end])
      let captured = try equations(in: prefix)
      if prefix.contains(#"\]"#) {
        XCTAssertEqual(captured.count, 2)
      } else if prefix.contains(#"\)"#) {
        XCTAssertEqual(captured.count, 1)
      } else {
        XCTAssertTrue(captured.isEmpty)
      }
    }
  }

  @MainActor
  func testFractionsScriptsGreekAndFallbackRenderToVisibleImages() throws {
    let fraction = MathEquation(latex: #"\frac{1}{n}\sum_{i=1}^{n} x_i^2"#, display: true).render()
    XCTAssertGreaterThan(fraction.size.width, 40)
    XCTAssertGreaterThan(fraction.size.height, 30)
    let fractionBitmap = try XCTUnwrap(
      NSBitmapImageRep(data: try XCTUnwrap(fraction.tiffRepresentation)))
    let inkPixels = (0..<fractionBitmap.pixelsWide).reduce(0) { count, x in
      count
        + (0..<fractionBitmap.pixelsHigh).filter {
          fractionBitmap.colorAt(x: x, y: $0)!.alphaComponent > 0.5
        }.count
    }
    XCTAssertGreaterThan(inkPixels, 100)
    try fractionBitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "book-brain-fraction.png"))
    let inline = MathEquation(latex: #"\mu = E[Y]"#, display: false).render()
    XCTAssertGreaterThan(inline.size.width, 20)
    XCTAssertLessThan(inline.size.height, fraction.size.height)
    XCTAssertLessThan(MathEquation(latex: #"\mu"#, display: false).render().size.width, 20)
    let unsupported = MathEquation(latex: #"\notARealCommand{x}"#, display: false).render()
    XCTAssertGreaterThan(unsupported.size.width, 20)
    XCTAssertGreaterThan(unsupported.size.height, 10)
  }

  @MainActor
  func testNamedOperatorsAndBoxedResultsRenderInsteadOfFallingBackToSource() throws {
    let namedOperator = MathEquation(
      latex: #"E[Q]=\operatorname{Var}(U)"#, display: true
    ).render()
    XCTAssertLessThan(namedOperator.size.width, 180)
    XCTAssertLessThan(namedOperator.size.height, 30)
    let upright = MathEquation(latex: #"E[Q]=\mathrm{Var}(U)"#, display: true).render()
    XCTAssertEqual(namedOperator.size, upright.size)

    let latex = #"P(|U-m|>r)\leq\frac{\operatorname{Var}(U)}{r^{2}}"#
    let plain = MathEquation(latex: latex, display: true).render()
    let boxed = MathEquation(latex: "\\boxed{\n\(latex)\n}", display: true).render()
    XCTAssertLessThan(boxed.size.width, 300)
    XCTAssertGreaterThan(boxed.size.width, plain.size.width)
    XCTAssertGreaterThan(boxed.size.height, plain.size.height)
    XCTAssertGreaterThan(boxed.size.height, 40)

    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(boxed.tiffRepresentation)))
    XCTAssertTrue(
      (2..<(bitmap.pixelsWide - 2)).allSatisfy {
        bitmap.colorAt(x: $0, y: 0)!.alphaComponent > 0.5
      })
    XCTAssertTrue(
      (2..<(bitmap.pixelsWide - 2)).allSatisfy {
        bitmap.colorAt(x: $0, y: bitmap.pixelsHigh - 1)!.alphaComponent > 0.5
      })
    let invalid = MathEquation(latex: #"\boxed{\notARealCommand{x}}"#, display: true).render()
    XCTAssertGreaterThan(invalid.size.width, 100)
  }

  private let annotatedIntegral = #"""
    Split the expectation at a threshold:

    \[
    \underbrace{E[T]}_{\text{all samples}}
    =
    \underbrace{\int_{0 \leq t \leq b} t g(t)\,dt}_{\text{below the cutoff}}
    +
    \underbrace{\int_{t > b} t g(t)\,dt}_{\text{above the cutoff}}
    \]
    """#

  @MainActor
  func testSavedIntegralWithThreeLabeledUnderbracesIsTypeset() throws {
    let saved = try JSONEncoder().encode(
      Exchange(
        question: "How is the total split?", excerpt: "", location: "", answer: annotatedIntegral))
    let reopened = try JSONDecoder().decode(Exchange.self, from: saved)
    let math = try XCTUnwrap(equations(in: reopened.answer).first)
    let image = math.render()
    let raw = NSAttributedString(
      string: math.latex,
      attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)])
    XCTAssertLessThan(image.size.width, raw.size().width * 0.8)
    let unlabelled = MathEquation(latex: #"\int_{0 \leq t \leq b} t g(t)\,dt"#, display: true)
      .render()
    XCTAssertGreaterThan(image.size.height, unlabelled.size.height + 10)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      "book-brain-annotated-integral.png")
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
  }

  @MainActor
  func testMixedAnswerFitsCompactWidthAndRendersInBothAppearances() throws {
    let source = #"""
      ### A mathematical example

      The mean is \(\mu=E[Y]\). Its spread is **not** the same as its mean.

      \[
      P(|Y-\mu|>r) \leq \frac{\sigma^2}{r^2}=\frac{1}{4}.
      \]

      1. Square the distance: \((Y-\mu)^2\).
      2. Apply the bound to \(Z=(Y-\mu)^2\).

      \[
      E[Z]=\operatorname{Var}(Y)
      \]

      \[
      \boxed{P(|Y-\mu|>r)\leq\frac{\operatorname{Var}(Y)}{r^2}}
      \]

      [Read more](https://example.com)

      ```latex
      \frac{a}{b}
      ```
      """#
    for scheme in [ColorScheme.light, .dark] {
      let view = AnswerMarkdown(source: source + "\n\n" + annotatedIntegral)
        .frame(width: 300).padding(16).background(Palette.paper)
        .environment(\.colorScheme, scheme)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 332, height: 600),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.alphaValue = 0
      window.contentView = host
      window.orderBack(nil)
      defer { window.orderOut(nil) }
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.frame.size = host.fittingSize
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      XCTAssertEqual(host.bounds.width, 332)
      XCTAssertGreaterThan(host.bounds.height, 250)
      let path = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("book-brain-math-\(scheme).png")
      try bitmap.representation(using: .png, properties: [:])!.write(to: path)
      print("Synthetic math preview: \(path.path)")
    }
  }
}
