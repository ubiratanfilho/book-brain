# Reading with Book Brain

## Reading controls

1. Open Book Brain and choose **Add book**. Enter the title and author. To include a PDF, choose **Attach PDF (optional)…** before saving. For a book created in an earlier version, use **Books → Edit title and author…** to add the author. Book Brain connects to your local Codex session.
2. Click **Enable Kindle capture…**. On macOS 27, open **System Settings → Privacy & Security → Device Control and Data Access** and turn on **Book Brain**. Earlier versions call this panel **Accessibility**. After an update, the switch can still refer to the previous app signature. If **Enable Kindle capture…** still appears after reopening the app, quit with **⌘Q**, remove the **Book Brain** entry from that panel, and add the current copy of `build/Book Brain.app`. Reopen that copy and try **⌘⇧B** with a new selection in Kindle.
3. Select a passage in Kindle and press **⌘⇧B**. Book Brain sends the Copy command to Kindle and displays the selection for review. When Kindle includes a recognizable page or location, Book Brain fills in **Chapter or page**. You can edit the reference. A new capture with no recognizable reference clears the field. To copy manually, choose **Copy** in Kindle and **Paste passage** in Book Brain.
4. Type your question and press **Enter** to send. **Shift+Enter** starts a new line. You can ask about the book with or without a selected passage.
5. Keep asking questions in the same chat, even after capturing another passage. **New chat** starts a fresh conversation and saves the previous one. Click the chat title to reopen a conversation for the current book. The **…** menu lets you rename or delete a local chat.
6. Use **Books** to switch between books. Each book remembers its selected chat. Each chat keeps its questions, answers, reading reference, selected passage, and draft.

Choose **System**, **Light**, or **Dark** from **Appearance** at the top of the window. Book Brain saves your choice on this Mac. The interface is in English. Codex replies in the language of your question unless you request another language.

The pin button keeps the window above Kindle. Closing the window leaves Book Brain in the menu bar. **⌘Q** quits the app. The shortcut works while Book Brain is running. If another app has claimed **⌘⇧B**, Book Brain shows a notice and offers the window and menu bar actions.

Drag a window edge to resize it down to **300 × 280 points**, or choose **Compact window**. In compact mode the question field and send button stay visible, and you can expand the passage to edit it. **Expand window** restores the previous size on the same display.

## Connecting to Codex

Book Brain looks for `codex` on your PATH, in the ChatGPT and Codex app bundles, and in the usual Homebrew locations. If it cannot find the executable, choose **Locate Codex executable…** in the connection menu. Codex handles authentication and applies your account’s usage limits. Book Brain does not read or copy authentication tokens.

## Reading with Codex

Answers stream into the chat. You can stop a reply and reconnect. Book Brain keeps your draft after an error or cancellation and saves only completed exchanges. Each exchange includes the passage you sent with the question. The first question names the chat until you rename it.

Each question includes the book title and author. Codex can draw on its knowledge of the work and explain the selected passage. For questions about an attached PDF, the instructions direct Codex to consult the saved copy and cite the physical page in the file. When it needs more evidence, Codex is instructed to search the web and link to the sources it consulted. Local Codex memories can help tailor examples and explanations.

## Data and limits

- Direct capture uses the macOS permission to send **⌘C** to the Kindle process that had focus when you pressed **⌘⇧B**. This updates the clipboard just like choosing **Copy**. Book Brain waits for a fresh copy and shows the passage before you send it. Kindle’s copy restrictions apply.
- Book Brain reads clipboard text when you use the shortcut or **Paste passage**. When Kindle gains focus, the app records the clipboard change count so it can detect a stale manual copy. If capture fails, sending is paused until you copy again, edit the passage, or choose **Keep the previous context**.
- Sending a question gives Codex the title, author, reading reference, current passage, and question. Codex resumes the chat session and can use and generate local memories.
- Each question allows up to **12,000 characters of selected text** and **4,000 characters of question text**. Book Brain keeps the full chat history. Codex manages the session’s context window.
- Book Brain stores books, passages, questions, answers, and drafts in `~/Library/Application Support/BookBrain/library.json`. It writes the file as plain text with permissions `0600` in a directory created with permissions `0700`. Book Brain does not provide its own encryption or sync.
- The selected PDF is copied to `~/Library/Application Support/BookBrain/PDFs/`. All chats for that book can use it even if you move the original. Codex can search the text, read a page by number, or request an image of a scanned page. Each lookup sends Codex the requested extracts or page. Book Brain rejects locked PDFs and PDFs that restrict copying.
- If the library cannot be read, the app displays the error and blocks edits to preserve the original file.
- **Delete…** removes a chat and **Delete current book…** removes a book after confirmation. Deleting a book also removes its saved PDF. Codex maintains its own history and memories on the Mac.

## Codex integration

Book Brain starts `codex app-server` using Swift and Foundation. It communicates over standard input and output using `initialize`, `account/read`, `config/read`, `thread/start`, `thread/resume`, and `turn/start`, and receives JSONL events.

The first completed answer associates the chat with a persistent Codex session. Book Brain stores the session ID and uses it for the next question, including after an app restart. It releases the session subscription at the end of each reply. Codex processes eligible conversations for memory in the background.

On upgrade from an older library, each book’s previous history becomes its first chat, including passages, replies, and drafts. Older versions did not store a shared session ID. The first follow-up supplies up to six complete earlier exchanges, capped at 24,000 characters. Subsequent questions resume the Codex session.

Configuration overrides apply only to the child process. Book Brain enables Codex memory use and generation. It disables dedicated memory tools, shell and code execution, plugins, connectors, browser access, skill discovery, and inherited MCP servers. The `book-brain` permission profile grants read-only access to essential runtime paths and an empty temporary folder. Local tool execution has no network access. The Codex service handles web search. Book Brain accepts PDF queries only for the active chat and turn. It rejects other tool and approval requests and closes the session on an unexpected execution event. The Codex process still needs access to its authentication and to the network for inference.

Book Brain uses **GPT-6.1 Terra** (`gpt-6.1-terra`) with **Extra High** reasoning (`xhigh`) and **Fast** mode (`priority`) for each question. These settings apply to chats created by the app. The permission profile API is experimental and may change in a Codex update. If the profile fails, Book Brain displays the error and keeps the existing permission limits. [Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
