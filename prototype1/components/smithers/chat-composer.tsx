"use client"

import React from "react"

import { useState } from "react"
import { ArrowUp, Square, Paperclip, AtSign, Sparkles } from "lucide-react"

interface ChatComposerProps {
  isStreaming?: boolean
  onSend?: (text: string) => void
  onInterrupt?: () => void
}

export function ChatComposer({
  isStreaming = false,
  onSend,
  onInterrupt,
}: ChatComposerProps) {
  const [text, setText] = useState("")

  const handleSend = () => {
    if (text.trim() && onSend) {
      onSend(text)
      setText("")
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      if (isStreaming) {
        onInterrupt?.()
      } else {
        handleSend()
      }
    }
  }

  return (
    <div
      className="px-4 pb-4 pt-2"
      style={{ borderTop: "1px solid var(--sm-border)" }}
    >
      <div
        className="flex flex-col rounded-[10px]"
        style={{
          background: "var(--sm-input-bg)",
          border: "1px solid rgba(255,255,255,0.06)",
        }}
      >
        {/* Text area */}
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Ask anything..."
          rows={1}
          className="w-full resize-none bg-transparent px-3 py-2.5 text-[13px] leading-[1.5] outline-none placeholder:text-[var(--sm-text-tertiary)]"
          style={{
            color: "var(--sm-text-primary)",
            minHeight: 36,
            maxHeight: 120,
          }}
        />

        {/* Footer row */}
        <div className="flex items-center justify-between px-2 pb-2">
          <div className="flex items-center gap-1">
            <button
              className="flex items-center justify-center rounded-md p-1.5 transition-colors"
              style={{ color: "var(--sm-text-tertiary)" }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = "rgba(255,255,255,0.06)"
                e.currentTarget.style.color = "var(--sm-text-secondary)"
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = "transparent"
                e.currentTarget.style.color = "var(--sm-text-tertiary)"
              }}
              title="Attach file"
            >
              <Paperclip size={14} />
            </button>
            <button
              className="flex items-center justify-center rounded-md p-1.5 transition-colors"
              style={{ color: "var(--sm-text-tertiary)" }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = "rgba(255,255,255,0.06)"
                e.currentTarget.style.color = "var(--sm-text-secondary)"
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = "transparent"
                e.currentTarget.style.color = "var(--sm-text-tertiary)"
              }}
              title="Mention"
            >
              <AtSign size={14} />
            </button>
            <button
              className="flex items-center justify-center rounded-md p-1.5 transition-colors"
              style={{ color: "var(--sm-text-tertiary)" }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = "rgba(255,255,255,0.06)"
                e.currentTarget.style.color = "var(--sm-text-secondary)"
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = "transparent"
                e.currentTarget.style.color = "var(--sm-text-tertiary)"
              }}
              title="Skills"
            >
              <Sparkles size={14} />
            </button>
          </div>

          {/* Send / Interrupt */}
          {isStreaming ? (
            <button
              onClick={onInterrupt}
              className="flex h-8 w-8 items-center justify-center rounded-md transition-colors"
              style={{
                background: "rgba(248,113,113,0.25)",
                color: "var(--sm-danger)",
              }}
              title="Stop"
            >
              <Square size={14} />
            </button>
          ) : (
            <button
              onClick={handleSend}
              disabled={!text.trim()}
              className="flex h-8 w-8 items-center justify-center rounded-md transition-all"
              style={{
                background: text.trim()
                  ? "var(--sm-accent)"
                  : "rgba(255,255,255,0.08)",
                color: text.trim()
                  ? "rgba(255,255,255,0.92)"
                  : "var(--sm-text-tertiary)",
                opacity: text.trim() ? 1 : 0.5,
              }}
              title="Send"
            >
              <ArrowUp size={14} />
            </button>
          )}
        </div>
      </div>

      <div className="mt-1.5 flex items-center justify-center">
        <span className="text-[10px]" style={{ color: "var(--sm-text-tertiary)" }}>
          Return to send, Shift+Return for new line
        </span>
      </div>
    </div>
  )
}
