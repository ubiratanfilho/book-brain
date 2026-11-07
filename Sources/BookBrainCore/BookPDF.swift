import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct BookPDF: Codable, Equatable {
  public let name: String
  public let pageCount: Int
}

extension LibraryStore {
  public func pdfURL(for bookID: UUID) -> URL {
    directory.appendingPathComponent("PDFs", isDirectory: true)
      .appendingPathComponent(bookID.uuidString).appendingPathExtension("pdf")
  }

  public func importPDF(_ source: URL, for bookID: UUID) throws -> BookPDF {
    let access = source.startAccessingSecurityScopedResource()
    defer { if access { source.stopAccessingSecurityScopedResource() } }
    let regularFile = source.resolvingSymlinksInPath()
    guard try regularFile.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      throw BookBrainError.message("Escolha um arquivo PDF.")
    }
    let destination = pdfURL(for: bookID)
    let fm = FileManager.default
    try fm.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: staging) }
    try fm.copyItem(at: regularFile, to: staging)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
    let document = try openBookPDF(staging)
    let attachment = BookPDF(name: source.lastPathComponent, pageCount: document.pageCount)
    try fm.moveItem(at: staging, to: destination)
    return attachment
  }
}

private func openBookPDF(_ url: URL) throws -> PDFDocument {
  guard let document = PDFDocument(url: url) else {
    throw BookBrainError.message("Não foi possível abrir esse PDF.")
  }
  guard !document.isLocked && document.allowsCopying else {
    throw BookBrainError.message(
      "Este PDF exige senha ou restringe a cópia. Escolha uma versão que permita consulta.")
  }
  guard document.pageCount > 0 else { throw BookBrainError.message("O PDF não contém páginas.") }
  return document
}

/// One instance per question, bound to the approved copy of the selected book.
/// The model can supply a search term or page number, never a filesystem path.
public actor BookPDFReader {
  private let file: URL
  private var document: PDFDocument?
  public init(file: URL) { self.file = file }

  static let namespace = "book_pdf"
  static let search = "search_book_pdf"
  static let read = "read_book_page"
  static let callLimit = 16
  static let specs: [[String: Any]] = [
    [
      "type": "function", "name": search,
      "description":
        "Search the attached book PDF for a literal word or phrase, ignoring case and accents. Returns matching PDF page numbers and short passages. Use terms in the book's language.",
      "inputSchema": [
        "type": "object",
        "properties": [
          "query": ["type": "string", "minLength": 1, "maxLength": 180],
          "from_page": ["type": "integer", "minimum": 1],
        ],
        "required": ["query"], "additionalProperties": false,
      ],
    ],
    [
      "type": "function", "name": read,
      "description":
        "Read a numbered PDF page (1-based). Use image=true for figures, formulas or layout. Scanned pages are returned as images. Use offset when reading the remainder of a long text page.",
      "inputSchema": [
        "type": "object",
        "properties": [
          "page": ["type": "integer", "minimum": 1], "image": ["type": "boolean"],
          "offset": ["type": "integer", "minimum": 0],
        ], "required": ["page"], "additionalProperties": false,
      ],
    ],
  ]

  func contents(for tool: String, arguments: [String: Any]) throws -> [[String: String]] {
    try Task.checkCancellation()
    let pdf: PDFDocument
    if let document {
      pdf = document
    } else {
      pdf = try openBookPDF(file)
      document = pdf
    }
    switch tool {
    case Self.search:
      guard Set(arguments.keys).isSubset(of: ["query", "from_page"]),
        let term = arguments["query"] as? String
      else { throw invalidArguments }
      let query = normalize(term)
      guard !query.isEmpty, term.count <= 180 else { throw invalidArguments }
      let start = try integer(arguments["from_page"] ?? 1, in: 1...pdf.pageCount)
      var hits: [String] = []
      for number in start...pdf.pageCount {
        try Task.checkCancellation()
        guard let raw = pdf.page(at: number - 1)?.string else { continue }
        let text = normalize(raw)
        if let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
          let lower =
            text.index(match.lowerBound, offsetBy: -120, limitedBy: text.startIndex)
            ?? text.startIndex
          let upper =
            text.index(match.upperBound, offsetBy: 220, limitedBy: text.endIndex) ?? text.endIndex
          hits.append("PDF p. \(number): \(text[lower..<upper])")
          if hits.count == 6 {
            if number < pdf.pageCount {
              hits.append("Continue with from_page=\(number + 1) for later matches.")
            }
            break
          }
        }
      }
      return [
        [
          "type": "inputText",
          "text": hits.isEmpty
            ? "No text match in PDF pp. \(start)–\(pdf.pageCount). Scanned pages can be read by page number."
            : hits.joined(separator: "\n\n"),
        ]
      ]
    case Self.read:
      guard Set(arguments.keys).isSubset(of: ["page", "image", "offset"]),
        let value = arguments["page"]
      else { throw invalidArguments }
      let number = try integer(value, in: 1...pdf.pageCount)
      guard let page = pdf.page(at: number - 1) else { throw invalidArguments }
      var imageRequested = false
      if let image = arguments["image"] {
        guard let flag = image as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else {
          throw invalidArguments
        }
        imageRequested = flag.boolValue
      }
      let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let offset = try integer(arguments["offset"] ?? 0, in: 0...text.count)
      let label = "PDF p. \(number) of \(pdf.pageCount)"
      if imageRequested || text.isEmpty {
        return [
          ["type": "inputText", "text": label],
          ["type": "inputImage", "imageUrl": try pageImage(page)],
        ]
      }
      let portion = text.dropFirst(offset).prefix(9000)
      let next = offset + portion.count
      let suffix = next < text.count ? "\nMore text: use offset=\(next)." : ""
      return [["type": "inputText", "text": "\(label)\n\(portion)\(suffix)"]]
    default: throw invalidArguments
    }
  }

  private var invalidArguments: BookBrainError {
    .message("Consulta inválida. Confira a página e os parâmetros da ferramenta de PDF.")
  }

  private func integer(_ value: Any, in range: ClosedRange<Int>) throws -> Int {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
      let i = Int(exactly: n.doubleValue), range.contains(i)
    else { throw invalidArguments }
    return i
  }

  private func normalize(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private func pageImage(_ page: PDFPage) throws -> String {
    guard let ref = page.pageRef else { throw BookBrainError.message("Página indisponível.") }
    let box = page.bounds(for: .cropBox)
    let rotated = abs(page.rotation % 180) == 90
    let w = rotated ? box.height : box.width
    let h = rotated ? box.width : box.height
    guard w.isFinite, h.isFinite, w > 0, h > 0 else { throw invalidArguments }
    let longest = max(w, h)
    let width = max(1, Int(w / longest * 1440))
    let height = max(1, Int(h / longest * 1440))
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw BookBrainError.message("Falha ao renderizar a página.") }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(rect)
    ctx.concatenate(
      ref.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
    ctx.drawPDFPage(ref)
    let data = NSMutableData()
    guard let image = ctx.makeImage(),
      let target = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw BookBrainError.message("Falha ao preparar a imagem da página.") }
    CGImageDestinationAddImage(
      target, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(target) else {
      throw BookBrainError.message("Falha ao codificar a página.")
    }
    return "data:image/jpeg;base64," + (data as Data).base64EncodedString()
  }
}
