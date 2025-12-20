/**
 * Database operations for agent state.
 *
 * Replaces in-memory Maps with PostgreSQL persistence.
 */

import sql from "./client";
import type {
  Session,
  Message,
  MessageStatus,
  UserMessage,
  AssistantMessage,
  Part,
  TextPart,
  ReasoningPart,
  ToolPart,
  FilePart,
} from "../core/models";

// =============================================================================
// Type Definitions
// =============================================================================

export interface MessageWithParts {
  info: Message;
  parts: Part[];
}

export interface FileTimeTracker {
  readTimes: Map<string, number>;
  modTimes: Map<string, number>;
}

// =============================================================================
// Helper Functions
// =============================================================================

/**
 * Safely parse JSON with fallback value on error
 */
function safeJsonParse<T>(value: string | null | undefined, fallback: T): T {
  if (!value) return fallback;
  try {
    return JSON.parse(value) as T;
  } catch (error) {
    console.error('Failed to parse JSON:', error);
    return fallback;
  }
}

// =============================================================================
// Session Operations
// =============================================================================

export async function getSession(sessionId: string): Promise<Session | null> {
  const rows = await sql`
    SELECT * FROM sessions WHERE id = ${sessionId}
  `;

  const row = rows[0];
  if (!row) return null;
  return rowToSession(row);
}

export async function getAllSessions(): Promise<Session[]> {
  const rows = await sql`
    SELECT * FROM sessions ORDER BY time_updated DESC
  `;
  return rows.map(rowToSession);
}

export async function saveSession(session: Session): Promise<void> {
  await sql`
    INSERT INTO sessions (
      id, project_id, directory, title, version,
      time_created, time_updated, time_archived,
      parent_id, fork_point, summary, revert, compaction,
      token_count, bypass_mode, model, reasoning_effort,
      ghost_commit, plugins
    ) VALUES (
      ${session.id},
      ${session.projectID},
      ${session.directory},
      ${session.title},
      ${session.version},
      ${session.time.created},
      ${session.time.updated},
      ${session.time.archived ?? null},
      ${session.parentID ?? null},
      ${session.forkPoint ?? null},
      ${session.summary ? JSON.stringify(session.summary) : null},
      ${session.revert ? JSON.stringify(session.revert) : null},
      ${session.compaction ? JSON.stringify(session.compaction) : null},
      ${session.tokenCount},
      ${session.bypassMode},
      ${session.model ?? null},
      ${session.reasoningEffort ?? null},
      ${session.ghostCommit ? JSON.stringify(session.ghostCommit) : null},
      ${JSON.stringify(session.plugins)}
    )
    ON CONFLICT (id) DO UPDATE SET
      project_id = EXCLUDED.project_id,
      directory = EXCLUDED.directory,
      title = EXCLUDED.title,
      version = EXCLUDED.version,
      time_created = EXCLUDED.time_created,
      time_updated = EXCLUDED.time_updated,
      time_archived = EXCLUDED.time_archived,
      parent_id = EXCLUDED.parent_id,
      fork_point = EXCLUDED.fork_point,
      summary = EXCLUDED.summary,
      revert = EXCLUDED.revert,
      compaction = EXCLUDED.compaction,
      token_count = EXCLUDED.token_count,
      bypass_mode = EXCLUDED.bypass_mode,
      model = EXCLUDED.model,
      reasoning_effort = EXCLUDED.reasoning_effort,
      ghost_commit = EXCLUDED.ghost_commit,
      plugins = EXCLUDED.plugins
  `;
}

export async function deleteSession(sessionId: string): Promise<void> {
  await sql`DELETE FROM sessions WHERE id = ${sessionId}`;
}

function rowToSession(row: Record<string, unknown>): Session {
  return {
    id: row.id as string,
    projectID: row.project_id as string,
    directory: row.directory as string,
    title: row.title as string,
    version: row.version as string,
    time: {
      created: Number(row.time_created),
      updated: Number(row.time_updated),
      archived: row.time_archived ? Number(row.time_archived) : undefined,
    },
    parentID: row.parent_id as string | undefined,
    forkPoint: row.fork_point as string | undefined,
    summary: row.summary ? safeJsonParse(row.summary as string, undefined) as Session["summary"] : undefined,
    revert: row.revert ? safeJsonParse(row.revert as string, undefined) as Session["revert"] : undefined,
    compaction: row.compaction ? safeJsonParse(row.compaction as string, undefined) as Session["compaction"] : undefined,
    tokenCount: Number(row.token_count),
    bypassMode: row.bypass_mode as boolean,
    model: row.model as string | undefined,
    reasoningEffort: row.reasoning_effort as Session["reasoningEffort"],
    ghostCommit: row.ghost_commit ? safeJsonParse(row.ghost_commit as string, undefined) as Session["ghostCommit"] : undefined,
    plugins: safeJsonParse((row.plugins as string), []) as string[],
  };
}

// =============================================================================
// Message Operations
// =============================================================================

export async function getSessionMessages(
  sessionId: string
): Promise<MessageWithParts[]> {
  const messageRows = await sql`
    SELECT * FROM messages
    WHERE session_id = ${sessionId}
    ORDER BY created_at ASC
  `;

  const partRows = await sql`
    SELECT * FROM parts
    WHERE session_id = ${sessionId}
    ORDER BY message_id, sort_order ASC
  `;

  // Group parts by message ID
  const partsByMessage = new Map<string, Part[]>();
  for (const row of partRows) {
    const part = rowToPart(row);
    const existing = partsByMessage.get(part.messageID) ?? [];
    existing.push(part);
    partsByMessage.set(part.messageID, existing);
  }

  return messageRows.map((row) => ({
    info: rowToMessage(row),
    parts: partsByMessage.get(row.id as string) ?? [],
  }));
}

export async function appendMessage(
  _sessionId: string,
  message: MessageWithParts
): Promise<void> {
  await saveMessage(message.info);
  for (let i = 0; i < message.parts.length; i++) {
    const part = message.parts[i];
    if (part) {
      await savePart(part, i);
    }
  }
}

export async function saveMessage(message: Message): Promise<void> {
  if (message.role === "user") {
    const userMsg = message as UserMessage;
    await sql`
      INSERT INTO messages (
        id, session_id, role, time_created, time_completed,
        status, thinking_text, error_message,
        agent, model_provider_id, model_model_id, system_prompt, tools
      ) VALUES (
        ${userMsg.id},
        ${userMsg.sessionID},
        ${userMsg.role},
        ${userMsg.time.created},
        ${userMsg.time.completed ?? null},
        ${userMsg.status},
        ${userMsg.thinkingText ?? null},
        ${userMsg.errorMessage ?? null},
        ${userMsg.agent},
        ${userMsg.model.providerID},
        ${userMsg.model.modelID},
        ${userMsg.system ?? null},
        ${userMsg.tools ? JSON.stringify(userMsg.tools) : null}
      )
      ON CONFLICT (id) DO UPDATE SET
        time_completed = EXCLUDED.time_completed,
        status = EXCLUDED.status,
        thinking_text = EXCLUDED.thinking_text,
        error_message = EXCLUDED.error_message,
        system_prompt = EXCLUDED.system_prompt,
        tools = EXCLUDED.tools
    `;
  } else {
    const assistantMsg = message as AssistantMessage;
    await sql`
      INSERT INTO messages (
        id, session_id, role, time_created, time_completed,
        status, thinking_text, error_message,
        parent_id, mode, path_cwd, path_root,
        cost, tokens_input, tokens_output, tokens_reasoning,
        tokens_cache_read, tokens_cache_write,
        finish, is_summary, error,
        model_provider_id, model_model_id
      ) VALUES (
        ${assistantMsg.id},
        ${assistantMsg.sessionID},
        ${assistantMsg.role},
        ${assistantMsg.time.created},
        ${assistantMsg.time.completed ?? null},
        ${assistantMsg.status},
        ${assistantMsg.thinkingText ?? null},
        ${assistantMsg.errorMessage ?? null},
        ${assistantMsg.parentID},
        ${assistantMsg.mode},
        ${assistantMsg.path.cwd},
        ${assistantMsg.path.root},
        ${assistantMsg.cost},
        ${assistantMsg.tokens.input},
        ${assistantMsg.tokens.output},
        ${assistantMsg.tokens.reasoning},
        ${assistantMsg.tokens.cache?.read ?? null},
        ${assistantMsg.tokens.cache?.write ?? null},
        ${assistantMsg.finish ?? null},
        ${assistantMsg.summary ?? null},
        ${assistantMsg.error ? JSON.stringify(assistantMsg.error) : null},
        ${assistantMsg.providerID},
        ${assistantMsg.modelID}
      )
      ON CONFLICT (id) DO UPDATE SET
        time_completed = EXCLUDED.time_completed,
        status = EXCLUDED.status,
        thinking_text = EXCLUDED.thinking_text,
        error_message = EXCLUDED.error_message,
        cost = EXCLUDED.cost,
        tokens_input = EXCLUDED.tokens_input,
        tokens_output = EXCLUDED.tokens_output,
        tokens_reasoning = EXCLUDED.tokens_reasoning,
        tokens_cache_read = EXCLUDED.tokens_cache_read,
        tokens_cache_write = EXCLUDED.tokens_cache_write,
        finish = EXCLUDED.finish,
        is_summary = EXCLUDED.is_summary,
        error = EXCLUDED.error
    `;
  }
}

export async function savePart(part: Part, sortOrder: number): Promise<void> {
  const base = {
    id: part.id,
    session_id: part.sessionID,
    message_id: part.messageID,
    type: part.type,
    sort_order: sortOrder,
  };

  if (part.type === "text") {
    const textPart = part as TextPart;
    await sql`
      INSERT INTO parts (id, session_id, message_id, type, text, time_start, time_end, sort_order)
      VALUES (
        ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
        ${textPart.text},
        ${textPart.time?.start ?? null},
        ${textPart.time?.end ?? null},
        ${base.sort_order}
      )
      ON CONFLICT (id) DO UPDATE SET
        text = EXCLUDED.text,
        time_start = EXCLUDED.time_start,
        time_end = EXCLUDED.time_end
    `;
  } else if (part.type === "reasoning") {
    const reasoningPart = part as ReasoningPart;
    await sql`
      INSERT INTO parts (id, session_id, message_id, type, text, time_start, time_end, sort_order)
      VALUES (
        ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
        ${reasoningPart.text},
        ${reasoningPart.time.start},
        ${reasoningPart.time.end ?? null},
        ${base.sort_order}
      )
      ON CONFLICT (id) DO UPDATE SET
        text = EXCLUDED.text,
        time_start = EXCLUDED.time_start,
        time_end = EXCLUDED.time_end
    `;
  } else if (part.type === "tool") {
    const toolPart = part as ToolPart;
    await sql`
      INSERT INTO parts (id, session_id, message_id, type, tool_name, tool_state, sort_order)
      VALUES (
        ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
        ${toolPart.tool},
        ${JSON.stringify(toolPart.state)},
        ${base.sort_order}
      )
      ON CONFLICT (id) DO UPDATE SET
        tool_name = EXCLUDED.tool_name,
        tool_state = EXCLUDED.tool_state
    `;
  } else if (part.type === "file") {
    const filePart = part as FilePart;
    await sql`
      INSERT INTO parts (id, session_id, message_id, type, mime, url, filename, sort_order)
      VALUES (
        ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
        ${filePart.mime},
        ${filePart.url},
        ${filePart.filename ?? null},
        ${base.sort_order}
      )
      ON CONFLICT (id) DO UPDATE SET
        mime = EXCLUDED.mime,
        url = EXCLUDED.url,
        filename = EXCLUDED.filename
    `;
  }
}

export async function setSessionMessages(
  sessionId: string,
  messages: MessageWithParts[]
): Promise<void> {
  // Use transaction to ensure atomicity
  await sql.begin(async (tx) => {
    // Delete existing (cascade from messages to parts via FK)
    await tx`DELETE FROM messages WHERE session_id = ${sessionId}`;

    // Insert all messages and their parts
    for (const msg of messages) {
      const message = msg.info;

      // Insert message - handle both user and assistant types within transaction
      if (message.role === "user") {
        const userMsg = message as UserMessage;
        await tx`
          INSERT INTO messages (
            id, session_id, role, time_created, time_completed,
            status, thinking_text, error_message,
            agent, model_provider_id, model_model_id, system_prompt, tools
          ) VALUES (
            ${userMsg.id}, ${userMsg.sessionID}, ${userMsg.role},
            ${userMsg.time.created}, ${userMsg.time.completed ?? null},
            ${userMsg.status}, ${userMsg.thinkingText ?? null}, ${userMsg.errorMessage ?? null},
            ${userMsg.agent}, ${userMsg.model.providerID}, ${userMsg.model.modelID},
            ${userMsg.system ?? null}, ${userMsg.tools ? JSON.stringify(userMsg.tools) : null}
          )
        `;
      } else {
        const assistantMsg = message as AssistantMessage;
        await tx`
          INSERT INTO messages (
            id, session_id, role, time_created, time_completed,
            status, thinking_text, error_message,
            parent_id, mode, path_cwd, path_root,
            cost, tokens_input, tokens_output, tokens_reasoning,
            tokens_cache_read, tokens_cache_write,
            finish, is_summary, error,
            model_provider_id, model_model_id
          ) VALUES (
            ${assistantMsg.id}, ${assistantMsg.sessionID}, ${assistantMsg.role},
            ${assistantMsg.time.created}, ${assistantMsg.time.completed ?? null},
            ${assistantMsg.status}, ${assistantMsg.thinkingText ?? null}, ${assistantMsg.errorMessage ?? null},
            ${assistantMsg.parentID}, ${assistantMsg.mode}, ${assistantMsg.path.cwd}, ${assistantMsg.path.root},
            ${assistantMsg.cost}, ${assistantMsg.tokens.input}, ${assistantMsg.tokens.output}, ${assistantMsg.tokens.reasoning},
            ${assistantMsg.tokens.cache?.read ?? null}, ${assistantMsg.tokens.cache?.write ?? null},
            ${assistantMsg.finish ?? null}, ${assistantMsg.summary ?? null},
            ${assistantMsg.error ? JSON.stringify(assistantMsg.error) : null},
            ${assistantMsg.providerID}, ${assistantMsg.modelID}
          )
        `;
      }

      // Insert parts - handle different part types
      for (let i = 0; i < msg.parts.length; i++) {
        const part = msg.parts[i];
        if (!part) continue;

        const base = {
          id: part.id,
          session_id: sessionId,
          message_id: msg.info.id,
          type: part.type,
          sort_order: i,
        };

        if (part.type === "text") {
          const textPart = part as TextPart;
          await tx`
            INSERT INTO parts (id, session_id, message_id, type, text, time_start, time_end, sort_order)
            VALUES (
              ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
              ${textPart.text}, ${textPart.time?.start ?? null}, ${textPart.time?.end ?? null}, ${base.sort_order}
            )
          `;
        } else if (part.type === "reasoning") {
          const reasoningPart = part as ReasoningPart;
          await tx`
            INSERT INTO parts (id, session_id, message_id, type, text, time_start, time_end, sort_order)
            VALUES (
              ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
              ${reasoningPart.text}, ${reasoningPart.time.start}, ${reasoningPart.time.end ?? null}, ${base.sort_order}
            )
          `;
        } else if (part.type === "tool") {
          const toolPart = part as ToolPart;
          await tx`
            INSERT INTO parts (id, session_id, message_id, type, tool_name, tool_state, sort_order)
            VALUES (
              ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
              ${toolPart.tool}, ${JSON.stringify(toolPart.state)}, ${base.sort_order}
            )
          `;
        } else if (part.type === "file") {
          const filePart = part as FilePart;
          await tx`
            INSERT INTO parts (id, session_id, message_id, type, mime, url, filename, sort_order)
            VALUES (
              ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
              ${filePart.mime}, ${filePart.url}, ${filePart.filename ?? null}, ${base.sort_order}
            )
          `;
        }
      }
    }
  });
}

function rowToMessage(row: Record<string, unknown>): Message {
  if (row.role === "user") {
    return {
      id: row.id as string,
      sessionID: row.session_id as string,
      role: "user",
      time: {
        created: Number(row.time_created),
        completed: row.time_completed ? Number(row.time_completed) : undefined,
      },
      status: (row.status as MessageStatus) || 'pending',
      thinkingText: row.thinking_text as string | undefined,
      errorMessage: row.error_message as string | undefined,
      agent: row.agent as string,
      model: {
        providerID: row.model_provider_id as string,
        modelID: row.model_model_id as string,
      },
      system: row.system_prompt as string | undefined,
      tools: row.tools ? safeJsonParse(row.tools as string, undefined) as Record<string, boolean> : undefined,
    } as UserMessage;
  } else {
    return {
      id: row.id as string,
      sessionID: row.session_id as string,
      role: "assistant",
      time: {
        created: Number(row.time_created),
        completed: row.time_completed ? Number(row.time_completed) : undefined,
      },
      status: (row.status as MessageStatus) || 'pending',
      thinkingText: row.thinking_text as string | undefined,
      errorMessage: row.error_message as string | undefined,
      parentID: row.parent_id as string,
      modelID: row.model_model_id as string,
      providerID: row.model_provider_id as string,
      mode: row.mode as string,
      path: {
        cwd: row.path_cwd as string,
        root: row.path_root as string,
      },
      cost: Number(row.cost),
      tokens: {
        input: Number(row.tokens_input),
        output: Number(row.tokens_output),
        reasoning: Number(row.tokens_reasoning),
        cache:
          row.tokens_cache_read != null
            ? {
                read: Number(row.tokens_cache_read),
                write: Number(row.tokens_cache_write),
              }
            : undefined,
      },
      finish: row.finish as string | undefined,
      summary: row.is_summary as boolean | undefined,
      error: row.error ? safeJsonParse(row.error as string, undefined) as Record<string, unknown> : undefined,
    } as AssistantMessage;
  }
}

function rowToPart(row: Record<string, unknown>): Part {
  const base = {
    id: row.id as string,
    sessionID: row.session_id as string,
    messageID: row.message_id as string,
  };

  switch (row.type) {
    case "text":
      return {
        ...base,
        type: "text",
        text: row.text as string,
        time:
          row.time_start != null
            ? {
                start: Number(row.time_start),
                end: row.time_end ? Number(row.time_end) : undefined,
              }
            : undefined,
      } as TextPart;

    case "reasoning":
      return {
        ...base,
        type: "reasoning",
        text: row.text as string,
        time: {
          start: Number(row.time_start),
          end: row.time_end ? Number(row.time_end) : undefined,
        },
      } as ReasoningPart;

    case "tool":
      return {
        ...base,
        type: "tool",
        tool: row.tool_name as string,
        state: safeJsonParse((row.tool_state as string), {}) as ToolPart["state"],
      } as ToolPart;

    case "file":
      return {
        ...base,
        type: "file",
        mime: row.mime as string,
        url: row.url as string,
        filename: row.filename as string | undefined,
      } as FilePart;

    default:
      throw new Error(`Unknown part type: ${row.type}`);
  }
}

// =============================================================================
// Snapshot History Operations
// =============================================================================

export async function getSnapshotHistory(sessionId: string): Promise<string[]> {
  const rows = await sql`
    SELECT change_id FROM snapshot_history
    WHERE session_id = ${sessionId}
    ORDER BY sort_order ASC
  `;
  return rows.map((r) => r.change_id as string);
}

export async function setSnapshotHistory(
  sessionId: string,
  history: string[]
): Promise<void> {
  await sql`DELETE FROM snapshot_history WHERE session_id = ${sessionId}`;

  for (let i = 0; i < history.length; i++) {
    const changeId = history[i];
    if (changeId !== undefined) {
      await sql`
        INSERT INTO snapshot_history (session_id, change_id, sort_order)
        VALUES (${sessionId}, ${changeId}, ${i})
      `;
    }
  }
}

export async function appendSnapshotHistory(
  sessionId: string,
  changeId: string
): Promise<void> {
  await sql`
    INSERT INTO snapshot_history (session_id, change_id, sort_order)
    VALUES (
      ${sessionId},
      ${changeId},
      (SELECT COALESCE(MAX(sort_order), -1) + 1 FROM snapshot_history WHERE session_id = ${sessionId})
    )
  `;
}

// =============================================================================
// Subtask Operations
// =============================================================================

export async function getSubtasks(
  sessionId: string
): Promise<Array<Record<string, unknown>>> {
  const rows = await sql`
    SELECT result FROM subtasks
    WHERE session_id = ${sessionId}
    ORDER BY created_at ASC
  `;
  return rows.map((r) => safeJsonParse((r.result as string), {}) as Record<string, unknown>);
}

export async function appendSubtask(
  sessionId: string,
  result: Record<string, unknown>
): Promise<void> {
  await sql`
    INSERT INTO subtasks (session_id, result)
    VALUES (${sessionId}, ${JSON.stringify(result)})
  `;
}

export async function clearSubtasks(sessionId: string): Promise<void> {
  await sql`DELETE FROM subtasks WHERE session_id = ${sessionId}`;
}

// =============================================================================
// File Tracker Operations
// =============================================================================

export async function getFileTracker(
  sessionId: string
): Promise<FileTimeTracker> {
  const rows = await sql`
    SELECT file_path, read_time, mod_time FROM file_trackers
    WHERE session_id = ${sessionId}
  `;

  const tracker: FileTimeTracker = {
    readTimes: new Map(),
    modTimes: new Map(),
  };

  for (const row of rows) {
    const path = row.file_path as string;
    if (row.read_time != null) {
      tracker.readTimes.set(path, Number(row.read_time));
    }
    if (row.mod_time != null) {
      tracker.modTimes.set(path, Number(row.mod_time));
    }
  }

  return tracker;
}

export async function updateFileTracker(
  sessionId: string,
  filePath: string,
  readTime?: number,
  modTime?: number
): Promise<void> {
  await sql`
    INSERT INTO file_trackers (session_id, file_path, read_time, mod_time)
    VALUES (${sessionId}, ${filePath}, ${readTime ?? null}, ${modTime ?? null})
    ON CONFLICT (session_id, file_path) DO UPDATE SET
      read_time = COALESCE(EXCLUDED.read_time, file_trackers.read_time),
      mod_time = COALESCE(EXCLUDED.mod_time, file_trackers.mod_time)
  `;
}

export async function clearFileTrackers(sessionId: string): Promise<void> {
  await sql`DELETE FROM file_trackers WHERE session_id = ${sessionId}`;
}

// =============================================================================
// Streaming Part Operations
// =============================================================================

/**
 * Generate a unique message ID.
 */
export function generateMessageId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let id = 'msg_';
  for (let i = 0; i < 12; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

/**
 * Generate a unique part ID.
 */
function generatePartId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let id = 'part_';
  for (let i = 0; i < 12; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

/**
 * Append a single part to a message during streaming.
 * Used for real-time persistence as events are generated.
 */
export async function appendStreamingPart(
  sessionId: string,
  messageId: string,
  partData: {
    type: 'text' | 'reasoning' | 'tool';
    text?: string;
    tool_name?: string;
    tool_state?: Record<string, unknown>;
    sort_order: number;
    time_start?: number;
    time_end?: number;
  }
): Promise<string> {
  const partId = generatePartId();

  const base = {
    id: partId,
    session_id: sessionId,
    message_id: messageId,
    type: partData.type,
    sort_order: partData.sort_order,
    time_start: partData.time_start ?? null,
    time_end: partData.time_end ?? null,
  };

  if (partData.type === 'text' || partData.type === 'reasoning') {
    await sql`
      INSERT INTO parts (id, session_id, message_id, type, text, time_start, time_end, sort_order)
      VALUES (
        ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
        ${partData.text ?? ''},
        ${base.time_start},
        ${base.time_end},
        ${base.sort_order}
      )
    `;
  } else if (partData.type === 'tool') {
    await sql`
      INSERT INTO parts (id, session_id, message_id, type, tool_name, tool_state, time_start, time_end, sort_order)
      VALUES (
        ${base.id}, ${base.session_id}, ${base.message_id}, ${base.type},
        ${partData.tool_name ?? ''},
        ${partData.tool_state ? JSON.stringify(partData.tool_state) : null},
        ${base.time_start},
        ${base.time_end},
        ${base.sort_order}
      )
    `;
  }

  return partId;
}

/**
 * Update an existing part (e.g., to append text or update tool state).
 */
export async function updateStreamingPart(
  partId: string,
  updates: {
    text?: string;
    tool_state?: Record<string, unknown>;
    time_end?: number;
  }
): Promise<void> {
  // Build dynamic update query based on what's provided
  const setClauses: string[] = [];
  const values: unknown[] = [];

  if (updates.text !== undefined) {
    setClauses.push('text = $' + (values.length + 1));
    values.push(updates.text);
  }

  if (updates.tool_state !== undefined) {
    setClauses.push('tool_state = $' + (values.length + 1));
    values.push(JSON.stringify(updates.tool_state));
  }

  if (updates.time_end !== undefined) {
    setClauses.push('time_end = $' + (values.length + 1));
    values.push(updates.time_end);
  }

  if (setClauses.length > 0) {
    values.push(partId);
    const query = `UPDATE parts SET ${setClauses.join(', ')} WHERE id = $${values.length}`;
    await sql.unsafe(query, values as never[]);
  }
}

/**
 * Update message status and related fields during streaming.
 */
export async function updateMessageStatus(
  messageId: string,
  updates: {
    status?: MessageStatus;
    thinking_text?: string;
    error_message?: string;
    time_completed?: number;
    finish?: string;
    error?: Record<string, unknown>;
    cost?: number;
    tokens_input?: number;
    tokens_output?: number;
    tokens_reasoning?: number;
    tokens_cache_read?: number;
    tokens_cache_write?: number;
  }
): Promise<void> {
  await sql`
    UPDATE messages SET
      status = COALESCE(${updates.status ?? null}, status),
      thinking_text = COALESCE(${updates.thinking_text ?? null}, thinking_text),
      error_message = COALESCE(${updates.error_message ?? null}, error_message),
      time_completed = COALESCE(${updates.time_completed ?? null}, time_completed),
      finish = COALESCE(${updates.finish ?? null}, finish),
      error = COALESCE(${updates.error ? JSON.stringify(updates.error) : null}, error),
      cost = COALESCE(${updates.cost ?? null}, cost),
      tokens_input = COALESCE(${updates.tokens_input ?? null}, tokens_input),
      tokens_output = COALESCE(${updates.tokens_output ?? null}, tokens_output),
      tokens_reasoning = COALESCE(${updates.tokens_reasoning ?? null}, tokens_reasoning),
      tokens_cache_read = COALESCE(${updates.tokens_cache_read ?? null}, tokens_cache_read),
      tokens_cache_write = COALESCE(${updates.tokens_cache_write ?? null}, tokens_cache_write)
    WHERE id = ${messageId}
  `;
}

// =============================================================================
// Cleanup Operations
// =============================================================================

export async function clearSessionState(sessionId: string): Promise<void> {
  // Foreign key cascades will handle parts, messages, snapshot_history, subtasks, file_trackers
  await sql`DELETE FROM sessions WHERE id = ${sessionId}`;
}