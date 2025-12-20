import { replaceMentionsWithLinks } from "./mentions";

// Simple but solid markdown to HTML converter
export function renderMarkdown(content: string): string {
  // Normalize line endings
  let text = content.replace(/\r\n/g, "\n");

  // Store code blocks to prevent processing
  const codeBlocks: string[] = [];
  text = text.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
    const index = codeBlocks.length;
    const escapedCode = escapeHtml(code.trim());
    codeBlocks.push(`<pre><code class="lang-${lang || 'text'}">${escapedCode}</code></pre>`);
    return `%%CODEBLOCK${index}%%`;
  });

  // Store inline code
  const inlineCodes: string[] = [];
  text = text.replace(/`([^`\n]+)`/g, (_, code) => {
    const index = inlineCodes.length;
    inlineCodes.push(`<code>${escapeHtml(code)}</code>`);
    return `%%INLINECODE${index}%%`;
  });

  // Escape remaining HTML
  text = escapeHtml(text);

  // Headers (must be at start of line)
  text = text.replace(/^#### (.+)$/gm, "<h4>$1</h4>");
  text = text.replace(/^### (.+)$/gm, "<h3>$1</h3>");
  text = text.replace(/^## (.+)$/gm, "<h2>$1</h2>");
  text = text.replace(/^# (.+)$/gm, "<h1>$1</h1>");

  // Horizontal rules
  text = text.replace(/^---+$/gm, "<hr>");
  text = text.replace(/^\*\*\*+$/gm, "<hr>");

  // Bold and italic
  text = text.replace(/\*\*\*(.+?)\*\*\*/g, "<strong><em>$1</em></strong>");
  text = text.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  text = text.replace(/\*(.+?)\*/g, "<em>$1</em>");
  text = text.replace(/_(.+?)_/g, "<em>$1</em>");

  // Links
  text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');

  // @mentions - replace with links to user profiles
  text = replaceMentionsWithLinks(text);

  // Images
  text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" loading="lazy">');

  // Blockquotes
  text = text.replace(/^&gt; (.+)$/gm, "<blockquote>$1</blockquote>");
  // Merge consecutive blockquotes
  text = text.replace(/<\/blockquote>\n<blockquote>/g, "\n");

  // Unordered lists
  text = text.replace(/^- (.+)$/gm, "<li>$1</li>");
  text = text.replace(/^\* (.+)$/gm, "<li>$1</li>");
  // Wrap consecutive list items
  text = text.replace(/(<li>[\s\S]*?<\/li>)(\n(?!<li>)|$)/g, "<ul>$1</ul>$2");
  text = text.replace(/<\/ul>\n<ul>/g, "\n");

  // Ordered lists
  text = text.replace(/^\d+\. (.+)$/gm, "<oli>$1</oli>");
  text = text.replace(/(<oli>[\s\S]*?<\/oli>)(\n(?!<oli>)|$)/g, "<ol>$1</ol>$2");
  text = text.replace(/<\/ol>\n<ol>/g, "\n");
  text = text.replace(/<oli>/g, "<li>");
  text = text.replace(/<\/oli>/g, "</li>");

  // Paragraphs - split by double newlines
  const blocks = text.split(/\n\n+/);
  text = blocks
    .map((block) => {
      block = block.trim();
      if (!block) return "";
      // Don't wrap if already a block element
      if (
        block.startsWith("<h") ||
        block.startsWith("<ul") ||
        block.startsWith("<ol") ||
        block.startsWith("<pre") ||
        block.startsWith("<blockquote") ||
        block.startsWith("<hr") ||
        block.startsWith("%%CODEBLOCK")
      ) {
        return block;
      }
      // Convert single newlines to <br>
      block = block.replace(/\n/g, "<br>");
      return `<p>${block}</p>`;
    })
    .join("\n");

  // Restore code blocks
  codeBlocks.forEach((code, i) => {
    text = text.replace(`%%CODEBLOCK${i}%%`, code);
  });

  // Restore inline code
  inlineCodes.forEach((code, i) => {
    text = text.replace(`%%INLINECODE${i}%%`, code);
  });

  return `<div class="markdown-body">${text}</div>`;
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
