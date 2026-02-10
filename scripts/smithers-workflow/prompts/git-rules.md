# Git Commit Rules

- Atomic commits (one logical change)
- Emoji conventional: `EMOJI type(scope): description`
  - ✨ feat — new feature
  - 🧪 test — add/update tests
  - 🐛 fix — bug fix
  - 📋 docs — documentation
  - ♻️ refactor — restructure (no behavior change)
  - ⚡ perf — performance
  - 🔧 chore — build/tooling/deps
- Examples:
  - `✨ feat(chat): add message streaming with WebSocket`
  - `🧪 test(storage): add WAL mode concurrent access tests`
  - `🐛 fix(terminal): correct cursor position after resize`
  - `♻️ refactor(host): extract platform abstraction to vtable`
