"use client"

import { useState } from "react"
import { ChatWindow } from "@/components/smithers/chat-window"
import { IDEWindow } from "@/components/smithers/ide-window"
import {
  mockSessions,
  mockMessages,
  mockAgents,
  mockJJChanges,
  mockFileTree,
} from "@/lib/mock-data"

export default function SmithersPrototype() {
  const [ideVisible, setIdeVisible] = useState(true)
  const [selectedSession, setSelectedSession] = useState("1")

  // Show messages only for session 1 (the one with mock data)
  const showMessages = selectedSession === "1"

  return (
    <div
      className="flex h-screen w-screen flex-col overflow-hidden"
      style={{ background: "var(--sm-base)" }}
    >
      {/* Top bar - prototype label */}
      <div
        className="flex shrink-0 items-center justify-center py-2"
        style={{ borderBottom: "1px solid var(--sm-border)" }}
      >
        <span
          className="rounded-full px-3 py-1 text-[10px] font-medium uppercase tracking-wider"
          style={{
            background: "var(--sm-pill-bg)",
            color: "var(--sm-text-tertiary)",
            border: "1px solid var(--sm-pill-border)",
          }}
        >
          Smithers v2 Prototype
        </span>
      </div>

      {/* Window container */}
      <div className="flex flex-1 gap-3 overflow-hidden p-3">
        {/* Chat Window (primary) - always visible */}
        <div
          className="shrink-0 overflow-hidden transition-all"
          style={{
            width: ideVisible ? "45%" : "100%",
            minWidth: ideVisible ? 400 : undefined,
          }}
        >
          <ChatWindow
            sessions={mockSessions}
            messages={mockMessages}
            agents={mockAgents}
            jjChanges={mockJJChanges}
            selectedSessionId={selectedSession}
            onSelectSession={setSelectedSession}
            onToggleIDE={() => setIdeVisible(!ideVisible)}
            showMessages={showMessages}
          />
        </div>

        {/* IDE Window (secondary) - togglable */}
        {ideVisible && (
          <div
            className="flex-1 overflow-hidden"
            style={{
              minWidth: 500,
              animation: "fadeSlideIn 0.25s ease-out",
            }}
          >
            <IDEWindow
              fileTree={mockFileTree}
              onClose={() => setIdeVisible(false)}
            />
          </div>
        )}
      </div>

      {/* Inline animation keyframes */}
      <style jsx>{`
        @keyframes fadeSlideIn {
          from {
            opacity: 0;
            transform: translateX(20px);
          }
          to {
            opacity: 1;
            transform: translateX(0);
          }
        }
      `}</style>
    </div>
  )
}
