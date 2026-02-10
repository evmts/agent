"use client"

import { useRef, useEffect } from "react"
import { PanelRight } from "lucide-react"
import { ChatSidebar } from "./chat-sidebar"
import { ChatMessages } from "./chat-messages"
import { ChatComposer } from "./chat-composer"
import { ChatWelcome } from "./chat-welcome"
import type { ChatSession, ChatMessage, Agent, JJChange } from "@/lib/mock-data"

interface ChatWindowProps {
  sessions: ChatSession[]
  messages: ChatMessage[]
  agents: Agent[]
  jjChanges: JJChange[]
  selectedSessionId: string
  onSelectSession: (id: string) => void
  onToggleIDE: () => void
  showMessages: boolean
}

export function ChatWindow({
  sessions,
  messages,
  agents,
  jjChanges,
  selectedSessionId,
  onSelectSession,
  onToggleIDE,
  showMessages,
}: ChatWindowProps) {
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [messages])

  return (
    <div className="flex h-full flex-col overflow-hidden rounded-lg" style={{ background: "var(--sm-surface1)", border: "1px solid var(--sm-border)" }}>
      {/* macOS traffic lights simulation + title bar */}
      <div
        className="flex shrink-0 items-center px-3"
        style={{
          height: 40,
          background: "var(--sm-titlebar-bg)",
          borderBottom: "1px solid var(--sm-border)",
        }}
      >
        {/* Traffic lights */}
        <div className="flex items-center gap-2">
          <div className="h-3 w-3 rounded-full" style={{ background: "#FF5F57" }} />
          <div className="h-3 w-3 rounded-full" style={{ background: "#FEBC2E" }} />
          <div className="h-3 w-3 rounded-full" style={{ background: "#28C840" }} />
        </div>

        {/* Center title */}
        <div className="flex flex-1 items-center justify-center">
          <span className="text-[11px] font-medium" style={{ color: "var(--sm-titlebar-fg)" }}>
            Smithers - web-app
          </span>
        </div>

        {/* Open Editor button */}
        <button
          onClick={onToggleIDE}
          className="flex items-center gap-1.5 rounded-md px-2 py-1 text-[11px] transition-colors"
          style={{ color: "var(--sm-text-secondary)" }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = "rgba(255,255,255,0.06)"
            e.currentTarget.style.color = "var(--sm-text-primary)"
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = "transparent"
            e.currentTarget.style.color = "var(--sm-text-secondary)"
          }}
          title="Open Editor"
        >
          <PanelRight size={14} />
          <span className="hidden sm:inline">Editor</span>
        </button>
      </div>

      {/* Main content area */}
      <div className="flex flex-1 overflow-hidden">
        {/* Sidebar */}
        <div
          className="hidden shrink-0 overflow-hidden sm:block"
          style={{
            width: 260,
            borderRight: "1px solid var(--sm-border)",
          }}
        >
          <ChatSidebar
            sessions={sessions}
            agents={agents}
            jjChanges={jjChanges}
            selectedSessionId={selectedSessionId}
            onSelectSession={onSelectSession}
          />
        </div>

        {/* Chat detail */}
        <div className="flex flex-1 flex-col overflow-hidden">
          {showMessages ? (
            <>
              {/* Messages */}
              <div
                ref={scrollRef}
                className="smithers-scroll flex-1 overflow-y-auto"
              >
                <ChatMessages
                  messages={messages}
                  onOpenInEditor={onToggleIDE}
                />
              </div>

              {/* Composer */}
              <ChatComposer />
            </>
          ) : (
            <>
              <ChatWelcome />
              <ChatComposer />
            </>
          )}
        </div>
      </div>
    </div>
  )
}
