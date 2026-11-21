import AppKit

enum AttachmentPaste {
  case files([URL])
  case image(Data)

  static func read(from pasteboard: NSPasteboard) -> AttachmentPaste? {
    if let urls = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
    {
      return .files(urls)
    }
    if let type = pasteboard.availableType(from: [.png, .tiff]),
      let data = pasteboard.data(forType: type)
    {
      return .image(data)
    }
    return nil
  }
}
