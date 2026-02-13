import { JSX } from "solid-js";
import { cn } from "./lib/cn";
import { Button } from "./components/ui/button";

function TitleBar(): JSX.Element {
  return (
    <div
      class={cn(
        "h-[28px] flex items-center justify-between px-3 border-b",
        "bg-[color:var(--sm-titlebar-bg)] border-[color:var(--sm-border)]",
      )}
    >
      <div />
      <div
        class={cn(
          "text-[var(--sm-titlebar-fg)]",
          "text-[var(--sm-type-s)] select-none",
        )}
      >
        Smithers — Workspace
      </div>
      <Button variant="ghost" size="sm" title="Open Editor">
        ⌘E
      </Button>
    </div>
  );
}

function ChatPane(): JSX.Element {
  return (
    <div class="flex h-full">
      {/* Sidebar */}
      <div
        class={cn(
          "w-[260px] border-r flex flex-col",
          "bg-[color:var(--sm-sidebar-bg)] border-[color:var(--sm-border)]",
        )}
      >
        <div class="h-10 px-2 flex items-center gap-2">
          <button
            class={cn(
              "h-7 px-2 rounded-md text-[11px] border",
              "bg-[color:var(--sm-pill-bg)] border-[color:var(--sm-pill-border)]",
              "hover:bg-[color:var(--sm-pill-active)]",
            )}
            type="button"
          >
            Chats
          </button>
          <button
            class={cn(
              "h-7 px-2 rounded-md text-[11px] border",
              "bg-transparent border-transparent text-[color:var(--sm-text-secondary)]",
              "hover:bg-[color:var(--sm-sidebar-hover)]",
            )}
            type="button"
          >
            Source
          </button>
          <button
            class={cn(
              "h-7 px-2 rounded-md text-[11px] border",
              "bg-transparent border-transparent text-[color:var(--sm-text-secondary)]",
              "hover:bg-[color:var(--sm-sidebar-hover)]",
            )}
            type="button"
          >
            Agents
          </button>
        </div>
        <div class="px-2 text-[10px] uppercase text-[color:var(--sm-text-tertiary)] tracking-wide">
          Today
        </div>
        <div class="mt-1">
          <div
            class={cn(
              "px-3 py-2 cursor-pointer",
              "hover:bg-[color:var(--sm-sidebar-hover)]",
            )}
          >
            Initial chat session
          </div>
          <div
            class={cn(
              "px-3 py-2 cursor-pointer",
              "hover:bg-[color:var(--sm-sidebar-hover)]",
            )}
          >
            Fix login bug
          </div>
        </div>
      </div>

      {/* Detail */}
      <div class="flex-1 flex flex-col">
        <TitleBar />
        <div class="flex-1 overflow-auto p-4 space-y-3">
          <div
            class={cn(
              "max-w-[70%] rounded-[12px] p-3",
              "bg-[color:var(--sm-bubble-assistant)]",
            )}
          >
            <div class="text-[13px] leading-[1.5]">
              Hello! I can help you scaffold the web app. Try running{" "}
              <code>zig build web</code> when ready.
            </div>
          </div>
          <div
            class={cn(
              "ml-auto max-w-[70%] rounded-[12px] p-3",
              "bg-[color:var(--sm-bubble-user)]",
            )}
          >
            <div class="text-[13px] leading-[1.5]">Great — let’s do it.</div>
          </div>
          <div
            class={cn(
              "max-w-[80%] rounded-[12px] p-0 overflow-hidden border",
              "bg-[color:var(--sm-bubble-command)] border-[color:var(--sm-border)]",
            )}
          >
            <div class="px-3 py-2 text-[12px] font-mono">$ pnpm build</div>
            <pre class="m-0 p-3 text-[12px] font-mono overflow-auto">
              ...output streaming here...
            </pre>
          </div>
        </div>
        <div class={cn("p-3 border-t", "border-[color:var(--sm-border)]")}>
          <div
            class={cn(
              "rounded-[10px] p-2 flex items-center gap-2 border",
              "bg-[color:var(--sm-input-bg)] border-[color:var(--sm-input-border)]",
            )}
          >
            <input
              class="flex-1 bg-transparent outline-none text-[13px]"
              placeholder="Message Smithers..."
            />
            <Button size="md" title="Send">
              ↑
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}

function IDEPane(): JSX.Element {
  return (
    <div class="flex h-full">
      <div
        class={cn(
          "w-[240px] border-r",
          "bg-[color:var(--sm-surface1)] border-[color:var(--sm-border)]",
        )}
      >
        <div class="h-[32px] flex items-center px-3 text-[11px] text-[color:var(--sm-text-secondary)] border-b border-[color:var(--sm-border)]">
          File Tree
        </div>
        <div class="p-2 text-[11px] space-y-1">
          <div class="hover:bg-[color:var(--sm-sidebar-hover)] rounded px-2 py-1">
            src/
          </div>
          <div class="hover:bg-[color:var(--sm-sidebar-hover)] rounded px-2 py-1">
            README.md
          </div>
        </div>
      </div>
      <div class="flex-1 flex flex-col">
        <div
          class={cn(
            "h-[32px] flex items-center gap-2 px-3 border-b",
            "bg-[color:var(--sm-surface2)] border-[color:var(--sm-border)]",
          )}
        >
          <div class="px-2 py-1 rounded-md text-[11px] bg-[color:var(--sm-pill-bg)]">
            README.md
          </div>
        </div>
        <div
          class={cn(
            "flex-1 p-4 font-mono text-[13px] leading-[1.4] overflow-auto",
            "bg-[color:var(--sm-surface1)]",
          )}
        >
          <span class="text-[color:var(--syn-keyword)]">fn</span>{" "}
          <span class="text-[color:var(--syn-function)]">main</span>() {"{"}
          <br />
          &nbsp;&nbsp;println!(
          <span class="text-[color:var(--syn-string)]">"Hello, Smithers"</span>
          );
          <br />
          {"}"}
        </div>
        <div
          class={cn(
            "h-[22px] text-[10px] px-3 flex items-center justify-between border-t",
            "bg-[color:var(--sm-surface2)] border-[color:var(--sm-border)] text-[color:var(--sm-text-secondary)]",
          )}
        >
          <div>Ln 1, Col 1 | UTF-8 | LF</div>
          <div>Spaces: 4</div>
        </div>
      </div>
    </div>
  );
}

export default function App(): JSX.Element {
  return (
    <div class="h-full w-full" style={{ background: "var(--sm-base)" }}>
      <div
        class="h-10 px-3 flex items-center justify-between border-b border-[color:var(--sm-border)]"
        style={{ background: "var(--sm-surface2)" }}
      >
        <div class="text-[13px]">Smithers v2</div>
        <div class="text-[11px] px-2 py-1 rounded-full border bg-[color:var(--sm-pill-bg)] border-[color:var(--sm-pill-border)]">
          Tokens live
        </div>
      </div>
      <div class="h-[calc(100%-40px)] flex">
        <div class="w-[45%] border-r border-[color:var(--sm-border)]">
          <ChatPane />
        </div>
        <div class="w-[55%]">
          <IDEPane />
        </div>
      </div>
    </div>
  );
}
