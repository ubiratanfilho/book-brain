# Book Brain

- Native macOS application built with SwiftUI/AppKit and Swift Package Manager.
- Keep the interface in English. Codex replies in the language of the reader’s question unless another language is requested. Write commits and PRs in English.
- Import Kindle passages only from explicit pastes or the user's shortcut in the focused Kindle app. Accept PDFs only from the book creation file picker. Bind PDF queries to the selected book. Keep conversations separate by book.
- Direct capture uses permission to send the native Copy command to the foreground Kindle process. Request that permission only from the explicit activation button. Never monitor clipboard content or inspect Kindle storage.
- Never broaden Codex tool permissions to work around a protocol error. Check the installed CLI schema first.
- Do not read, copy, commit, or log authentication tokens, clipboard contents, or real reading history.
- Keep `library.json` and imported PDFs outside the repository. Do not overwrite a corrupt library on load failure.
- Run `swift test` and `./scripts/build-app.sh` for changes to the app. Live tests are opt-in and use synthetic text only.
- Format Swift with `swift format` and the Python test fixture with Black.
