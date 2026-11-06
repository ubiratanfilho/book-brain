# Book Brain

- Native macOS application built with SwiftUI/AppKit and Swift Package Manager.
- Keep user-facing copy in Brazilian Portuguese. Write commits and PRs in English.
- Keep the prototype limited to explicitly pasted text and per-book conversations.
- Never monitor the clipboard, inspect Kindle storage, or request screen/accessibility permissions without a concrete new requirement.
- Never broaden Codex tool permissions to work around a protocol error. Check the installed CLI schema first.
- Do not read, copy, commit, or log authentication tokens, clipboard contents, or real reading history.
- Keep `library.json` outside the repository. Do not overwrite a corrupt library on load failure.
- Run `swift test` and `./scripts/build-app.sh` for changes to the app. Live tests are opt-in and use synthetic text only.
- Format Swift with `swift format` and the Python test fixture with Black.
