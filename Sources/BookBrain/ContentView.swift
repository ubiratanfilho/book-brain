import BookBrainCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel
  let shortcutAvailable: Bool
  let setFloating: (Bool) -> Void
  let setCompact: (Bool) -> Void
  @State private var editingBook: Book?
  @State private var confirmDelete = false
  @State private var editingCompactExcerpt = false
  @State private var showChats = false
  @AppStorage("readingAppearance") private var appearance = ReadingAppearance.system
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
              .help("Chat history for this book")
              .accessibilityLabel("Chat history")
              .accessibilityValue(book.currentChat.title)
            Spacer(minLength: 0)
            Button {
              model.changeChat { $0.newChat() }
            } label: {
              Label("New chat", systemImage: "square.and.pencil").fixedSize()
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
    .padding(.top, 28)
    .background(Palette.paper)
    .alert("Delete this book and its chats?", isPresented: $confirmDelete) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) { model.deleteSelectedBook() }
    } message: {
      Text("This will remove the book's chat history and its saved PDF from Book Brain.")
    }
    .onChange(of: appearance, initial: true) { _, mode in NSApp.appearance = mode.appAppearance }
    .onChange(of: model.focusQuestion) { _, _ in questionFocused = true }
  }

  @ViewBuilder private var notices: some View {
    if !shortcutAvailable {
      banner(
        "The ⌘⇧B shortcut is unavailable. Use Paste passage in the window or the menu bar.",
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
        Button(model.isConnected ? "Reconnect to Codex" : "Connect to Codex") {
          Task { await model.connect() }
        }
        Button("Locate Codex executable…") { model.chooseExecutable() }
        if !model.modelName.isEmpty { Text(model.modelName) }
      } label: {
        HStack(spacing: 6) {
          Circle().fill(model.isConnected ? Palette.green : .orange).frame(width: 6, height: 6)
          Text(
            compact
              ? "Codex"
              : (model.isConnecting
                ? "Connecting…" : model.isConnected ? "Codex connected" : "Connect to Codex")
          )
          .font(.system(size: 11, weight: .medium))
        }
      }
      .menuStyle(.borderlessButton).fixedSize()
      .disabled(model.isConnecting || model.isBusy)
      Menu {
        Picker("Appearance", selection: $appearance) {
          ForEach(ReadingAppearance.allCases, id: \.self) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }.pickerStyle(.inline).labelsHidden()
      } label: {
        Image(systemName: "circle.lefthalf.filled").frame(width: 24, height: 28)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .help("Appearance").accessibilityLabel("Appearance").accessibilityValue(appearance.rawValue)
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
      .help(compact ? "Expand window" : "Compact window")
      .accessibilityLabel(compact ? "Expand window" : "Compact window")
      Button {
        model.floating.toggle()
        setFloating(model.floating)
      } label: {
        Image(systemName: model.floating ? "pin.fill" : "pin")
          .foregroundStyle(model.floating ? Palette.green : Palette.muted)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .help(model.floating ? "Unpin window" : "Keep window above Kindle")
      .accessibilityLabel("Keep window above Kindle")
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
          Text("NOW READING").font(.system(size: 10, weight: .semibold)).tracking(1.8)
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
          Button("Add book…") {
            model.showNewBook = true
          }
          Button("Edit title and author…") { editingBook = book }
          Button("Delete current book…", role: .destructive) { confirmDelete = true }
        } label: {
          Label("Books", systemImage: "books.vertical")
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
        Label("PDF · \(pdf.name) · \(pdf.pageCount) pp.", systemImage: "doc.text")
          .font(.caption).foregroundStyle(Palette.muted).lineLimit(1).help(pdf.name)
      }
      TextField("Chapter or page · optional", text: model.field(\.location))
        .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted)
        .accessibilityLabel("Chapter or page")
        .help("Kindle citations can fill this in when you press ⌘⇧B. You can edit it here.")
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
              "Selected passage",
              systemImage: editingCompactExcerpt ? "chevron.down" : "chevron.right")
          }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
            .help("Expand or collapse the passage editor")
        } else {
          Label("Selected passage", systemImage: "text.quote")
            .font(.system(size: 12, weight: .semibold))
        }
        Spacer()
        Button {
          Task { await model.pasteExcerpt() }
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
            Text("Paste passage")
          }.font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain).disabled(!model.isEditable)
      }
      if !model.canCopyFromKindle {
        Button("Enable Kindle capture…") { model.requestCopyAccess() }
          .font(.system(size: 11))
      }
      if let issue = model.captureIssue {
        VStack(alignment: .leading, spacing: 7) {
          Label(issue, systemImage: "doc.on.clipboard").fixedSize(horizontal: false, vertical: true)
          if !book.currentChat.excerpt.isEmpty || !book.currentChat.exchanges.isEmpty {
            Button("Keep the previous context") { model.captureIssue = nil }
          }
        }.font(.system(size: 12))
          .padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
      }
      if compact && !editingCompactExcerpt {
        Text(
          book.currentChat.excerpt.isEmpty
            ? "Select a passage in Kindle and press ⌘⇧B." : book.currentChat.excerpt
        )
        .font(.system(size: 12, design: .serif)).lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ZStack(alignment: .topLeading) {
          if book.currentChat.excerpt.isEmpty {
            Text("Select a passage in Kindle and press ⌘⇧B, or paste it here.")
              .font(.system(size: 13)).foregroundStyle(Palette.muted)
              .padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false)
          }
          TextEditor(text: model.field(\.excerpt))
            .font(.system(size: 14, design: .serif)).lineSpacing(4)
            .scrollContentBackground(.hidden)
            .frame(height: compact ? 60 : 94)
            .accessibilityLabel("Book passage")
            .disabled(!model.isEditable)
        }
        HStack {
          Spacer()
          Text("\(book.currentChat.excerpt.count.formatted()) / 12,000")
            .foregroundStyle(
              book.currentChat.excerpt.count > ReadingPrompt.excerptLimit ? .red : Palette.muted)
        }.font(.system(size: 10)).foregroundStyle(Palette.muted)
      }
    }
    .padding(14)
    .background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
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
                suggestion("Explain this with an example", icon: "lightbulb")
                suggestion("What's the main idea of this passage?", icon: "text.alignleft")
                suggestion("Ask me a question about this passage", icon: "bubble.left")
              }.padding(.top, 6)
            }.padding(.vertical, compact ? 0 : 12)
          }
          ForEach(book.currentChat.exchanges) { exchange in
            VStack(alignment: .leading, spacing: 14) {
              questionBubble(exchange.question)
              if !exchange.excerpt.isEmpty {
                DisclosureGroup("Show passage for this question") {
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
    let canSend =
      model.isConnected && model.isEditable && model.captureIssue == nil
      && !book.currentChat.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    func send() {
      guard canSend else { return }
      Task { await model.send() }
    }

    return VStack(alignment: .leading, spacing: compact ? 4 : 10) {
      HStack(alignment: .bottom, spacing: 12) {
        QuestionField(text: model.field(\.question), compact: compact, send: send)
          .focused($questionFocused).disabled(!model.isEditable)
        if model.isBusy {
          Button("Stop", systemImage: "stop.fill") { model.cancel() }
            .buttonStyle(.bordered)
        } else {
          Button(action: send) {
            Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold))
              .frame(width: 32, height: 32)
          }
          .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 9))
          .keyboardShortcut(.return, modifiers: .command)
          .accessibilityLabel("Send question")
          .disabled(!canSend)
        }
      }
      .padding(compact ? 8 : 14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1) }
      HStack(alignment: .top) {
        Text(
          book.pdf == nil
            ? "Web search available. Memories enabled."
            : "PDF and web search available. Memories enabled."
        )
        .fixedSize(horizontal: false, vertical: true)
        Spacer()
        if !compact { Text("Enter to send · ⇧Enter for a new line").fixedSize() }
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
      Text("Your book in Book Brain")
        .font(.system(size: 36, weight: .regular, design: .serif)).lineSpacing(3)
      Text(
        "Add a book, select a passage in Kindle, and press ⌘⇧B to bring it into the chat."
      )
      .font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(5)
      .fixedSize(horizontal: false, vertical: true)
      Button {
        model.showNewBook = true
      } label: {
        Label("Add my first book", systemImage: "plus")
          .padding(.vertical, 5).padding(.horizontal, 4)
      }
      .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.isEditable)
      Spacer()
      VStack(alignment: .leading, spacing: 10) {
        step("1", "Bring in a Kindle selection", shortcut: "⌘⇧B")
        step("2", "Send a question", shortcut: "Enter")
      }
      .padding(18).background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
      Text(
        "Your chats are saved on this Mac. When you ask a question, Codex can use your memories and learn from the chat."
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
        .background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
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
        .buttonStyle(.plain).accessibilityLabel("Dismiss notice")
      }
    }.font(.system(size: 12)).padding(12)
      .background(isError ? Color.red.opacity(0.08) : Palette.green.opacity(0.06))
  }
}
