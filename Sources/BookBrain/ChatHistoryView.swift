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
            Text("Conversas").font(.title2)
            Text(book.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer()
          Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        Divider()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach([book.currentChat] + book.savedChats) { chat in
              if editingID == chat.id {
                HStack {
                  TextField("Nome da conversa", text: $name).onSubmit { saveName(chat) }
                  Button("Salvar") { saveName(chat) }
                  Button {
                    editingID = nil
                  } label: {
                    Image(systemName: "xmark")
                  }
                  .accessibilityLabel("Cancelar edição")
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
                            ? "Rascunho"
                            : "\(chat.exchanges.count) \(chat.exchanges.count == 1 ? "pergunta" : "perguntas")"
                        )
                      }.font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                  }.buttonStyle(.plain)
                  if chat.id == book.currentChat.id {
                    Image(systemName: "checkmark").accessibilityLabel("Conversa atual")
                  }
                  Menu {
                    Button("Renomear…") {
                      name = chat.title
                      editingID = chat.id
                    }
                    Button("Excluir…", role: .destructive) {
                      deletion = chat
                      confirmDeletion = true
                    }
                  } label: {
                    Image(systemName: "ellipsis.circle")
                  }
                  .menuIndicator(.hidden).menuStyle(.borderlessButton).fixedSize()
                  .accessibilityLabel("Opções de \(chat.title)")
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
          "Excluir conversa do Book Brain?", isPresented: $confirmDeletion, presenting: deletion
        ) { chat in
          Button("Cancelar", role: .cancel) {}
          Button("Excluir", role: .destructive) { model.changeChat { $0.deleteChat(chat.id) } }
        } message: { chat in
          Text(
            "“\(chat.title)” será removida da biblioteca deste Mac. O Codex mantém seu próprio histórico e suas memórias."
          )
        }
    }
  }

  private func saveName(_ chat: ReadingChat) {
    model.changeChat { $0.renameChat(chat.id, to: name) }
    editingID = nil
  }
}
