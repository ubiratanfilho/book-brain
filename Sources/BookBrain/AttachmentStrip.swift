import AppKit
import BookBrainCore
import SwiftUI

struct AttachmentStrip: View {
  let attachments: [ChatAttachment]
  let store: LibraryStore
  let bookID: UUID
  let chatID: UUID
  var remove: ((UUID) -> Void)?

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(attachments) { attachment in
          let url = store.attachmentURL(attachment, bookID: bookID, chatID: chatID)
          HStack(spacing: 7) {
            Button {
              NSWorkspace.shared.open(url)
            } label: {
              HStack(spacing: 7) {
                if attachment.kind == .image, let image = NSImage(contentsOf: url) {
                  Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                } else {
                  Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "doc.text")
                    .font(.system(size: 24)).frame(width: 32, height: 44)
                }
                VStack(alignment: .leading, spacing: 3) {
                  Text(attachment.name).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
                  Group {
                    if let pages = attachment.pageCount {
                      Text("PDF · \(pages) \(pages == 1 ? "page" : "pages")")
                    } else {
                      Text(
                        ByteCountFormatter.string(
                          fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                    }
                  }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.font(.system(size: 11))
              }
            }.buttonStyle(.plain).help("Open \(attachment.name)")
            if let remove {
              Button {
                remove(attachment.id)
              } label: {
                Image(systemName: "xmark.circle.fill")
              }
              .buttonStyle(.plain).foregroundStyle(Palette.muted)
              .accessibilityLabel("Remove \(attachment.name)")
            }
          }
          .padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
          .overlay { RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1) }
        }
      }.padding(.vertical, 2)
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}
