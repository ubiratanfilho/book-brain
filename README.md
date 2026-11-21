# Book Brain

Select a passage in Kindle for Mac, press **⌘⇧B**, and ask a question in a floating window beside the book. Each book keeps its own conversations, so you can return to a question when you pick up reading again. If you have a PDF, attach it when adding the book and ask for a citation that points you to the page behind an answer.

<p align="center">
  <img src="docs/reading-demo.gif" width="1200" alt="A reader selects a passage in Kindle, asks Book Brain about it, and reads the explanation alongside the book.">
</p>

## Build and run on your Mac

You'll need macOS 14 or later, Xcode 16 or later with Swift 6, and Node.js 22.19+ with npm to build the app. The built app includes Pi. Choose an API key from Anthropic, Google, or OpenAI, or use an authenticated Codex CLI with app-server permission profiles. The Codex integration was tested with CLI version `0.167.0-alpha.3.2`. Check your version with `codex --version`. If you need to sign in, run `codex login`. [Codex CLI setup](https://github.com/openai/codex#quickstart)

```bash
git clone https://github.com/ubiratanfilho/book-brain.git
cd book-brain
./scripts/setup-local-signing.sh
./scripts/build-app.sh
open "build/Book Brain.app"
```

Run the signing setup once. It creates a local code-signing certificate in your login keychain, with trust limited to code signing. Keep that identity so macOS can recognize future builds and preserve Kindle capture permission. You can use an existing signing identity with `CODE_SIGN_IDENTITY="Your identity" ./scripts/build-app.sh`. CI uses explicit ad hoc signing (`CODE_SIGN_IDENTITY=-`), which does not preserve permission across code changes.

The build installs the pinned Pi dependencies and packages the helper for your Mac. The script creates an app for your Mac's architecture. If Book Brain can't find Codex, choose **Locate Codex executable…** in the connection menu.

## Try it with a book

1. Choose **Add book** and enter the title and author. If you'd like Codex to consult a PDF, choose **Attach PDF (optional)…** before saving.
2. Click **Enable Kindle capture…** and grant the macOS permission. In Kindle for Mac, select a paragraph you can copy and press **⌘⇧B**. Book Brain shows the passage for review. For manual capture, copy the passage yourself and click **Paste passage**.
3. In a new chat, open the connection menu and choose **Use an API key…** to select a provider and model. Enter your key once to save it in the macOS Keychain. For Codex, choose **Model**, set **Reasoning effort**, and toggle **Fast mode** in the same menu. You can change these settings between questions.
4. Try asking *“Can you explain this with an example?”* Press **Enter** to send. Ask a follow-up in the same chat, or click its title later to reopen a conversation for that book. Replies follow the language of your question.
5. Use the **paperclip** beside the question to attach images, PDFs, or UTF-8 text files. To paste a screenshot, copy it and press **⌘V** in the question field. Review or remove attachments before sending.

## What gets shared

Book Brain saves your library, drafts and imported files on your Mac. When you send a question, your selected provider receives the book title, author, reference, passage, question, and attached images or text. PDF lookups share the requested excerpts or page images. API mode sends requests directly from the bundled Pi helper to the selected provider and bills your API account. Each chat keeps its own provider and model. Codex mode uses your Codex account, web search, and Codex memory. [Storage, permissions and troubleshooting](docs/reading-guide.md)

## Development

The app uses SwiftUI and AppKit. Run the offline test suite with synthetic passages and a simulated Codex server, then build the app bundle.

```bash
swift test
./scripts/build-app.sh
```

To run the optional integration tests against your authenticated Codex session, use `BOOK_BRAIN_LIVE_TEST=1 swift test`. These tests use synthetic text and PDFs. [Codex integration details](docs/reading-guide.md#codex-integration)

Format Swift with `swift format format --in-place --recursive Sources Tests Package.swift` and the Python fixture with `python3 -m black Tests/BookBrainCoreTests/Fixtures/fake-codex.py`.

## Report a problem

Include your macOS version, Codex CLI version and the steps that reproduce the problem. For reading or capture issues, use a made-up passage so your books and chat history stay private. [Open a GitHub issue](https://github.com/ubiratanfilho/book-brain/issues/new)

## License

Book Brain is available under the [MIT License](LICENSE). The app bundle includes license notices for its Swift dependencies, MathJax, Pi, Bun, and the bundled provider libraries. Book Brain is an independent project by Ubiratan da Motta and has no affiliation with Amazon or OpenAI.
