"use client"

import React from "react"

import { useState } from "react"
import {
  Copy,
  GitBranch,
  RotateCcw,
  Pencil,
  MoreHorizontal,
  ExternalLink,
  CheckCircle2,
  XCircle,
  Loader2,
  AlertTriangle,
} from "lucide-react"
import type { ChatMessage } from "@/lib/mock-data"

interface ChatMessagesProps {
  messages: ChatMessage[]
  onOpenInEditor?: () => void
}

export function ChatMessages({ messages, onOpenInEditor }: ChatMessagesProps) {
  return (
    <div className="flex flex-col gap-3 px-4 py-4">
      {messages.map((msg) => (
        <MessageBubble key={msg.id} message={msg} onOpenInEditor={onOpenInEditor} />
      ))}
    </div>
  )
}

function MessageBubble({
  message,
  onOpenInEditor,
}: {
  message: ChatMessage
  onOpenInEditor?: () => void
}) {
  const [showActions, setShowActions] = useState(false)

  if (message.type === "status") {
    return (
      <div className="flex justify-center py-1">
        <span
          className="rounded-full px-3 py-1 text-[11px]"
          style={{
            background: "var(--sm-bubble-status)",
            color: "var(--sm-text-secondary)",
          }}
        >
          {message.content}
        </span>
      </div>
    )
  }

  if (message.type === "command" && message.command) {
    return <CommandBubble command={message.command} />
  }

  if (message.type === "diff" && message.diff) {
    return <DiffBubble diff={message.diff} onOpenInEditor={onOpenInEditor} />
  }

  const isUser = message.type === "user"

  return (
    <div
      className={`flex ${isUser ? "justify-end" : "justify-start"}`}
      onMouseEnter={() => setShowActions(true)}
      onMouseLeave={() => setShowActions(false)}
    >
      <div className="relative" style={{ maxWidth: "80%" }}>
        {/* Action bar */}
        {showActions && (
          <div
            className="absolute -top-8 z-10 flex items-center gap-0.5 rounded-lg px-1 py-0.5"
            style={{
              background: "rgba(0,0,0,0.6)",
              border: "1px solid rgba(255,255,255,0.06)",
              backdropFilter: "blur(8px)",
              ...(isUser ? { right: 0 } : { left: 0 }),
            }}
          >
            {!isUser && (
              <ActionButton icon={<Copy size={12} />} tooltip="Copy" />
            )}
            <ActionButton icon={<GitBranch size={12} />} tooltip="Fork" />
            {isUser ? (
              <ActionButton icon={<Pencil size={12} />} tooltip="Edit" />
            ) : (
              <ActionButton icon={<RotateCcw size={12} />} tooltip="Retry" />
            )}
            <ActionButton
              icon={<MoreHorizontal size={12} />}
              tooltip="More"
            />
          </div>
        )}

        {/* Bubble */}
        <div
          className="px-3.5 py-2.5"
          style={{
            background: isUser
              ? "var(--sm-bubble-user)"
              : "var(--sm-bubble-assistant)",
            borderRadius: isUser
              ? "12px 12px 4px 12px"
              : "12px 12px 12px 4px",
            lineHeight: 1.5,
          }}
        >
          {isUser ? (
            <p className="text-[13px]" style={{ color: "var(--sm-text-primary)" }}>
              {message.content}
            </p>
          ) : (
            <AssistantMarkdown content={message.content} />
          )}
        </div>
      </div>
    </div>
  )
}

function ActionButton({
  icon,
  tooltip,
}: {
  icon: React.ReactNode
  tooltip: string
}) {
  return (
    <button
      title={tooltip}
      className="flex items-center justify-center rounded-md p-1.5 transition-colors"
      style={{ color: "var(--sm-text-secondary)" }}
      onMouseEnter={(e) => {
        e.currentTarget.style.background = "rgba(255,255,255,0.1)"
        e.currentTarget.style.color = "var(--sm-text-primary)"
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background = "transparent"
        e.currentTarget.style.color = "var(--sm-text-secondary)"
      }}
    >
      {icon}
    </button>
  )
}

function AssistantMarkdown({ content }: { content: string }) {
  // Simple markdown rendering for the prototype
  const lines = content.split("\n")
  return (
    <div className="flex flex-col gap-1.5 text-[13px]" style={{ color: "var(--sm-text-primary)" }}>
      {lines.map((line, i) => {
        if (line.startsWith("**") && line.endsWith("**")) {
          return (
            <p key={i} className="font-semibold">
              {line.replace(/\*\*/g, "")}
            </p>
          )
        }
        if (line.startsWith("- **")) {
          const parts = line.replace(/^- /, "").split("**")
          return (
            <p key={i} className="pl-2">
              {"- "}
              {parts.map((part, j) =>
                j % 2 === 1 ? (
                  <strong key={j}>{part}</strong>
                ) : (
                  <span key={j}>
                    {part.split("`").map((seg, k) =>
                      k % 2 === 1 ? (
                        <code
                          key={k}
                          className="rounded px-1 py-0.5 font-mono text-[12px]"
                          style={{ background: "rgba(255,255,255,0.06)" }}
                        >
                          {seg}
                        </code>
                      ) : (
                        <span key={k}>{seg}</span>
                      )
                    )}
                  </span>
                )
              )}
            </p>
          )
        }
        // Handle numbered lists
        if (/^\d+\.\s/.test(line)) {
          const text = line.replace(/^\d+\.\s/, "")
          return (
            <p key={i} className="pl-2">
              {line.match(/^\d+\./)?.[0]}{" "}
              {text.split("`").map((seg, k) =>
                k % 2 === 1 ? (
                  <code
                    key={k}
                    className="rounded px-1 py-0.5 font-mono text-[12px]"
                    style={{ background: "rgba(255,255,255,0.06)" }}
                  >
                    {seg}
                  </code>
                ) : (
                  <span key={k}>{seg}</span>
                )
              )}
            </p>
          )
        }
        // Inline code
        if (line.includes("`")) {
          return (
            <p key={i}>
              {line.split("`").map((seg, k) =>
                k % 2 === 1 ? (
                  <code
                    key={k}
                    className="rounded px-1 py-0.5 font-mono text-[12px]"
                    style={{ background: "rgba(255,255,255,0.06)" }}
                  >
                    {seg}
                  </code>
                ) : (
                  <span key={k}>{seg}</span>
                )
              )}
            </p>
          )
        }
        if (line === "") return <div key={i} className="h-1" />
        return <p key={i}>{line}</p>
      })}
    </div>
  )
}

function CommandBubble({
  command,
}: {
  command: NonNullable<ChatMessage["command"]>
}) {
  const [expanded, setExpanded] = useState(true)

  return (
    <div className="flex justify-start">
      <div
        className="overflow-hidden rounded-xl"
        style={{
          background: "var(--sm-bubble-command)",
          maxWidth: "90%",
          border: "1px solid var(--sm-border)",
        }}
      >
        {/* Header */}
        <button
          onClick={() => setExpanded(!expanded)}
          className="flex w-full items-center gap-2 px-3 py-2"
          style={{ borderBottom: expanded ? "1px solid var(--sm-border)" : "none" }}
        >
          <span
            className="font-mono text-[13px] font-semibold"
            style={{ color: "var(--sm-text-primary)" }}
          >
            $ {command.cmd}
          </span>
          <span className="ml-auto">
            {command.running ? (
              <Loader2
                size={14}
                className="animate-spin"
                style={{ color: "var(--sm-accent)" }}
              />
            ) : command.exitCode === 0 ? (
              <span
                className="flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-medium"
                style={{
                  background: "rgba(52,211,153,0.18)",
                  color: "var(--sm-success)",
                }}
              >
                <CheckCircle2 size={10} />
                exit 0
              </span>
            ) : (
              <span
                className="flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-medium"
                style={{
                  background: "rgba(248,113,113,0.18)",
                  color: "var(--sm-danger)",
                }}
              >
                <XCircle size={10} />
                exit {command.exitCode}
              </span>
            )}
          </span>
        </button>

        {/* CWD */}
        {expanded && (
          <div className="px-3 pt-1.5">
            <span
              className="text-[10px]"
              style={{ color: "var(--sm-text-tertiary)" }}
            >
              cwd: {command.cwd}
            </span>
          </div>
        )}

        {/* Output */}
        {expanded && (
          <div className="smithers-scroll overflow-x-auto px-3 py-2">
            <pre
              className="font-mono text-[12px] leading-relaxed"
              style={{ color: "var(--sm-text-primary)" }}
            >
              {command.output}
            </pre>
          </div>
        )}
      </div>
    </div>
  )
}

function DiffBubble({
  diff,
  onOpenInEditor,
}: {
  diff: NonNullable<ChatMessage["diff"]>
  onOpenInEditor?: () => void
}) {
  const statusStyles: Record<string, { bg: string; color: string; icon: React.ReactNode }> = {
    Applied: {
      bg: "rgba(52,211,153,0.18)",
      color: "var(--sm-success)",
      icon: <CheckCircle2 size={10} />,
    },
    Applying: {
      bg: "rgba(76,141,255,0.18)",
      color: "var(--sm-accent)",
      icon: <Loader2 size={10} className="animate-spin" />,
    },
    Failed: {
      bg: "rgba(248,113,113,0.18)",
      color: "var(--sm-danger)",
      icon: <XCircle size={10} />,
    },
    Declined: {
      bg: "rgba(251,191,36,0.18)",
      color: "var(--sm-warning)",
      icon: <AlertTriangle size={10} />,
    },
  }

  const statusStyle = statusStyles[diff.status]

  return (
    <div className="flex justify-start">
      <div
        className="overflow-hidden rounded-xl"
        style={{
          background: "var(--sm-bubble-diff)",
          maxWidth: "90%",
          border: "1px solid var(--sm-border)",
        }}
      >
        {/* Header */}
        <div
          className="flex items-center justify-between px-3 py-2"
          style={{ borderBottom: "1px solid var(--sm-border)" }}
        >
          <span className="text-[13px] font-medium" style={{ color: "var(--sm-text-primary)" }}>
            {diff.files.length} file{diff.files.length > 1 ? "s" : ""} changed
          </span>
          <span className="font-mono text-[12px]">
            <span style={{ color: "var(--sm-success)" }}>+{diff.totalAdditions}</span>{" "}
            <span style={{ color: "var(--sm-danger)" }}>-{diff.totalDeletions}</span>
          </span>
        </div>

        {/* File list */}
        <div className="px-3 py-2" style={{ borderBottom: "1px solid var(--sm-border)" }}>
          {diff.files.map((file) => (
            <div key={file.name} className="flex items-center gap-2 py-0.5">
              <span className="text-[11px]" style={{ color: "var(--sm-text-primary)" }}>
                {file.name}
              </span>
              <span className="ml-auto font-mono text-[10px]">
                <span style={{ color: "var(--sm-success)" }}>+{file.additions}</span>{" "}
                <span style={{ color: "var(--sm-danger)" }}>-{file.deletions}</span>
              </span>
            </div>
          ))}
        </div>

        {/* Diff snippet */}
        <div className="smithers-scroll overflow-x-auto px-3 py-2" style={{ borderBottom: "1px solid var(--sm-border)" }}>
          <pre className="font-mono text-[12px] leading-relaxed">
            {diff.snippet.split("\n").map((line, i) => (
              <div key={i}>
                <span
                  style={{
                    color: line.startsWith("+")
                      ? "var(--sm-success)"
                      : line.startsWith("-")
                        ? "var(--sm-danger)"
                        : "var(--sm-text-secondary)",
                  }}
                >
                  {line}
                </span>
              </div>
            ))}
          </pre>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-3 py-2">
          <span
            className="flex items-center gap-1 rounded-md px-2 py-0.5 text-[10px] font-medium"
            style={{
              background: statusStyle?.bg,
              color: statusStyle?.color,
            }}
          >
            {statusStyle?.icon}
            {diff.status}
          </span>
          <button
            onClick={onOpenInEditor}
            className="flex items-center gap-1 rounded-md px-2 py-1 text-[10px] font-medium transition-colors"
            style={{ color: "var(--sm-accent)" }}
            onMouseEnter={(e) =>
              (e.currentTarget.style.background = "rgba(76,141,255,0.1)")
            }
            onMouseLeave={(e) =>
              (e.currentTarget.style.background = "transparent")
            }
          >
            <ExternalLink size={10} />
            Open in Editor
          </button>
        </div>
      </div>
    </div>
  )
}
