"use client"

import { mockCodeContent } from "@/lib/mock-data"

export function CodeEditor() {
  const lines = mockCodeContent.split("\n")

  return (
    <div className="flex h-full overflow-hidden" style={{ background: "var(--sm-surface1)" }}>
      {/* Line numbers gutter */}
      <div
        className="smithers-scroll flex shrink-0 flex-col overflow-y-auto px-3 py-3 text-right"
        style={{
          borderRight: "1px solid var(--sm-border)",
          minWidth: 48,
          userSelect: "none",
        }}
      >
        {lines.map((_, i) => (
          <div
            key={i}
            className="font-mono text-[13px]"
            style={{
              color: "var(--sm-text-tertiary)",
              lineHeight: "1.4",
              height: "1.4em",
            }}
          >
            {i + 1}
          </div>
        ))}
      </div>

      {/* Code content */}
      <div className="smithers-scroll flex-1 overflow-auto px-4 py-3">
        <pre className="font-mono text-[13px]" style={{ lineHeight: "1.4" }}>
          {lines.map((line, i) => (
            <div
              key={i}
              className="transition-colors"
              style={{
                height: "1.4em",
                background:
                  i === 14
                    ? "rgba(255,255,255,0.06)"
                    : "transparent",
              }}
            >
              <SyntaxLine line={line} />
            </div>
          ))}
        </pre>

        {/* Ghost text completion demo */}
        <div
          className="font-mono text-[13px]"
          style={{
            color: "rgba(255,255,255,0.35)",
            lineHeight: "1.4",
            marginTop: "-1.4em",
            paddingLeft: "2ch",
          }}
        >
        </div>
      </div>

      {/* Minimap */}
      <div
        className="hidden shrink-0 overflow-hidden lg:block"
        style={{
          width: 70,
          borderLeft: "1px solid var(--sm-border)",
          background: "var(--sm-surface1)",
        }}
      >
        <div className="p-1.5">
          {lines.map((_, i) => (
            <div
              key={i}
              className="mb-px rounded-sm"
              style={{
                height: 2,
                width: `${Math.min(Math.random() * 80 + 20, 100)}%`,
                background: "rgba(255,255,255,0.12)",
              }}
            />
          ))}
          {/* Viewport indicator */}
          <div
            className="absolute right-0 top-0 rounded"
            style={{
              width: 70,
              height: 60,
              background: "rgba(255,255,255,0.04)",
              border: "1px solid rgba(255,255,255,0.08)",
            }}
          />
        </div>
      </div>
    </div>
  )
}

function SyntaxLine({ line }: { line: string }) {
  // Simple syntax highlighting for the prototype
  const tokens = tokenize(line)
  return (
    <>
      {tokens.map((token, i) => (
        <span key={i} style={{ color: token.color }}>
          {token.text}
        </span>
      ))}
    </>
  )
}

interface Token {
  text: string
  color: string
}

function tokenize(line: string): Token[] {
  const tokens: Token[] = []
  const keywords = [
    "import",
    "export",
    "async",
    "function",
    "const",
    "return",
    "if",
    "try",
    "catch",
    "await",
    "from",
    "as",
    "type",
    "interface",
    "extends",
    "new",
  ]
  const types = [
    "Request",
    "Response",
    "NextFunction",
    "JWTPayload",
    "UserPayload",
    "TextEncoder",
    "Error",
    "string",
  ]

  // Simple word-by-word tokenization
  let remaining = line
  let leadingSpaces = ""

  // Capture leading whitespace
  const spaceMatch = remaining.match(/^(\s+)/)
  if (spaceMatch) {
    leadingSpaces = spaceMatch[1]
    remaining = remaining.slice(leadingSpaces.length)
  }

  if (leadingSpaces) {
    tokens.push({ text: leadingSpaces, color: "transparent" })
  }

  // Comment lines
  if (remaining.trimStart().startsWith("//")) {
    tokens.push({ text: remaining, color: "var(--syn-comment)" })
    return tokens
  }

  // String on the whole line
  if (remaining.includes("'") || remaining.includes('"')) {
    const parts = remaining.split(/(["'][^"']*["']|`[^`]*`)/)
    for (const part of parts) {
      if (
        (part.startsWith("'") && part.endsWith("'")) ||
        (part.startsWith('"') && part.endsWith('"')) ||
        (part.startsWith("`") && part.endsWith("`"))
      ) {
        tokens.push({ text: part, color: "var(--syn-string)" })
      } else {
        tokenizeWords(part, tokens, keywords, types)
      }
    }
    return tokens
  }

  tokenizeWords(remaining, tokens, keywords, types)
  return tokens
}

function tokenizeWords(
  text: string,
  tokens: Token[],
  keywords: string[],
  types: string[]
) {
  const wordPattern = /([a-zA-Z_$][a-zA-Z0-9_$]*|[{}();:,.<>=!|&?+\-*\/\[\]]|\s+)/g
  let match: RegExpExecArray | null

  while ((match = wordPattern.exec(text)) !== null) {
    const word = match[1]

    if (/^\s+$/.test(word)) {
      tokens.push({ text: word, color: "transparent" })
    } else if (keywords.includes(word)) {
      tokens.push({ text: word, color: "var(--syn-keyword)" })
    } else if (types.includes(word)) {
      tokens.push({ text: word, color: "var(--syn-type)" })
    } else if (/^[{}();:,.<>=!|&?+\-*\/\[\]]+$/.test(word)) {
      tokens.push({ text: word, color: "var(--syn-operator)" })
    } else if (/^[A-Z]/.test(word)) {
      tokens.push({ text: word, color: "var(--syn-type)" })
    } else if (/^\d+$/.test(word)) {
      tokens.push({ text: word, color: "var(--syn-number)" })
    } else {
      tokens.push({ text: word, color: "var(--sm-text-primary)" })
    }
  }
}
