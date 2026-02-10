"use client"

import React from "react"

import { useState } from "react"
import {
  MessageSquare,
  GitBranch,
  Users,
  Plus,
  Search,
  MoreHorizontal,
} from "lucide-react"
import type { ChatSession, Agent, JJChange } from "@/lib/mock-data"

type SidebarMode = "chats" | "source" | "agents"

interface ChatSidebarProps {
  sessions: ChatSession[]
  agents: Agent[]
  jjChanges: JJChange[]
  selectedSessionId: string
  onSelectSession: (id: string) => void
}

export function ChatSidebar({
  sessions,
  agents,
  jjChanges,
  selectedSessionId,
  onSelectSession,
}: ChatSidebarProps) {
  const [mode, setMode] = useState<SidebarMode>("chats")
  const [searchQuery, setSearchQuery] = useState("")

  const modes: { key: SidebarMode; icon: React.ReactNode; label: string }[] = [
    { key: "chats", icon: <MessageSquare size={14} />, label: "Chats" },
    { key: "source", icon: <GitBranch size={14} />, label: "Source" },
    { key: "agents", icon: <Users size={14} />, label: "Agents" },
  ]

  const groups = ["Today", "Yesterday", "This Week", "Older"] as const
  const filteredSessions = sessions.filter((s) =>
    s.title.toLowerCase().includes(searchQuery.toLowerCase())
  )

  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--sm-sidebar-bg)" }}
    >
      {/* Mode bar */}
      <div
        className="flex items-center gap-1 px-2"
        style={{ height: 40, borderBottom: "1px solid var(--sm-border)" }}
      >
        {modes.map((m) => (
          <button
            key={m.key}
            onClick={() => setMode(m.key)}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 text-[11px] font-medium transition-colors"
            style={{
              background:
                mode === m.key
                  ? "var(--sm-sidebar-selected)"
                  : "transparent",
              color:
                mode === m.key
                  ? "var(--sm-accent)"
                  : "var(--sm-text-secondary)",
            }}
            onMouseEnter={(e) => {
              if (mode !== m.key)
                e.currentTarget.style.background = "var(--sm-sidebar-hover)"
            }}
            onMouseLeave={(e) => {
              if (mode !== m.key)
                e.currentTarget.style.background = "transparent"
            }}
          >
            {m.icon}
            {m.label}
          </button>
        ))}
      </div>

      {/* Content based on mode */}
      {mode === "chats" && (
        <ChatsContent
          sessions={filteredSessions}
          selectedSessionId={selectedSessionId}
          onSelectSession={onSelectSession}
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          groups={groups}
        />
      )}
      {mode === "source" && <SourceContent jjChanges={jjChanges} />}
      {mode === "agents" && <AgentsContent agents={agents} />}
    </div>
  )
}

function ChatsContent({
  sessions,
  selectedSessionId,
  onSelectSession,
  searchQuery,
  onSearchChange,
  groups,
}: {
  sessions: ChatSession[]
  selectedSessionId: string
  onSelectSession: (id: string) => void
  searchQuery: string
  onSearchChange: (q: string) => void
  groups: readonly string[]
}) {
  return (
    <div className="flex flex-1 flex-col overflow-hidden">
      {/* New Chat + Search */}
      <div className="flex flex-col gap-2 p-3">
        <button
          className="flex w-full items-center justify-center gap-2 rounded-lg py-2 text-[12px] font-medium transition-colors"
          style={{
            background: "var(--sm-accent)",
            color: "rgba(255,255,255,0.92)",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.filter = "brightness(1.1)")}
          onMouseLeave={(e) => (e.currentTarget.style.filter = "none")}
        >
          <Plus size={14} />
          New Chat
        </button>
        <div
          className="flex items-center gap-2 rounded-lg px-2.5 py-1.5"
          style={{
            background: "var(--sm-input-bg)",
            border: "1px solid var(--sm-border)",
          }}
        >
          <Search size={12} style={{ color: "var(--sm-text-tertiary)" }} />
          <input
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search chats..."
            className="w-full bg-transparent text-[11px] outline-none placeholder:text-[var(--sm-text-tertiary)]"
            style={{ color: "var(--sm-text-primary)" }}
          />
        </div>
      </div>

      {/* Session list */}
      <div className="smithers-scroll flex-1 overflow-y-auto">
        {groups.map((group) => {
          const groupSessions = sessions.filter((s) => s.group === group)
          if (groupSessions.length === 0) return null
          return (
            <div key={group}>
              <div
                className="px-3 pb-1.5 pt-3 text-[10px] font-semibold uppercase tracking-wider"
                style={{ color: "var(--sm-text-tertiary)" }}
              >
                {group}
              </div>
              {groupSessions.map((session) => (
                <button
                  key={session.id}
                  onClick={() => onSelectSession(session.id)}
                  className="group flex w-full flex-col px-3 py-2.5 text-left transition-colors"
                  style={{
                    background:
                      selectedSessionId === session.id
                        ? "var(--sm-sidebar-selected)"
                        : "transparent",
                  }}
                  onMouseEnter={(e) => {
                    if (selectedSessionId !== session.id)
                      e.currentTarget.style.background =
                        "var(--sm-sidebar-hover)"
                  }}
                  onMouseLeave={(e) => {
                    if (selectedSessionId !== session.id)
                      e.currentTarget.style.background = "transparent"
                  }}
                >
                  <div className="flex items-center justify-between">
                    <span
                      className="truncate text-[12px] font-semibold"
                      style={{ color: "var(--sm-text-primary)" }}
                    >
                      {session.title}
                    </span>
                    <div className="flex items-center gap-1">
                      <span
                        className="text-[10px]"
                        style={{ color: "var(--sm-text-tertiary)" }}
                      >
                        {session.timestamp}
                      </span>
                      <MoreHorizontal
                        size={12}
                        className="opacity-0 transition-opacity group-hover:opacity-100"
                        style={{ color: "var(--sm-text-tertiary)" }}
                      />
                    </div>
                  </div>
                  <span
                    className="mt-0.5 line-clamp-2 text-[10px]"
                    style={{ color: "var(--sm-text-tertiary)" }}
                  >
                    {session.preview}
                  </span>
                </button>
              ))}
            </div>
          )
        })}
      </div>
    </div>
  )
}

function SourceContent({ jjChanges }: { jjChanges: JJChange[] }) {
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>({
    working: true,
    log: false,
    bookmarks: false,
  })

  const toggleSection = (key: string) =>
    setExpandedSections((prev) => ({ ...prev, [key]: !prev[key] }))

  const statusColors: Record<string, string> = {
    M: "var(--sm-warning)",
    A: "var(--sm-success)",
    D: "var(--sm-danger)",
    "?": "var(--sm-text-tertiary)",
  }

  return (
    <div className="smithers-scroll flex-1 overflow-y-auto p-2">
      {/* Working Copy */}
      <div>
        <button
          onClick={() => toggleSection("working")}
          className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-[11px] font-medium transition-colors"
          style={{ color: "var(--sm-text-primary)" }}
          onMouseEnter={(e) =>
            (e.currentTarget.style.background = "var(--sm-sidebar-hover)")
          }
          onMouseLeave={(e) =>
            (e.currentTarget.style.background = "transparent")
          }
        >
          <span
            className="text-[10px] transition-transform"
            style={{
              transform: expandedSections.working ? "rotate(90deg)" : "rotate(0deg)",
            }}
          >
            {"\\u25B6"}
          </span>
          Working Copy
          <span
            className="ml-auto rounded-full px-1.5 py-0.5 text-[9px] font-mono"
            style={{
              background: "var(--sm-pill-bg)",
              color: "var(--sm-text-secondary)",
            }}
          >
            {jjChanges.length}
          </span>
        </button>
        {expandedSections.working &&
          jjChanges.map((change) => (
            <div
              key={change.file}
              className="group flex items-center gap-2 rounded px-3 py-1.5 transition-colors"
              onMouseEnter={(e) =>
                (e.currentTarget.style.background = "var(--sm-sidebar-hover)")
              }
              onMouseLeave={(e) =>
                (e.currentTarget.style.background = "transparent")
              }
            >
              <span
                className="w-4 text-center font-mono text-[10px] font-bold"
                style={{ color: statusColors[change.status] }}
              >
                {change.status}
              </span>
              <span
                className="flex-1 truncate text-[11px]"
                style={{ color: "var(--sm-text-primary)" }}
              >
                {change.file.split("/").pop()}
              </span>
              <span
                className="font-mono text-[10px]"
                style={{ color: "var(--sm-text-tertiary)" }}
              >
                <span style={{ color: "var(--sm-success)" }}>
                  +{change.additions}
                </span>{" "}
                <span style={{ color: "var(--sm-danger)" }}>
                  -{change.deletions}
                </span>
              </span>
            </div>
          ))}
      </div>

      {/* Change Log */}
      <div className="mt-2">
        <button
          onClick={() => toggleSection("log")}
          className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-[11px] font-medium transition-colors"
          style={{ color: "var(--sm-text-primary)" }}
          onMouseEnter={(e) =>
            (e.currentTarget.style.background = "var(--sm-sidebar-hover)")
          }
          onMouseLeave={(e) =>
            (e.currentTarget.style.background = "transparent")
          }
        >
          <span
            className="text-[10px] transition-transform"
            style={{
              transform: expandedSections.log ? "rotate(90deg)" : "rotate(0deg)",
            }}
          >
            {"\\u25B6"}
          </span>
          Change Log
        </button>
        {expandedSections.log && (
          <div className="px-3 py-2">
            <div className="flex items-center gap-2 py-1">
              <div
                className="h-1.5 w-1.5 rounded-full"
                style={{ background: "var(--sm-accent)" }}
              />
              <span className="text-[11px]" style={{ color: "var(--sm-text-primary)" }}>
                auth-refactor-v2
              </span>
              <span className="ml-auto text-[10px]" style={{ color: "var(--sm-text-tertiary)" }}>
                2m ago
              </span>
            </div>
            <div className="flex items-center gap-2 py-1">
              <div
                className="h-1.5 w-1.5 rounded-full"
                style={{ background: "var(--sm-text-tertiary)" }}
              />
              <span className="text-[11px]" style={{ color: "var(--sm-text-primary)" }}>
                add-rate-limiter
              </span>
              <span className="ml-auto text-[10px]" style={{ color: "var(--sm-text-tertiary)" }}>
                1h ago
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Bookmarks */}
      <div className="mt-2">
        <button
          onClick={() => toggleSection("bookmarks")}
          className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-[11px] font-medium transition-colors"
          style={{ color: "var(--sm-text-primary)" }}
          onMouseEnter={(e) =>
            (e.currentTarget.style.background = "var(--sm-sidebar-hover)")
          }
          onMouseLeave={(e) =>
            (e.currentTarget.style.background = "transparent")
          }
        >
          <span
            className="text-[10px] transition-transform"
            style={{
              transform: expandedSections.bookmarks ? "rotate(90deg)" : "rotate(0deg)",
            }}
          >
            {"\\u25B6"}
          </span>
          Bookmarks
        </button>
        {expandedSections.bookmarks && (
          <div className="px-3 py-2">
            <div className="flex items-center gap-2 py-1">
              <span className="text-[11px]" style={{ color: "var(--sm-text-primary)" }}>
                main
              </span>
              <span
                className="rounded px-1 py-0.5 text-[9px]"
                style={{ background: "var(--sm-pill-bg)", color: "var(--sm-text-secondary)" }}
              >
                HEAD
              </span>
            </div>
            <div className="flex items-center gap-2 py-1">
              <span className="text-[11px]" style={{ color: "var(--sm-text-primary)" }}>
                feature/auth-refactor
              </span>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function AgentsContent({ agents }: { agents: Agent[] }) {
  const statusColors: Record<string, string> = {
    idle: "var(--sm-text-tertiary)",
    working: "var(--sm-info)",
    completed: "var(--sm-success)",
    failed: "var(--sm-danger)",
  }

  return (
    <div className="smithers-scroll flex-1 overflow-y-auto p-2">
      <div
        className="px-2 pb-1.5 pt-2 text-[10px] font-semibold uppercase tracking-wider"
        style={{ color: "var(--sm-text-tertiary)" }}
      >
        Active Agents
      </div>
      {agents.map((agent) => (
        <div
          key={agent.id}
          className="group flex items-center gap-2.5 rounded-lg px-3 py-2.5 transition-colors"
          onMouseEnter={(e) =>
            (e.currentTarget.style.background = "var(--sm-sidebar-hover)")
          }
          onMouseLeave={(e) =>
            (e.currentTarget.style.background = "transparent")
          }
        >
          <div
            className="h-2 w-2 shrink-0 rounded-full"
            style={{
              background: statusColors[agent.status],
              boxShadow:
                agent.status === "working"
                  ? `0 0 6px ${statusColors[agent.status]}`
                  : "none",
            }}
          />
          <div className="flex min-w-0 flex-1 flex-col">
            <span
              className="text-[11px] font-medium"
              style={{ color: "var(--sm-text-primary)" }}
            >
              {agent.name}
            </span>
            <span
              className="truncate text-[10px]"
              style={{ color: "var(--sm-text-tertiary)" }}
            >
              {agent.task}
            </span>
          </div>
          {agent.changes > 0 && (
            <span
              className="shrink-0 rounded px-1.5 py-0.5 font-mono text-[10px]"
              style={{
                background: "var(--sm-pill-bg)",
                color: "var(--sm-text-secondary)",
              }}
            >
              {agent.changes}
            </span>
          )}
        </div>
      ))}
    </div>
  )
}
