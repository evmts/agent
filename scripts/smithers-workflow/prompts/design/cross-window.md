# Design Spec: Cross-Window Workflow Rules (Section 8)

## 8) Cross-window workflow rules

### 8.1 "Open in Editor" contract

A single routing function:

`showInEditor(fileURL, line?, column?, highlightRange?)`

Behavior:

1. Ensure IDE window is visible.
2. Ensure file is open as tab (or reuse existing).
3. Select the tab.
4. Scroll to line/column with 0.2s ease-in-out animation.
5. Briefly pulse highlight (white@10% background) on the line for 0.6s (fade out).

### 8.2 AI file changes

When AI changes files:

1. Chat receives a **Diff Preview Card**
2. If preference `autoOpenIDEOnFileChange == true`:

   - IDE opens and focuses the first changed file (or diff tab)
   - Chat remains frontmost unless user preference "Focus editor on change" is enabled (default false)

3. JJ snapshot is created (as you already do)
4. Message hover actions allow revert/rollback.
