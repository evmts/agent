"use client"

import React from "react"

import { useState, useCallback } from "react"
import {
  ChevronRight,
  FileText,
  Folder,
  FolderOpen,
  FileCode2,
  FileJson,
  FileType,
  Lock,
  BookOpen,
} from "lucide-react"
import type { FileTreeItem } from "@/lib/mock-data"

interface FileTreeProps {
  items: FileTreeItem[]
  selectedFile?: string
  onSelectFile?: (name: string) => void
}

const fileIcons: Record<string, { icon: React.ReactNode; color: string }> = {
  typescript: { icon: <FileCode2 size={14} />, color: "#3178C6" },
  json: { icon: <FileJson size={14} />, color: "#FFCB6B" },
  env: { icon: <Lock size={14} />, color: "#F07178" },
  markdown: { icon: <BookOpen size={14} />, color: "#60A5FA" },
  default: { icon: <FileText size={14} />, color: "var(--sm-text-secondary)" },
}

export function FileTree({ items, selectedFile, onSelectFile }: FileTreeProps) {
  return (
    <div
      className="smithers-scroll flex h-full flex-col overflow-y-auto"
      style={{ background: "var(--sm-surface1)" }}
    >
      {items.map((item) => (
        <FileTreeNode
          key={item.name}
          item={item}
          selectedFile={selectedFile}
          onSelectFile={onSelectFile}
        />
      ))}
    </div>
  )
}

function FileTreeNode({
  item,
  selectedFile,
  onSelectFile,
}: {
  item: FileTreeItem
  selectedFile?: string
  onSelectFile?: (name: string) => void
}) {
  const [expanded, setExpanded] = useState(item.expanded ?? false)

  const handleClick = useCallback(() => {
    if (item.type === "folder") {
      setExpanded(!expanded)
    } else {
      onSelectFile?.(item.name)
    }
  }, [item, expanded, onSelectFile])

  const isFolder = item.type === "folder"
  const isSelected = selectedFile === item.name
  const iconInfo = isFolder
    ? null
    : fileIcons[item.language || "default"] || fileIcons.default

  return (
    <div>
      <button
        onClick={handleClick}
        className="group relative flex w-full items-center gap-1.5 py-1 pr-3 text-left transition-colors"
        style={{
          paddingLeft: `${item.depth * 16 + 8}px`,
          height: 28,
        }}
        onMouseEnter={(e) => {
          if (!isSelected) e.currentTarget.style.background = "rgba(255,255,255,0.04)"
        }}
        onMouseLeave={(e) => {
          if (!isSelected) e.currentTarget.style.background = "transparent"
        }}
      >
        {/* Selection indicator */}
        {isSelected && (
          <div
            className="absolute left-0 top-1 rounded-r"
            style={{
              width: 3,
              height: "calc(100% - 8px)",
              background: "var(--sm-accent)",
              borderRadius: "0 2px 2px 0",
            }}
          />
        )}

        {/* Indent guides */}
        {item.depth > 0 &&
          Array.from({ length: item.depth }).map((_, i) => (
            <div
              key={i}
              className="absolute top-0 h-full"
              style={{
                left: `${i * 16 + 16}px`,
                width: 1,
                background: "rgba(255,255,255,0.035)",
              }}
            />
          ))}

        {/* Chevron for folders */}
        {isFolder ? (
          <ChevronRight
            size={12}
            className="shrink-0 transition-transform"
            style={{
              transform: expanded ? "rotate(90deg)" : "rotate(0deg)",
              color: "var(--sm-text-tertiary)",
            }}
          />
        ) : (
          <span className="w-3" />
        )}

        {/* Icon */}
        {isFolder ? (
          expanded ? (
            <FolderOpen
              size={14}
              className="shrink-0"
              style={{ color: "var(--sm-accent)" }}
            />
          ) : (
            <Folder
              size={14}
              className="shrink-0"
              style={{ color: "var(--sm-text-secondary)" }}
            />
          )
        ) : (
          <span className="shrink-0" style={{ color: iconInfo?.color }}>
            {iconInfo?.icon}
          </span>
        )}

        {/* Name */}
        <span
          className="flex-1 truncate text-[11px]"
          style={{
            color: isSelected
              ? "var(--sm-text-primary)"
              : isFolder && item.depth === 0
                ? "var(--sm-text-primary)"
                : "var(--sm-text-secondary)",
            fontWeight: isFolder && item.depth === 0 ? 600 : 400,
          }}
        >
          {item.name}
        </span>

        {/* Modified dot */}
        {item.modified && (
          <div
            className="h-1.5 w-1.5 shrink-0 rounded-full"
            style={{ background: "var(--sm-accent)" }}
          />
        )}
      </button>

      {/* Children */}
      {isFolder && expanded && item.children && (
        <div>
          {item.children.map((child) => (
            <FileTreeNode
              key={child.name}
              item={child}
              selectedFile={selectedFile}
              onSelectFile={onSelectFile}
            />
          ))}
        </div>
      )}
    </div>
  )
}
