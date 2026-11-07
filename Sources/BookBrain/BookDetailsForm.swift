import BookBrainCore
import SwiftUI
import UniformTypeIdentifiers

struct BookDetailsForm: View {
  @ObservedObject var model: AppModel
  let book: Book?
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var author: String
  @State private var pdfURL: URL?
  @State private var choosingPDF = false
  @State private var error: String?

  init(model: AppModel, book: Book? = nil) {
    self.model = model
    self.book = book
    _title = State(initialValue: book?.title ?? "")
    _author = State(initialValue: book?.author ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(book == nil ? "Adicionar livro" : "Editar livro").font(.system(size: 23, design: .serif))
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          LabeledContent("Título") { TextField("Título do livro", text: $title) }
          LabeledContent("Autor") { TextField("Nome do autor", text: $author) }
          if book == nil {
            if let pdfURL {
              HStack {
                Label(pdfURL.lastPathComponent, systemImage: "doc.text").lineLimit(2)
                Spacer()
                Button {
                  self.pdfURL = nil
                } label: {
                  Image(systemName: "xmark")
                }
                .accessibilityLabel("Remover PDF da seleção")
              }
            } else {
              Button {
                choosingPDF = true
              } label: {
                Label("Anexar PDF (opcional)…", systemImage: "paperclip")
              }
            }
            Text(
              "O PDF fica salvo neste Mac. O Codex pode consultar páginas para responder e citar a fonte."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.textFieldStyle(.roundedBorder).padding(2).disabled(model.isImporting)
      }
      HStack {
        if model.isImporting { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.isImporting)
        Button(book == nil ? "Adicionar" : "Salvar") {
          Task {
            do {
              try await model.saveBook(id: book?.id, title: title, author: author, pdfURL: pdfURL)
              dismiss()
            } catch { self.error = error.localizedDescription }
          }
        }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
          .disabled(
            !model.isEditable || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(18)
      .interactiveDismissDisabled(model.isImporting)
      .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { selection in
        do {
          pdfURL = try selection.get()
          error = nil
        } catch {
          if (error as NSError).code != NSUserCancelledError {
            self.error = error.localizedDescription
          }
        }
      }
  }
}
