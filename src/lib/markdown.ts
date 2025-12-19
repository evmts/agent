export function renderMarkdown(content: string): string {
  let html = content
    // Escape HTML first
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    // Code blocks (before other processing)
    .replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
      return `<pre><code class="lang-${lang}">${code.trim()}</code></pre>`;
    })
    // Inline code
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    // Headers
    .replace(/^#### (.+)$/gm, "<h4>$1</h4>")
    .replace(/^### (.+)$/gm, "<h3>$1</h3>")
    .replace(/^## (.+)$/gm, "<h2>$1</h2>")
    .replace(/^# (.+)$/gm, "<h1>$1</h1>")
    // Bold
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    // Italic
    .replace(/\*(.+?)\*/g, "<em>$1</em>")
    // Links
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
    // Unordered lists
    .replace(/^- (.+)$/gm, "<li>$1</li>")
    // Horizontal rules
    .replace(/^---$/gm, "<hr>")
    // Paragraphs (double newlines)
    .replace(/\n\n+/g, "</p><p>")
    // Single newlines to <br>
    .replace(/\n/g, "<br>");

  // Wrap lists
  html = html.replace(/(<li>.*?<\/li>)(\s*<br>)?/g, "$1");
  html = html.replace(/(<li>[\s\S]*?<\/li>)+/g, "<ul>$&</ul>");

  return `<div class="markdown-body"><p>${html}</p></div>`;
}
