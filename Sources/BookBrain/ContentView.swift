import BookBrainCore
import SwiftUI

private enum Palette {
  static let paper = Color(red: 0.97, green: 0.96, blue: 0.94)
  static let ink = Color(red: 0.16, green: 0.20, blue: 0.18)
  static let green = Color(red: 0.21, green: 0.36, blue: 0.29)
  static let muted = Color(red: 0.45, green: 0.47, blue: 0.43)
  static let line = Color(red: 0.85, green: 0.86, blue: 0.81)
}

struct ContentView: View {
  @ObservedObject var model: AppModel
  let setFloating: (Bool) -> Void
  @State private var newTitle = ""
  @State private var confirmDelete = false
  @FocusState private var questionFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      if let error = model.storageError { banner(error, isError: true) }
      if let notice = model.notice { banner(notice, isError: false) }
      if let book = model.selectedBook {
        bookHeader(book)
        excerptCard(book)
        conversation(book)
        composer(book)
      } else {
        welcome
      }
    }
    .background(Palette.paper)
    .foregroundStyle(Palette.ink)
    .tint(Palette.green)
    .preferredColorScheme(.light)
    .padding(.top, 28)
    .background(Palette.paper)
    .sheet(isPresented: $model.showNewBook) { newBookSheet }
    .alert("Excluir este livro e suas conversas?", isPresented: $confirmDelete) {
      Button("Cancelar", role: .cancel) {}
      Button("Excluir", role: .destructive) { model.deleteSelectedBook() }
    } message: {
      Text("O histórico local deste livro será apagado. Essa ação não altera nada no Kindle.")
    }
    .onChange(of: model.focusQuestion) { _, _ in questionFocused = true }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "book.closed.fill")
        .font(.system(size: 18)).foregroundStyle(Palette.green)
      Text("book brain").font(.system(size: 20, weight: .semibold, design: .serif))
      Spacer()
      Menu {
        Button(model.isConnected ? "Reconectar ao Codex" : "Conectar ao Codex") {
          Task { await model.connect() }
        }
        Button("Localizar executável do Codex…") { model.chooseExecutable() }
        if !model.modelName.isEmpty { Text(model.modelName) }
      } label: {
        HStack(spacing: 6) {
          Circle().fill(model.isConnected ? Palette.green : .orange).frame(width: 6, height: 6)
          Text(
            model.isConnecting
              ? "Conectando…" : model.isConnected ? "Codex conectado" : "Conectar Codex"
          )
          .font(.system(size: 11, weight: .medium))
        }
      }
      .menuStyle(.borderlessButton).fixedSize()
      .disabled(model.isConnecting || model.isBusy)
      Button {
        model.floating.toggle()
        setFloating(model.floating)
      } label: {
        Image(systemName: model.floating ? "pin.fill" : "pin")
          .foregroundStyle(model.floating ? Palette.green : Palette.muted)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .help(model.floating ? "Desafixar janela" : "Manter janela acima do Kindle")
      .accessibilityLabel("Manter janela acima do Kindle")
    }
    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 18)
    .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
  }

  private func bookHeader(_ book: Book) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("SUA LEITURA").font(.system(size: 10, weight: .semibold)).tracking(1.8)
          .foregroundStyle(Palette.muted)
        Spacer()
        Menu {
          ForEach(model.library.books) { item in
            Button(item.title) { model.selectBook(item.id) }
          }
          Divider()
          Button("Adicionar livro…") {
            newTitle = ""
            model.showNewBook = true
          }
          Button("Excluir livro atual…", role: .destructive) { confirmDelete = true }
        } label: {
          Label("Livros", systemImage: "books.vertical")
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12))
        .disabled(!model.isEditable)
      }
      Text(book.title).font(.system(size: 26, weight: .medium, design: .serif))
        .lineLimit(2).textSelection(.enabled)
      TextField("Capítulo ou página · opcional", text: model.field(\.location))
        .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted)
        .accessibilityLabel("Capítulo ou página")
        .disabled(!model.isEditable)
    }
    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
  }

  private func excerptCard(_ book: Book) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Trecho em foco", systemImage: "text.quote")
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button {
          model.pasteExcerpt()
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
            Text("Colar trecho")
            Text("⌘⇧B").foregroundStyle(Palette.muted)
          }.font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain).disabled(!model.isEditable)
      }
      ZStack(alignment: .topLeading) {
        if book.excerpt.isEmpty {
          Text("No Kindle, selecione um trecho e copie com ⌘C. Depois, use ⌘⇧B ou cole aqui.")
            .font(.system(size: 13)).foregroundStyle(Palette.muted)
            .padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false)
        }
        TextEditor(text: model.field(\.excerpt))
          .font(.system(size: 14, design: .serif)).lineSpacing(4)
          .scrollContentBackground(.hidden)
          .frame(height: 94)
          .accessibilityLabel("Trecho do livro")
          .disabled(!model.isEditable)
      }
      HStack {
        Text("Você escolhe o que compartilhar.")
        Spacer()
        Text("\(book.excerpt.count.formatted()) / 12.000")
          .foregroundStyle(book.excerpt.count > ReadingPrompt.excerptLimit ? .red : Palette.muted)
      }.font(.system(size: 10)).foregroundStyle(Palette.muted)
    }
    .padding(14)
    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1) }
    .padding(.horizontal, 24)
  }

  private func conversation(_ book: Book) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
          if book.exchanges.isEmpty && !model.isBusy {
            VStack(alignment: .leading, spacing: 12) {
              Text("Dê espaço à curiosidade.")
                .font(.system(size: 23, weight: .regular, design: .serif))
              Text("Uma ideia difícil, uma conexão inesperada, uma pergunta que ficou.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(3)
              VStack(alignment: .leading, spacing: 8) {
                suggestion("Me explica com um exemplo", icon: "lightbulb")
                suggestion("Qual é a ideia central deste trecho?", icon: "text.alignleft")
                suggestion("Me faça uma pergunta sobre o trecho", icon: "bubble.left")
              }.padding(.top, 6)
            }.padding(.vertical, 24)
          }
          ForEach(book.exchanges) { exchange in
            VStack(alignment: .leading, spacing: 14) {
              questionBubble(exchange.question)
              if !exchange.excerpt.isEmpty {
                DisclosureGroup("Ver trecho desta pergunta") {
                  Text(exchange.excerpt).font(.system(size: 12, design: .serif))
                    .foregroundStyle(Palette.muted).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
              }
              answerText(exchange.answer)
            }
          }
          if model.isBusy {
            questionBubble(model.pendingQuestion)
            if model.streamingAnswer.isEmpty {
              HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Pensando sobre o trecho…").font(.system(size: 12)).foregroundStyle(
                  Palette.muted)
              }
            } else {
              answerText(model.streamingAnswer)
            }
          }
          Color.clear.frame(height: 1).id("bottom")
        }.padding(.horizontal, 24).padding(.vertical, 20)
      }
      .onChange(of: model.streamingAnswer) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
      .onChange(of: book.exchanges.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
      .onChange(of: model.isBusy) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
      .onChange(of: book.id) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
    }
  }

  private func composer(_ book: Book) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .bottom, spacing: 12) {
        TextField("O que você quer entender?", text: model.field(\.question), axis: .vertical)
          .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(2...5)
          .focused($questionFocused).disabled(!model.isEditable)
          .accessibilityLabel("Sua pergunta")
        if model.isBusy {
          Button("Parar", systemImage: "stop.fill") { model.cancel() }
            .buttonStyle(.bordered)
        } else {
          Button {
            Task { await model.send() }
          } label: {
            Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold))
              .frame(width: 32, height: 32)
          }
          .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 9))
          .keyboardShortcut(.return, modifiers: .command)
          .accessibilityLabel("Enviar pergunta")
          .disabled(
            !model.isConnected
              || book.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1) }
      HStack(alignment: .top) {
        Text(
          "Ao enviar, o trecho e até 6 trocas recentes vão ao Codex.\nO livro inteiro não é acessado."
        )
        .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Text("⌘↩ enviar").fixedSize()
      }.font(.system(size: 10)).foregroundStyle(Palette.muted)
    }
    .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 12)
    .background(Palette.paper)
    .overlay(alignment: .top) { Palette.line.frame(height: 1) }
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 22) {
      Spacer()
      Image(systemName: "book.pages").font(.system(size: 48, weight: .ultraLight))
        .foregroundStyle(Palette.green)
      Text("Um livro.\nMuitas boas perguntas.")
        .font(.system(size: 36, weight: .regular, design: .serif)).lineSpacing(3)
      Text(
        "Leia no Kindle, copie um trecho e converse sobre ele aqui. Seu espaço para pensar junto com o livro."
      )
      .font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(5)
      .fixedSize(horizontal: false, vertical: true)
      Button {
        newTitle = ""
        model.showNewBook = true
      } label: {
        Label("Adicionar meu primeiro livro", systemImage: "plus")
          .padding(.vertical, 5).padding(.horizontal, 4)
      }
      .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.isEditable)
      Spacer()
      VStack(alignment: .leading, spacing: 10) {
        step("1", "Copie um trecho no Kindle", shortcut: "⌘C")
        step("2", "Traga o trecho para cá", shortcut: "⌘⇧B")
        step("3", "Pergunte, explore, continue lendo", shortcut: "⌘↩")
      }
      .padding(18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
      Text(
        "Histórico salvo neste Mac. Somente o contexto da pergunta é enviado quando você pede uma resposta."
      )
      .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
    }.padding(32)
  }

  private var newBookSheet: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("O que você está lendo?").font(.system(size: 25, design: .serif))
      Text("O nome organiza seus trechos e conversas. Não é preciso importar o livro.")
        .font(.system(size: 13)).foregroundStyle(.secondary)
      TextField("Título do livro", text: $newTitle)
        .textFieldStyle(.roundedBorder).controlSize(.large)
        .accessibilityLabel("Título do livro")
        .onSubmit { addBook() }
      HStack {
        Spacer()
        Button("Cancelar") { model.showNewBook = false }.keyboardShortcut(.cancelAction)
        Button("Adicionar") { addBook() }
          .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
          .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(28).frame(width: 400).background(Palette.paper)
  }

  private func addBook() {
    guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    model.createBook(title: newTitle)
    model.showNewBook = false
    newTitle = ""
  }

  private func suggestion(_ text: String, icon: String) -> some View {
    Button {
      model.field(\.question).wrappedValue = text
      questionFocused = true
    } label: {
      Label(text, systemImage: icon).font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }.buttonStyle(.plain).disabled(!model.isEditable)
  }

  private func questionBubble(_ text: String) -> some View {
    Text(text).font(.system(size: 14, weight: .medium)).textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading).padding(14)
      .background(Palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }

  private func answerText(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("BOOK BRAIN", systemImage: "sparkle")
        .font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.green)
      Text(.init(text)).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func step(_ number: String, _ text: String, shortcut: String) -> some View {
    HStack(spacing: 10) {
      Text(number).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
        .frame(width: 20, height: 20).background(Palette.green.opacity(0.08), in: Circle())
      Text(text).font(.system(size: 12))
      Spacer()
      Text(shortcut).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
    }
  }

  private func banner(_ text: String, isError: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
      Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      if !isError {
        Button {
          model.notice = nil
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain).accessibilityLabel("Fechar aviso")
      }
    }.font(.system(size: 12)).padding(12)
      .background(isError ? Color.red.opacity(0.08) : Palette.green.opacity(0.06))
  }
}
