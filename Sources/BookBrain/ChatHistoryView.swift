import BookBrainCore
import SwiftUI

struct ChatHistoryView: View {
  @ObservedObject var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var editingID: UUID?
  @State private var name = ""
  @State private var deletion: ReadingChat?
  @State private var confirmDeletion = false

  var body: some View {
    if let book = model.selectedBook {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Chats").font(.title2)
            Text(book.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer()
          Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        Divider()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach([book.currentChat] + book.savedChats) { chat in
              if editingID == chat.id {
                HStack {
                  TextField("Chat name", text: $name).onSubmit { saveName(chat) }
                  Button("Save") { saveName(chat) }
                  Button {
                    editingID = nil
                  } label: {
                    Image(systemName: "xmark")
                  }
                  .accessibilityLabel("Cancel editing")
                }.padding(.vertical, 6)
              } else {
                HStack {
                  Button {
                    model.changeChat { $0.openChat(chat.id) }
                    dismiss()
                  } label: {
                    VStack(alignment: .leading, spacing: 5) {
                      Text(chat.title).lineLimit(2)
                      HStack(spacing: 5) {
                        Text(
                          (chat.exchanges.last?.date ?? chat.createdAt).formatted(
                            date: .numeric, time: .shortened))
                        Text("·")
                        Text(
                          chat.exchanges.isEmpty
                            ? "Draft"
                            : "\(chat.exchanges.count) \(chat.exchanges.count == 1 ? "question" : "questions")"
                        )
                      }.font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                  }.buttonStyle(.plain)
                  if chat.id == book.currentChat.id {
                    Image(systemName: "checkmark").accessibilityLabel("Current chat")
                  }
                  Menu {
                    Button("Rename…") {
                      name = chat.title
                      editingID = chat.id
                    }
                    Button("Delete…", role: .destructive) {
                      deletion = chat
                      confirmDeletion = true
                    }
                  } label: {
                    Image(systemName: "ellipsis.circle")
                  }
                  .menuIndicator(.hidden).menuStyle(.borderlessButton).fixedSize()
                  .accessibilityLabel("Options for \(chat.title)")
                }
                .padding(8)
                .background(
                  chat.id == book.currentChat.id ? Color.secondary.opacity(0.09) : .clear,
                  in: RoundedRectangle(cornerRadius: 8))
              }
            }
          }.disabled(!model.isEditable)
        }
      }.padding(14)
        .alert(
          "Delete this chat from Book Brain?", isPresented: $confirmDeletion, presenting: deletion
        ) { chat in
          Button("Cancel", role: .cancel) {}
          Button("Delete", role: .destructive) { model.changeChat { $0.deleteChat(chat.id) } }
        } message: { chat in
          Text(
            "“\(chat.title)” will be removed from this Mac's library. Codex keeps its own history and memories."
          )
        }
    }
  }

  private func saveName(_ chat: ReadingChat) {
    model.changeChat { $0.renameChat(chat.id, to: name) }
    editingID = nil
  }
}
