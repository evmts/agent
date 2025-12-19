# Duplicate Detection Architecture

## System Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Request                              │
│                  "Read package.json twice"                       │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                     streamAgent()                                │
│  Options: { sessionId: "user-123", enableDuplicateDetection }  │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│              wrapToolsWithDuplicateDetection()                   │
│                                                                  │
│  Original tools ──► Wrapped tools (with dedup logic)            │
│                                                                  │
│  { readFile, grep, ... } ──► { readFile*, grep*, ... }         │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Vercel AI SDK (streamText)                     │
│                                                                  │
│  Claude decides to call readFile("package.json") → FIRST CALL   │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Wrapped readFile Execute                        │
│                                                                  │
│  1. Check: tracker.checkDuplicate(sessionId, "readFile", args) │
│     Result: { isDuplicate: false }                              │
│                                                                  │
│  2. Execute: readFileImpl(args) ──► file contents               │
│                                                                  │
│  3. Record: tracker.recordCall(sessionId, "readFile", args,     │
│             result)                                              │
│                                                                  │
│  4. Return: file contents to LLM                                │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ToolCallTracker State                        │
│                                                                  │
│  Session "user-123": [                                          │
│    {                                                             │
│      toolName: "readFile",                                      │
│      args: { filePath: "package.json" },                        │
│      result: "{ name: 'plue', ... }",                           │
│      timestamp: 1702998600000                                   │
│    }                                                             │
│  ]                                                               │
└─────────────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Vercel AI SDK (streamText)                     │
│                                                                  │
│  Claude decides to call readFile("package.json") → SECOND CALL  │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Wrapped readFile Execute                        │
│                                                                  │
│  1. Check: tracker.checkDuplicate(sessionId, "readFile", args) │
│     Result: { isDuplicate: true, previousResult: "..." }       │
│                                                                  │
│  2. Return: "[Cached result from 10:23:45 AM]\n\n..."          │
│     (SKIP execution, return cached result)                      │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Stream Event                                │
│                                                                  │
│  {                                                               │
│    type: "tool_result",                                         │
│    toolName: "readFile",                                        │
│    toolOutput: "[Cached result from 10:23:45 AM]\n\n...",      │
│    cached: true  ◄── Marked as cached                           │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

## Component Relationships

```
┌────────────────────────────────────────────────────────────────┐
│                        Application Layer                        │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  persistedStreamAgent()                                         │
│         │                                                       │
│         ├──► Passes sessionId automatically                    │
│         │                                                       │
│         ▼                                                       │
│  streamAgent()                                                  │
│         │                                                       │
│         ├──► Wraps tools with duplicate detection              │
│         │                                                       │
│         ▼                                                       │
│  wrapToolsWithDuplicateDetection()                             │
│                                                                 │
└─────────┬───────────────────────────────────────────────────┬──┘
          │                                                   │
          │                                                   │
┌─────────▼──────────────────┐              ┌─────────────────▼───┐
│   ToolCallTracker          │              │   Vercel AI SDK     │
├────────────────────────────┤              ├─────────────────────┤
│                            │              │                     │
│  + checkDuplicate()        │◄─────────────┤  streamText()       │
│  + recordCall()            │              │                     │
│  + clearSession()          │              │  Tool execution     │
│  + getStats()              │              │  happens here       │
│                            │              │                     │
│  State:                    │              └─────────────────────┘
│  ├─ Session histories      │
│  ├─ Similarity checkers    │
│  └─ Cleanup logic          │
│                            │
└────────────────────────────┘
```

## Tool Similarity Logic Flow

```
Tool Call: grep({ pattern: "export", path: "/src", glob: "*.ts" })
                              │
                              ▼
                  Is there a custom checker?
                              │
              ┌───────────────┴───────────────┐
              │                               │
             YES                             NO
              │                               │
              ▼                               ▼
   Use tool-specific checker      Use generic fallback
   (from similarityCheckers)       (property matching)
              │                               │
              ▼                               ▼
   Check: pattern, path,          Check: >50% of properties
          glob, multiline,                match OR critical
          caseInsensitive                 identifier matches
              │                               │
              └───────────────┬───────────────┘
                              │
                              ▼
                    Return: boolean (isDuplicate)
```

## Memory Management

```
┌────────────────────────────────────────────────────────────────┐
│                    ToolCallTracker Memory                       │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Map<SessionId, ToolCall[]>                                    │
│                                                                 │
│  session-1: [call1, call2, ..., call50]  ◄── Max 50 calls     │
│  session-2: [call1, call2, call3]                              │
│  session-3: [call1]                                            │
│                                                                 │
│  Cleanup triggers:                                             │
│  ├─ When adding new call (check if > 50)                      │
│  ├─ On each checkDuplicate() (periodic cleanup)               │
│  │                                                             │
│  Cleanup rules:                                                │
│  ├─ Remove entries older than 5 minutes                       │
│  ├─ Keep only last 50 calls per session                       │
│  └─ Remove empty sessions                                     │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

## Session Isolation

```
┌─────────────────────────────────────────────────────────────────┐
│                         Session A                                │
│  User: Alice                                                     │
│  History: [readFile("config.json"), grep("test"), ...]          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Request: readFile("config.json")                               │
│  Result: DUPLICATE DETECTED (cached)                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Session B                                │
│  User: Bob                                                       │
│  History: [webFetch("example.com"), ...]                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Request: readFile("config.json")                               │
│  Result: NOT DUPLICATE (different session, executes normally)   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Tool Categories

```
┌────────────────────────────────────────────────────────────────┐
│                     Cacheable Tools                             │
├────────────────────────────────────────────────────────────────┤
│  readFile     ──► Same path = duplicate                        │
│  grep         ──► Same pattern/path/options = duplicate        │
│  writeFile    ──► Same path + content = duplicate              │
│  multiedit    ──► Same edits = duplicate                       │
│  webFetch     ──► Same URL = duplicate                         │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│                  Never-Cache Tools                              │
├────────────────────────────────────────────────────────────────┤
│  unifiedExec        ──► Commands have side effects             │
│  writeStdin         ──► Interactive I/O                        │
│  closePtySession    ──► Stateful operation                     │
│  listPtySessions    ──► Always needs fresh data                │
└────────────────────────────────────────────────────────────────┘
```

## Performance Characteristics

### Time Complexity

- **checkDuplicate()**: O(1) to O(3)
  - Map lookup: O(1)
  - Check last 3 calls only: O(3)
  - Similarity check: O(p) where p = number of properties

- **recordCall()**: O(1) amortized
  - Map insertion: O(1)
  - Occasional cleanup: O(h) where h = history size

### Space Complexity

- **Per session**: O(50 × s) where s = average result size
- **Global**: O(n × 50 × s) where n = number of active sessions
- **Typical**: ~100KB per session, automatically cleaned up

### Cleanup Overhead

- Triggered on every `checkDuplicate()` call
- Scans all sessions: O(n × h)
- But n is small (active sessions) and happens infrequently
- Amortized cost is negligible
