"use client"

import { ArrowRight } from "lucide-react"
import { suggestedPrompts } from "@/lib/mock-data"

const categories = ["Create", "Explore", "Code", "Learn"]

interface ChatWelcomeProps {
  projectName?: string
  onSelectPrompt?: (prompt: string) => void
}

export function ChatWelcome({
  projectName = "web-app",
  onSelectPrompt,
}: ChatWelcomeProps) {
  return (
    <div className="flex flex-1 items-center justify-center px-4">
      <div className="flex w-full max-w-[640px] flex-col items-center gap-6">
        {/* Heading */}
        <div className="flex flex-col items-center gap-2 text-center">
          <h1
            className="text-[28px] font-semibold"
            style={{ color: "var(--sm-text-primary)", lineHeight: 1.35 }}
          >
            How can I help you?
          </h1>
          <p className="text-[16px]" style={{ color: "var(--sm-text-secondary)" }}>
            {projectName}
          </p>
        </div>

        {/* Category pills */}
        <div className="flex flex-wrap items-center justify-center gap-2">
          {categories.map((cat) => (
            <button
              key={cat}
              className="rounded-full border px-3.5 py-2 text-[12px] font-medium transition-colors"
              style={{
                background: "var(--sm-pill-bg)",
                borderColor: "var(--sm-pill-border)",
                color: "var(--sm-text-secondary)",
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = "var(--sm-pill-active)"
                e.currentTarget.style.borderColor = "var(--sm-accent)"
                e.currentTarget.style.color = "var(--sm-text-primary)"
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = "var(--sm-pill-bg)"
                e.currentTarget.style.borderColor = "var(--sm-pill-border)"
                e.currentTarget.style.color = "var(--sm-text-secondary)"
              }}
            >
              {cat}
            </button>
          ))}
        </div>

        {/* Suggested prompts */}
        <div className="flex w-full flex-col gap-2">
          {suggestedPrompts.map((prompt) => (
            <button
              key={prompt.label}
              onClick={() => onSelectPrompt?.(prompt.label)}
              className="group flex w-full items-center justify-between rounded-lg border px-3 py-3 text-left transition-colors"
              style={{
                background: "rgba(255,255,255,0.03)",
                borderColor: "rgba(255,255,255,0.06)",
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = "rgba(255,255,255,0.06)"
                e.currentTarget.style.borderColor = "rgba(255,255,255,0.1)"
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = "rgba(255,255,255,0.03)"
                e.currentTarget.style.borderColor = "rgba(255,255,255,0.06)"
              }}
            >
              <div className="flex flex-col gap-0.5">
                <span
                  className="text-[13px]"
                  style={{ color: "var(--sm-text-primary)" }}
                >
                  {prompt.label}
                </span>
                <span className="text-[10px]" style={{ color: "var(--sm-text-tertiary)" }}>
                  {prompt.category}
                </span>
              </div>
              <ArrowRight
                size={14}
                className="opacity-0 transition-opacity group-hover:opacity-100"
                style={{ color: "var(--sm-text-tertiary)" }}
              />
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
