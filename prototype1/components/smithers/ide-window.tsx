"use client"

import { useState } from "react"
import {
  X,
  FileCode2,
  Terminal,
  MoreHorizontal,
  ChevronRight,
} from "lucide-react"
import { FileTree } from "./file-tree"
import { CodeEditor } from "./code-editor"
import type { FileTreeItem } from "@/lib/mock-data"

interface IDEWindowProps {
  fileTree: FileTreeItem[]
  onClose: () => void
}

interface Tab {
  id: string
  name: string
  type: "file" | "terminal" | "diff"
  modified?: boolean
}

const initialTabs: Tab[] = [
  { id: "t1", name: "auth.ts", type: "file", modified: true },
  { id: "t2", name: "package.json", type: "file", modified: true },
  { id: "t3", name: "Terminal", type: "terminal" },
]

export function IDEWindow({ fileTree, onClose }: IDEWindowProps) {
  const [tabs, setTabs] = useState(initialTabs)
  const [activeTab, setActiveTab] = useState("t1")
  const [selectedFile, setSelectedFile] = useState("auth.ts")
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)

  const handleCloseTab = (tabId: string) => {
    const newTabs = tabs.filter((t) => t.id !== tabId)
    setTabs(newTabs)
    if (activeTab === tabId && newTabs.length > 0) {
      setActiveTab(newTabs[0].id)
    }
  }

  const handleSelectFile = (name: string) => {
    setSelectedFile(name)
    // check if tab exists
    const existing = tabs.find((t) => t.name === name)
    if (existing) {
      setActiveTab(existing.id)
    } else {
      const newTab: Tab = {
        id: `t${Date.now()}`,
        name,
        type: "file",
      }
      setTabs([...tabs, newTab])
      setActiveTab(newTab.id)
    }
  }

  const currentTab = tabs.find((t) => t.id === activeTab)

  // Breadcrumb from file name
  const breadcrumb = currentTab?.type === "file"
    ? `web-app / src / middleware / ${currentTab.name}`
    : null

  return (
    <div
      className="flex h-full flex-col overflow-hidden rounded-lg"
      style={{
        background: "var(--sm-surface1)",
        border: "1px solid var(--sm-border)",
      }}
    >
      {/* Title bar */}
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
          <button
            onClick={onClose}
            className="group h-3 w-3 rounded-full"
            style={{ background: "#FF5F57" }}
          />
          <div className="h-3 w-3 rounded-full" style={{ background: "#FEBC2E" }} />
          <div className="h-3 w-3 rounded-full" style={{ background: "#28C840" }} />
        </div>

        {/* Center title */}
        <div className="flex flex-1 items-center justify-center">
          <span className="text-[11px] font-medium" style={{ color: "var(--sm-titlebar-fg)" }}>
            Editor - web-app
          </span>
        </div>

        <div className="w-[52px]" />
      </div>

      {/* Main content */}
      <div className="flex flex-1 overflow-hidden">
        {/* File tree sidebar */}
        {!sidebarCollapsed && (
          <div
            className="shrink-0 overflow-hidden"
            style={{
              width: 220,
              borderRight: "1px solid var(--sm-border)",
            }}
          >
            {/* Sidebar header */}
            <div
              className="flex items-center justify-between px-3"
              style={{
                height: 32,
                background: "var(--sm-surface2)",
                borderBottom: "1px solid var(--sm-border)",
              }}
            >
              <span
                className="text-[10px] font-semibold uppercase tracking-wider"
                style={{ color: "var(--sm-text-tertiary)" }}
              >
                Explorer
              </span>
              <button
                onClick={() => setSidebarCollapsed(true)}
                className="rounded p-0.5 transition-colors"
                style={{ color: "var(--sm-text-tertiary)" }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = "rgba(255,255,255,0.06)"
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = "transparent"
                }}
              >
                <ChevronRight size={12} style={{ transform: "rotate(180deg)" }} />
              </button>
            </div>
            <FileTree
              items={fileTree}
              selectedFile={selectedFile}
              onSelectFile={handleSelectFile}
            />
          </div>
        )}

        {/* Editor area */}
        <div className="flex flex-1 flex-col overflow-hidden">
          {/* Tab bar */}
          <div
            className="flex shrink-0 items-center overflow-x-auto"
            style={{
              height: 32,
              background: "var(--sm-surface2)",
              borderBottom: "1px solid var(--sm-border)",
            }}
          >
            {sidebarCollapsed && (
              <button
                onClick={() => setSidebarCollapsed(false)}
                className="flex h-full shrink-0 items-center px-2 transition-colors"
                style={{ color: "var(--sm-text-tertiary)", borderRight: "1px solid var(--sm-border)" }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = "rgba(255,255,255,0.06)"
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = "transparent"
                }}
              >
                <ChevronRight size={12} />
              </button>
            )}

            {tabs.map((tab) => (
              <div
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className="group relative flex shrink-0 cursor-pointer items-center gap-2 px-3"
                style={{
                  height: 32,
                  minWidth: 120,
                  maxWidth: 200,
                  background:
                    activeTab === tab.id
                      ? "rgba(255,255,255,0.06)"
                      : "transparent",
                  borderRight: "1px solid var(--sm-border)",
                }}
                onMouseEnter={(e) => {
                  if (activeTab !== tab.id)
                    e.currentTarget.style.background = "rgba(255,255,255,0.03)"
                }}
                onMouseLeave={(e) => {
                  if (activeTab !== tab.id)
                    e.currentTarget.style.background = "transparent"
                }}
              >
                {/* Active tab underline */}
                {activeTab === tab.id && (
                  <div
                    className="absolute bottom-0 left-2 right-2 rounded-t"
                    style={{ height: 2, background: "var(--sm-accent)" }}
                  />
                )}

                {/* Tab icon */}
                {tab.type === "terminal" ? (
                  <Terminal
                    size={12}
                    style={{ color: "var(--sm-success)" }}
                    className="shrink-0"
                  />
                ) : (
                  <FileCode2
                    size={12}
                    style={{ color: "#3178C6" }}
                    className="shrink-0"
                  />
                )}

                {/* Tab name */}
                <span
                  className="truncate text-[11px]"
                  style={{
                    color:
                      activeTab === tab.id
                        ? "var(--sm-text-primary)"
                        : "var(--sm-text-secondary)",
                  }}
                >
                  {tab.name}
                </span>

                {/* Modified dot or close */}
                <div className="ml-auto flex shrink-0 items-center">
                  {tab.modified ? (
                    <div
                      className="h-1.5 w-1.5 rounded-full group-hover:hidden"
                      style={{ background: "var(--sm-accent)" }}
                    />
                  ) : null}
                  <button
                    onClick={(e) => {
                      e.stopPropagation()
                      handleCloseTab(tab.id)
                    }}
                    className={`rounded p-0.5 transition-colors ${tab.modified ? "hidden group-hover:flex" : "opacity-0 group-hover:opacity-100"}`}
                    style={{ color: "var(--sm-text-tertiary)" }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.background = "rgba(255,255,255,0.1)"
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.background = "transparent"
                    }}
                  >
                    <X size={10} />
                  </button>
                </div>
              </div>
            ))}

            {/* Spacer + overflow */}
            <div className="flex-1" />
            <button
              className="flex h-full shrink-0 items-center px-2"
              style={{ color: "var(--sm-text-tertiary)" }}
            >
              <MoreHorizontal size={14} />
            </button>
          </div>

          {/* Breadcrumb */}
          {breadcrumb && (
            <div
              className="flex shrink-0 items-center gap-1 px-3"
              style={{
                height: 22,
                background: "var(--sm-surface1)",
                borderBottom: "1px solid var(--sm-border)",
              }}
            >
              {breadcrumb.split(" / ").map((seg, i, arr) => (
                <span key={i} className="flex items-center gap-1">
                  <span
                    className="cursor-pointer text-[10px] transition-colors hover:underline"
                    style={{
                      color:
                        i === arr.length - 1
                          ? "var(--sm-text-primary)"
                          : "var(--sm-text-tertiary)",
                      fontWeight: i === arr.length - 1 ? 600 : 400,
                    }}
                  >
                    {seg}
                  </span>
                  {i < arr.length - 1 && (
                    <ChevronRight
                      size={8}
                      style={{ color: "var(--sm-text-tertiary)" }}
                    />
                  )}
                </span>
              ))}
            </div>
          )}

          {/* Content area */}
          <div className="flex-1 overflow-hidden">
            {currentTab?.type === "terminal" ? (
              <TerminalContent />
            ) : (
              <CodeEditor />
            )}
          </div>

          {/* Status bar */}
          <div
            className="flex shrink-0 items-center justify-between px-3"
            style={{
              height: 22,
              background: "var(--sm-surface2)",
              borderTop: "1px solid var(--sm-border)",
            }}
          >
            <span
              className="font-mono text-[10px]"
              style={{ color: "var(--sm-text-secondary)" }}
            >
              Ln 15, Col 24 | UTF-8 | LF
            </span>
            <div className="flex items-center gap-3">
              <span
                className="text-[10px]"
                style={{ color: "var(--sm-text-secondary)" }}
              >
                Skills: jose-migration
              </span>
              <span
                className="font-mono text-[10px]"
                style={{ color: "var(--sm-text-secondary)" }}
              >
                TypeScript | Spaces: 2
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function TerminalContent() {
  const terminalLines = [
    { text: "$ npm test -- --filter auth", style: "bold" as const },
    { text: "", style: "normal" as const },
    { text: " PASS  tests/auth.test.ts", style: "success" as const },
    { text: "  Auth Middleware", style: "normal" as const },
    { text: "    \u2713 should reject requests without token (3ms)", style: "success" as const },
    { text: "    \u2713 should reject requests with invalid token (5ms)", style: "success" as const },
    { text: "    \u2713 should accept requests with valid token (4ms)", style: "success" as const },
    { text: "    \u2713 should decode payload correctly (3ms)", style: "success" as const },
    { text: "", style: "normal" as const },
    { text: "Test Suites: 1 passed, 1 total", style: "normal" as const },
    { text: "Tests:       4 passed, 4 total", style: "success" as const },
    { text: "Time:        1.234s", style: "normal" as const },
    { text: "", style: "normal" as const },
    { text: "~/projects/web-app $", style: "normal" as const },
  ]

  const styleMap = {
    bold: "var(--sm-text-primary)",
    normal: "var(--sm-text-secondary)",
    success: "var(--sm-success)",
  }

  return (
    <div
      className="smithers-scroll h-full overflow-auto p-3"
      style={{ background: "var(--sm-base)" }}
    >
      <pre className="font-mono text-[13px]" style={{ lineHeight: 1.5 }}>
        {terminalLines.map((line, i) => (
          <div key={i}>
            <span
              style={{
                color: styleMap[line.style],
                fontWeight: line.style === "bold" ? 600 : 400,
              }}
            >
              {line.text}
            </span>
          </div>
        ))}
        {/* Blinking cursor */}
        <span
          className="animate-pulse"
          style={{ color: "var(--sm-text-primary)" }}
        >
          {"\\u2588"}
        </span>
      </pre>
    </div>
  )
}
