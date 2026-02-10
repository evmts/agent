# Cross-Window Workflow Rules

## 8) Cross-window workflow

### 8.1 "Open in Editor" contract

`showInEditor(fileURL, line?, column?, highlightRange?)`

1. Ensure IDE visible
2. Ensure file tab open (or reuse)
3. Select tab
4. Scroll to line/col (0.2s ease-in-out)
5. Pulse highlight `white@10%` on line 0.6s fade

### 8.2 AI file changes

1. Chat receives Diff Preview Card
2. If `autoOpenIDEOnFileChange == true`: IDE opens + focuses first changed file (or diff tab); Chat remains front unless "Focus editor on change" enabled (default false)
3. JJ snapshot created
4. Message hover allows revert/rollback
