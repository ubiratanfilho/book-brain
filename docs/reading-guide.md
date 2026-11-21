# Reading with Book Brain

## Reading controls

1. Open Book Brain and choose **Add book**. Enter the title and author. To include a PDF, choose **Attach PDF (optional)…** before saving. For a book created in an earlier version, use **Books → Edit title and author…** to add the author. Choose a connection for the chat from the window’s connection menu.
2. Click **Enable Kindle capture…**. On macOS 27, open **System Settings → Privacy & Security → Device Control and Data Access** and turn on **Book Brain**. Earlier versions call this panel **Accessibility**. If you previously used an ad hoc signed build, its permission does not carry over to a changed executable or to the first build using the local signing certificate. Quit with **⌘Q**, remove the old **Book Brain** entry from that panel, and add the current copy of `build/Book Brain.app`. Reopen that copy and try **⌘⇧B** with a new selection in Kindle. Future builds made with the same signing certificate retain their signing identity; keep the certificate created by `./scripts/setup-local-signing.sh`.
3. Select a passage in Kindle and press **⌘⇧B**. Book Brain sends the Copy command to Kindle and displays the selection for review. When Kindle includes a recognizable page or location, Book Brain fills in **Chapter or page**. You can edit the reference. A new capture with no recognizable reference clears the field. To copy manually, choose **Copy** in Kindle and **Paste passage** in Book Brain.
4. Type your question and press **Enter** to send. **Shift+Enter** starts a new line. You can ask about the book with or without a selected passage.
5. Keep asking questions in the same chat, even after capturing another passage. **New chat** starts a fresh conversation and saves the previous one. Click the chat title to reopen a conversation for the current book. The **…** menu lets you rename or delete a local chat.
6. Use **Books** to switch between books. Each book remembers its selected chat. Each chat keeps its questions, answers, reading reference, selected passage, and draft.

Use the **paperclip** beside the question to select images, PDFs, or UTF-8 text files, including Markdown, source code, JSON, XML, CSV, and TSV. You can also copy files in Finder and paste them into the question field. To attach a screenshot directly, copy a screenshot with **⌃⇧⌘4**, then press **⌘V** in the question field. Pasting ordinary text still inserts text into your question.

Attachments appear above the question. Click one to open its saved copy, or click **×** to remove it before sending. Files are shared with the selected provider when you send the message. An attachment-only message is allowed. Attachments stay in that chat's history, and an unsuccessful send keeps them in your draft.

Choose **System**, **Light**, or **Dark** from **Appearance** at the top of the window. Book Brain saves your choice on this Mac. The interface is in English. Codex replies in the language of your question unless you request another language.

The pin button keeps the window above Kindle. Closing the window leaves Book Brain in the menu bar. **⌘Q** quits the app. The shortcut works while Book Brain is running. If another app has claimed **⌘⇧B**, Book Brain shows a notice and offers the window and menu bar actions.

Drag a window edge to resize it down to **300 × 280 points**, or choose **Compact window**. In compact mode the question field and send button stay visible, and you can expand the passage to edit it. **Expand window** restores the previous size on the same display.

If capture still asks for permission while the switch is enabled, check which copy of Book Brain you added. Old development copies have the same display name and can leave a permission entry associated with an old signature. Use the file picker's **⌘⇧G** action to select the exact path of the current `build/Book Brain.app` when replacing that entry, then restart Book Brain.

The `--check-kindle-capture-access` launch argument checks only the app's event-posting permission and prints `Kindle capture access: allowed` or `Kindle capture access: denied`. It exits before loading the library, registering the shortcut, or reading the clipboard.

## Using your own API key

After adding a book, open the connection menu and choose **Use an API key…**. Pick Anthropic, Google, or OpenAI, choose a model and save your provider API key. Model availability and billing depend on your provider account. The catalog comes from the bundled Pi release. Open **API settings…** to replace or remove a provider’s key from this Mac’s Keychain. The same provider key serves all its chats.

Each API chat keeps its provider and model. Choose **New chat** to switch providers after a completed answer. New chats in the same book inherit the active chat’s model. Older chats open in Codex mode. Sending through Pi includes up to six recent completed exchanges from the same chat, capped at 24,000 characters. Select a model with vision for screenshots or scanned PDF pages. Text attachments and the current chat’s PDF lookup tools are available in API mode. Web search and Codex memories are available in Codex mode.

## Connecting to Codex

Book Brain looks for `codex` on your PATH, in the ChatGPT and Codex app bundles, and in the usual Homebrew locations. If it cannot find the executable, choose **Locate Codex executable…** in the connection menu. Codex handles authentication and applies your account’s usage limits. Book Brain does not read or copy authentication tokens.

## Reading with Codex

Use **Copy raw** beside a response to copy its original text, including Markdown, LaTeX and code fences. During streaming, it copies the text received so far.

Answers stream into the chat. You can stop a reply and reconnect. Book Brain keeps your draft after an error or cancellation and saves only completed exchanges. Each exchange includes the passage you sent with the question. The first question names the chat until you rename it.

Equations in answers render locally, including in saved conversations. Inline math accepts `\(...\)` or `$...$`; display equations accept `\[...\]` or `$$...$$`. Named operators such as `\operatorname{Var}(X)` and display results wrapped in `\boxed{...}` are supported. Expressions such as integrals annotated with `\underbrace` use a bundled offline MathJax renderer. Wide equations scroll horizontally in compact windows. Unsupported LaTeX remains visible as source text, and code blocks keep their literal contents.

Each question includes the book title and author. Codex can draw on its knowledge of the work and explain the selected passage. For questions about an attached PDF, the instructions direct Codex to consult the saved copy and cite the physical page in the file. When it needs more evidence, Codex is instructed to search the web and link to the sources it consulted. Local Codex memories can help tailor examples and explanations.

## Data and limits

- Direct capture uses the macOS permission to send **⌘C** to the Kindle process that had focus when you pressed **⌘⇧B**. This updates the clipboard just like choosing **Copy**. Book Brain waits for a fresh copy and shows the passage before you send it. Kindle’s copy restrictions apply.
- Book Brain reads clipboard text when you use the shortcut or **Paste passage**. When Kindle gains focus, the app records the clipboard change count so it can detect a stale manual copy. If capture fails, sending is paused until you copy again, edit the passage, or choose **Keep the previous context**.
- Pasting into the question field reads images, file URLs, or text only for that explicit paste action. Book Brain does not monitor clipboard content.
- In Codex mode, sending a question gives Codex the title, author, reading reference, current passage, question, and attached images or text. Codex resumes the chat session and can use and generate local memories.
- Each question allows up to **12,000 characters of selected text** and **4,000 characters of question text**. Book Brain keeps the full chat history. Codex manages the session’s context window.
- Each message allows up to **8 attachments**, each no larger than **20 MB**. Images are converted to PNG and resized to at most **2,400 pixels** on the longest edge; the combined resized images must fit within **4 MB** per message. Text files must use UTF-8 and total no more than **40,000 characters** per message. Password-protected PDFs and PDFs that restrict copying are rejected.
- Book Brain stores books, passages, questions, answers, and drafts in `~/Library/Application Support/BookBrain/library.json`. It writes the file as plain text with permissions `0600` in a directory created with permissions `0700`. Book Brain does not provide its own encryption or sync.
- The selected PDF is copied to `~/Library/Application Support/BookBrain/PDFs/`. All chats for that book can use it even if you move the original. Codex can search the text, read a page by number, or request an image of a scanned page. Each lookup sends Codex the requested extracts or page. Book Brain rejects locked PDFs and PDFs that restrict copying.
- Chat attachments are copied to `~/Library/Application Support/BookBrain/Attachments/`, separated by book and chat, with file permissions `0600`. Moving or deleting the source file does not remove the saved attachment. A chat PDF uses the same bounded page and search tools as the book PDF, with an attachment ID rather than a model-supplied path. Instructions treat file contents as reference material and prohibit including private attachment contents in web searches.
- If the library cannot be read, the app displays the error and blocks edits to preserve the original file.
- **Delete…** removes a chat and its saved attachments, and **Delete current book…** removes a book, its chats, attachments, and saved PDF after confirmation. Original files remain in place. Codex maintains its own history and memories on the Mac.

## Codex integration

Book Brain starts `codex app-server` using Swift and Foundation. It communicates over standard input and output using `initialize`, `account/read`, `config/read`, `model/list`, `thread/start`, `thread/resume`, and `turn/start`, and receives JSONL events.

The first completed answer associates the chat with a persistent Codex session. Book Brain stores the session ID and uses it for the next question, including after an app restart. It releases the session subscription at the end of each reply. Codex processes eligible conversations for memory in the background.

On upgrade from an older library, each book’s previous history becomes its first chat, including passages, replies, and drafts. Older versions did not store a shared session ID. The first follow-up supplies up to six complete earlier exchanges, capped at 24,000 characters. Subsequent questions resume the Codex session.

New sessions register the PDF attachment tools at creation so that files can be added later. A session created before chat attachments cannot acquire updated tools on resume. Its first message with an attachment starts a new Codex session with the same bounded recent transcript. The complete local conversation remains in the original Book Brain chat.

Configuration overrides apply only to the child process. Book Brain enables Codex memory use and generation. It disables dedicated memory tools, shell and code execution, plugins, connectors, browser access, skill discovery, and inherited MCP servers. The `book-brain` permission profile grants read-only access to essential runtime paths and an empty temporary folder. Local tool execution has no network access. The Codex service handles web search. Book Brain accepts PDF queries only for the active chat and turn. It rejects other tool and approval requests and closes the session on an unexpected execution event. The Codex process still needs access to its authentication and to the network for inference.

Open the Codex connection menu to choose **Model** and turn **Fast mode** on or off. Choices apply to the next message in that chat, including resumed conversations. A new chat in the same book inherits the current choice. Book Brain gets available models and Fast support from the connected CLI. Existing chats initially use GPT-6.1 Terra when available, with Fast enabled where supported. Book Brain requests Extra High reasoning where available and otherwise uses the model’s default. The permission profile API is experimental and may change in a Codex update. If the profile fails, Book Brain displays the error and keeps the existing permission limits. [Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
