import AppKit
import XCTest

@testable import BookBrainCore

@MainActor
final class PassageClipboardTests: XCTestCase {
  func testSelectionWithoutCopyIsRejectedAndRecopyingSameTextIsAllowed() async throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("Old passage", forType: .string)
    let capture = PassageClipboard(board)
    capture.beginReading()
    do {
      _ = try await capture.readNewExcerpt()
      XCTFail("Selecting text without copying must not import the previous clipboard.")
    } catch { XCTAssertTrue(error.localizedDescription.contains("nova cópia")) }

    board.clearContents()
    board.setString("Second passage", forType: .string)
    let second = try await capture.readNewExcerpt()
    XCTAssertEqual(second, "Second passage")
    do {
      _ = try await capture.readNewExcerpt()
      XCTFail("The same clipboard revision must not be imported twice.")
    } catch { XCTAssertTrue(error.localizedDescription.contains("nova cópia")) }
    board.clearContents()
    board.setString("Second passage", forType: .string)
    let recopied = try await capture.readNewExcerpt()
    XCTAssertEqual(recopied, second)
  }

  func testCopyArrivingAfterShortcutWinsOverPreviousPassage() async throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("Earlier text", forType: .string)
    let capture = PassageClipboard(board)
    capture.beginReading()
    let writer = Task {
      try await Task.sleep(for: .milliseconds(100))
      board.clearContents()
      board.setString("Current selection", forType: .string)
    }
    let excerpt = try await capture.readNewExcerpt()
    try await writer.value
    XCTAssertEqual(excerpt, "Current selection")
  }
}
