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
  let shortcutAvailable: Bool
  let setFloating: (Bool) -> Void
  let setCompact: (Bool) -> Void
  @State private var editingBook: Book?
  @State private var confirmDelete = false
  @State private var editingCompactExcerpt = false
  @State private var showChats = false
  @FocusState private var questionFocused: Bool

  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.width < 480 || geometry.size.height < 620
      VStack(spacing: 0) {
        header(compact: compact)
        if let book = model.selectedBook {
          HStack(spacing: 8) {
            Button {
              showChats = true
            } label: {
              HStack(spacing: 5) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text(book.currentChat.title).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption2)
              }
            }.buttonStyle(.plain)
              .help("Histórico de conversas deste livro")
              .accessibilityLabel("Histórico de conversas")
              .accessibilityValue(book.currentChat.title)
            Spacer(minLength: 0)
            Button {
              model.changeChat { $0.newChat() }
            } label: {
              Label("Nova conversa", systemImage: "square.and.pencil").fixedSize()
            }.disabled(book.currentChat.isBlank)
          }.font(.system(size: 12)).disabled(!model.isEditable)
            .padding(.horizontal, compact ? 12 : 24).padding(.vertical, compact ? 5 : 8)
          if !compact {
            notices
            bookHeader(book, compact: false)
            excerptCard(book, compact: false)
          }
          conversation(book, compact: compact)
          composer(book, compact: compact)
        } else {
          ScrollView {
            notices
            welcome
          }
        }
      }
      .sheet(isPresented: $model.showNewBook) {
        BookDetailsForm(model: model).frame(
          width: min(420, geometry.size.width), height: min(350, geometry.size.height))
      }
      .sheet(item: $editingBook) { book in
        BookDetailsForm(model: model, book: book).frame(
          width: min(420, geometry.size.width), height: min(350, geometry.size.height))
      }
      .sheet(isPresented: $showChats) {
        ChatHistoryView(model: model)
          .frame(width: min(450, geometry.size.width), height: min(430, geometry.size.height))
      }
    }
    .background(Palette.paper)
    .foregroundStyle(Palette.ink)
    .tint(Palette.green)
    .preferredColorScheme(.light)
    .padding(.top, 28)
    .background(Palette.paper)
    .alert("Excluir este livro e suas conversas?", isPresented: $confirmDelete) {
      Button("Cancelar", role: .cancel) {}
      Button("Excluir", role: .destructive) { model.deleteSelectedBook() }
    } message: {
      Text("O histórico e a cópia do PDF deste livro serão removidos da biblioteca do Book Brain.")
    }
    .onChange(of: model.focusQuestion) { _, _ in questionFocused = true }
  }

  @ViewBuilder private var notices: some View {
    if !shortcutAvailable {
      banner(
        "O atalho ⌘⇧B está indisponível. Use Colar trecho na janela ou na barra de menus.",
        isError: true)
    }
    if let error = model.storageError { banner(error, isError: true) }
    if let notice = model.notice { banner(notice, isError: false) }
  }

  private func header(compact: Bool) -> some View {
    HStack(spacing: compact ? 5 : 10) {
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
            compact
              ? "Codex"
              : (model.isConnecting
                ? "Conectando…" : model.isConnected ? "Codex conectado" : "Conectar Codex")
          )
          .font(.system(size: 11, weight: .medium))
        }
      }
      .menuStyle(.borderlessButton).fixedSize()
      .disabled(model.isConnecting || model.isBusy)
      Button {
        setCompact(!compact)
      } label: {
        Image(
          systemName: compact
            ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        )
        .frame(width: 24, height: 28)
      }
      .buttonStyle(.plain)
      .help(compact ? "Ampliar janela" : "Reduzir janela")
      .accessibilityLabel(compact ? "Ampliar janela" : "Reduzir janela")
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
    .padding(.horizontal, compact ? 12 : 24).padding(.top, compact ? 0 : 8).padding(
      .bottom, compact ? 4 : 18
    )
    .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
  }

  private func bookHeader(_ book: Book, compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        if compact {
          Text(book.title).font(.system(size: 17, weight: .medium, design: .serif)).lineLimit(2)
        } else {
          Text("SUA LEITURA").font(.system(size: 10, weight: .semibold)).tracking(1.8)
            .foregroundStyle(Palette.muted)
        }
        Spacer()
        Menu {
          ForEach(model.library.books) { item in
            Button(item.author.isEmpty ? item.title : "\(item.title) · \(item.author)") {
              model.selectBook(item.id)
            }
          }
          Divider()
          Button("Adicionar livro…") {
            model.showNewBook = true
          }
          Button("Editar título e autor…") { editingBook = book }
          Button("Excluir livro atual…", role: .destructive) { confirmDelete = true }
        } label: {
          Label("Livros", systemImage: "books.vertical")
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12))
        .disabled(!model.isEditable)
      }
      if !compact {
        Text(book.title).font(.system(size: 26, weight: .medium, design: .serif))
          .lineLimit(2).textSelection(.enabled)
      }
      if !book.author.isEmpty {
        Text(book.author).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
      }
      if let pdf = book.pdf {
        Label("PDF · \(pdf.name) · \(pdf.pageCount) pág.", systemImage: "doc.text")
          .font(.caption).foregroundStyle(Palette.muted).lineLimit(1).help(pdf.name)
      }
      TextField("Capítulo ou página · opcional", text: model.field(\.location))
        .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted)
        .accessibilityLabel("Capítulo ou página")
        .disabled(!model.isEditable)
    }
    .padding(.horizontal, compact ? 0 : 24).padding(.top, compact ? 0 : 20).padding(
      .bottom, compact ? 0 : 16)
  }

  private func excerptCard(_ book: Book, compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        if compact {
          Button {
            editingCompactExcerpt.toggle()
          } label: {
            Label(
              "Trecho em foco",
              systemImage: editingCompactExcerpt ? "chevron.down" : "chevron.right")
          }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
            .help("Expandir ou recolher o editor do trecho")
        } else {
          Label("Trecho em foco", systemImage: "text.quote")
            .font(.system(size: 12, weight: .semibold))
        }
        Spacer()
        Button {
          Task { await model.pasteExcerpt() }
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
            Text("Colar trecho")
          }.font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain).disabled(!model.isEditable)
      }
      if !model.canCopyFromKindle {
        Button("Ativar captura direta no Kindle…") { model.requestCopyAccess() }
          .font(.system(size: 11))
      }
      if let issue = model.captureIssue {
        VStack(alignment: .leading, spacing: 7) {
          Label(issue, systemImage: "doc.on.clipboard").fixedSize(horizontal: false, vertical: true)
          if !book.currentChat.excerpt.isEmpty || !book.currentChat.exchanges.isEmpty {
            Button("Continuar com o contexto anterior") { model.captureIssue = nil }
          }
        }.font(.system(size: 12))
          .padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
      }
      if compact && !editingCompactExcerpt {
        Text(
          book.currentChat.excerpt.isEmpty
            ? "Selecione um trecho no Kindle e pressione ⌘⇧B." : book.currentChat.excerpt
        )
        .font(.system(size: 12, design: .serif)).lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ZStack(alignment: .topLeading) {
          if book.currentChat.excerpt.isEmpty {
            Text("Selecione um trecho no Kindle e pressione ⌘⇧B, ou cole o texto aqui.")
              .font(.system(size: 13)).foregroundStyle(Palette.muted)
              .padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false)
          }
          TextEditor(text: model.field(\.excerpt))
            .font(.system(size: 14, design: .serif)).lineSpacing(4)
            .scrollContentBackground(.hidden)
            .frame(height: compact ? 60 : 94)
            .accessibilityLabel("Trecho do livro")
            .disabled(!model.isEditable)
        }
        HStack {
          Spacer()
          Text("\(book.currentChat.excerpt.count.formatted()) / 12.000")
            .foregroundStyle(
              book.currentChat.excerpt.count > ReadingPrompt.excerptLimit ? .red : Palette.muted)
        }.font(.system(size: 10)).foregroundStyle(Palette.muted)
      }
    }
    .padding(14)
    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1) }
    .padding(.horizontal, compact ? 0 : 24)
  }

  private func conversation(_ book: Book, compact: Bool) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: compact ? 12 : 24) {
          if compact {
            VStack(alignment: .leading, spacing: 8) {
              notices
              bookHeader(book, compact: true)
              excerptCard(book, compact: true)
            }.id("context")
          }
          if book.currentChat.exchanges.isEmpty && !model.isBusy {
            VStack(alignment: .leading, spacing: 12) {
              VStack(alignment: .leading, spacing: 8) {
                suggestion("Me explica com um exemplo", icon: "lightbulb")
                suggestion("Qual é a ideia central deste trecho?", icon: "text.alignleft")
                suggestion("Me faça uma pergunta sobre o trecho", icon: "bubble.left")
              }.padding(.top, 6)
            }.padding(.vertical, compact ? 0 : 12)
          }
          ForEach(book.currentChat.exchanges) { exchange in
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
                Text(model.answerStatus).font(.system(size: 12)).foregroundStyle(
                  Palette.muted)
              }
            } else {
              answerText(model.streamingAnswer)
            }
          }
          Color.clear.frame(height: 1).id("bottom")
        }.padding(.horizontal, compact ? 12 : 24).padding(.vertical, compact ? 8 : 20)
      }
      .onChange(of: model.streamingAnswer) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
      .onChange(of: book.currentChat.exchanges.count) { _, _ in
        proxy.scrollTo("bottom", anchor: .bottom)
      }
      .onChange(of: model.isBusy) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
      .onChange(of: book.currentChat.id) { _, _ in
        editingCompactExcerpt = false
        proxy.scrollTo(compact ? "context" : "bottom", anchor: compact ? .top : .bottom)
      }
      .onChange(of: model.captureIssue) { _, issue in
        if compact && issue != nil { proxy.scrollTo("context", anchor: .top) }
      }
      .onChange(of: book.currentChat.excerpt) { _, _ in
        if compact && !editingCompactExcerpt { proxy.scrollTo("context", anchor: .top) }
      }
    }
  }

  private func composer(_ book: Book, compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: compact ? 4 : 10) {
      HStack(alignment: .bottom, spacing: 12) {
        TextField("O que você quer entender?", text: model.field(\.question), axis: .vertical)
          .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(compact ? 1...2 : 2...5)
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
            !model.isConnected || !model.isEditable || model.captureIssue != nil
              || book.currentChat.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(compact ? 8 : 14).background(.white, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1) }
      HStack(alignment: .top) {
        Text(
          book.pdf == nil
            ? "Pesquisa na web disponível. Memórias ativadas."
            : "Consulta ao PDF e pesquisa na web disponíveis. Memórias ativadas."
        )
        .fixedSize(horizontal: false, vertical: true)
        Spacer()
        if !compact { Text("⌘↩ enviar").fixedSize() }
      }.font(.system(size: 10)).foregroundStyle(Palette.muted)
    }
    .padding(.horizontal, compact ? 12 : 24).padding(.bottom, compact ? 7 : 20).padding(
      .top, compact ? 6 : 12
    )
    .background(Palette.paper)
    .overlay(alignment: .top) { Palette.line.frame(height: 1) }
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 22) {
      Spacer()
      Image(systemName: "book.pages").font(.system(size: 48, weight: .ultraLight))
        .foregroundStyle(Palette.green)
      Text("Seu livro no Book Brain")
        .font(.system(size: 36, weight: .regular, design: .serif)).lineSpacing(3)
      Text(
        "Adicione o livro, selecione um trecho no Kindle e use ⌘⇧B para trazê-lo à conversa."
      )
      .font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(5)
      .fixedSize(horizontal: false, vertical: true)
      Button {
        model.showNewBook = true
      } label: {
        Label("Adicionar meu primeiro livro", systemImage: "plus")
          .padding(.vertical, 5).padding(.horizontal, 4)
      }
      .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.isEditable)
      Spacer()
      VStack(alignment: .leading, spacing: 10) {
        step("1", "Trazer a seleção do Kindle", shortcut: "⌘⇧B")
        step("2", "Enviar uma pergunta", shortcut: "⌘↩")
      }
      .padding(18).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
      Text(
        "Histórico salvo neste Mac. Ao enviar uma pergunta, o Codex pode usar suas memórias e aprender com a conversa."
      )
      .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
    }.padding(32)
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
      AnswerMarkdown(source: text).equatable()
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
