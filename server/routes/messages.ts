/**
 * Message routes - send messages with SSE streaming.
 */

import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { getSession, getSessionMessages, appendSessionMessage, activeTasks } from '../../core';
import { NotFoundError } from '../../core/exceptions';
import { getServerEventBus } from '../event-bus';
import { persistedStreamAgent } from '../../ai';
import { saveMessage } from '../../db/agent-state';
import type { CoreMessage } from 'ai';
import type { MessageWithParts } from '../../core/state';
import type { UserMessage, AssistantMessage, TextPart } from '../../core/models';
import type { Session } from '../../core/models/session';

const app = new Hono();

// Generate a simple ID
function generateId(prefix: string): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let id = prefix;
  for (let i = 0; i < 12; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

// Send a message with SSE streaming response
app.post('/:sessionId/message', async (c) => {
  const sessionId = c.req.param('sessionId');
  const body = await c.req.json();
  const eventBus = getServerEventBus();

  // Validate session exists
  let session: Session;
  try {
    session = await getSession(sessionId);
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }

  // Extract user message content
  const userText = body.parts?.[0]?.text ?? body.content ?? '';
  if (!userText) {
    return c.json({ error: 'Message content is required' }, 400);
  }

  // Await the session to get its properties
  const sessionData = await session;

  // Create user message
  const now = Date.now();
  const userMessageId = generateId('msg_');
  const userMessage: UserMessage = {
    id: userMessageId,
    sessionID: sessionId,
    role: 'user',
    time: { created: now },
    status: 'completed',
    agent: body.agent ?? 'build',
    model: {
      providerID: 'anthropic',
      modelID: body.model?.modelID ?? sessionData.model ?? 'claude-sonnet-4-20250514',
    },
  };

  // Store user message
  const userMessageWithParts: MessageWithParts = {
    info: userMessage,
    parts: [
      {
        id: generateId('part_'),
        sessionID: sessionId,
        messageID: userMessageId,
        type: 'text',
        text: userText,
      } as TextPart,
    ],
  };
  appendSessionMessage(sessionId, userMessageWithParts);

  // Publish user message event
  await eventBus.publish({
    type: 'message.created',
    properties: {
      sessionID: sessionId,
      message: userMessage,
    },
  });

  // Create assistant message
  const assistantMessageId = generateId('msg_');
  const assistantMessage: AssistantMessage = {
    id: assistantMessageId,
    sessionID: sessionId,
    role: 'assistant',
    time: { created: now },
    status: 'pending',
    parentID: userMessageId,
    modelID: userMessage.model.modelID,
    providerID: userMessage.model.providerID,
    mode: 'default',
    path: { cwd: sessionData.directory, root: sessionData.directory },
    cost: 0,
    tokens: { input: 0, output: 0, reasoning: 0 },
  };

  // Save assistant message to DB with pending status
  await saveMessage(assistantMessage);

  // Load conversation history
  const messageHistory = await getSessionMessages(sessionId);
  // Build CoreMessage array from history (skip the last user message we just added)
  const coreMessages: CoreMessage[] = [];
  for (const msg of messageHistory.slice(0, -1)) {
    const textPart = msg.parts.find((p) => p.type === 'text');
    if (textPart && 'text' in textPart) {
      coreMessages.push({
        role: msg.info.role,
        content: textPart.text,
      });
    }
  }
  // Add the current user message
  coreMessages.push({
    role: 'user',
    content: userText,
  });

  // Create AbortController for this task
  const abortController = new AbortController();
  activeTasks.set(sessionId, abortController);

  // Stream the response
  return streamSSE(c, async (stream) => {
    try {
      // Publish assistant message created event
      await stream.writeSSE({
        event: 'message.created',
        data: JSON.stringify({
          type: 'message.created',
          properties: {
            sessionID: sessionId,
            message: assistantMessage,
          },
        }),
      });

      // Stream agent response with database persistence
      for await (const event of persistedStreamAgent(
        sessionId,
        assistantMessageId,
        coreMessages,
        {
          modelId: userMessage.model.modelID,
          agentName: body.agent ?? 'build',
          workingDir: sessionData.directory,
          abortSignal: abortController.signal,
          sessionId, // For duplicate detection
        }
      )) {
        switch (event.type) {
          case 'text':
            await stream.writeSSE({
              event: 'part.updated',
              data: JSON.stringify({
                type: 'part.updated',
                properties: {
                  sessionID: sessionId,
                  messageID: assistantMessageId,
                  type: 'text',
                  delta: event.data,
                },
              }),
            });
            break;

          case 'reasoning':
            await stream.writeSSE({
              event: 'part.updated',
              data: JSON.stringify({
                type: 'part.updated',
                properties: {
                  sessionID: sessionId,
                  messageID: assistantMessageId,
                  type: 'reasoning',
                  delta: event.data,
                },
              }),
            });
            break;

          case 'tool_call':
            await stream.writeSSE({
              event: 'tool.call',
              data: JSON.stringify({
                type: 'tool.call',
                properties: {
                  sessionID: sessionId,
                  messageID: assistantMessageId,
                  toolId: event.toolId,
                  toolName: event.toolName,
                  input: event.toolInput,
                },
              }),
            });
            break;

          case 'tool_result':
            await stream.writeSSE({
              event: 'tool.result',
              data: JSON.stringify({
                type: 'tool.result',
                properties: {
                  sessionID: sessionId,
                  messageID: assistantMessageId,
                  toolId: event.toolId,
                  toolName: event.toolName,
                  output: event.toolOutput,
                  cached: event.cached,
                },
              }),
            });
            break;

          case 'finish':
            await stream.writeSSE({
              event: 'message.completed',
              data: JSON.stringify({
                type: 'message.completed',
                properties: {
                  sessionID: sessionId,
                  messageID: assistantMessageId,
                  finishReason: event.finishReason,
                },
              }),
            });
            break;
        }
      }
    } catch (error) {
      await stream.writeSSE({
        event: 'error',
        data: JSON.stringify({
          type: 'error',
          properties: {
            sessionID: sessionId,
            error: String(error),
          },
        }),
      });
    } finally {
      // Clean up AbortController
      activeTasks.delete(sessionId);
    }
  });
});

// Abort a running message stream
app.post('/:sessionId/abort', async (c) => {
  const sessionId = c.req.param('sessionId');

  // Check if session has an active task
  const abortController = activeTasks.get(sessionId);
  if (!abortController) {
    return c.json({ error: 'No active task found for this session' }, 404);
  }

  // Abort the task
  abortController.abort();
  activeTasks.delete(sessionId);

  return c.json({ success: true, message: 'Task aborted successfully' });
});

// List messages for a session
app.get('/:sessionId/messages', async (c) => {
  const sessionId = c.req.param('sessionId');
  const limit = parseInt(c.req.query('limit') ?? '50', 10);

  try {
    await getSession(sessionId); // Validate session exists
    const messages = await getSessionMessages(sessionId);
    const limited = messages.slice(-limit);

    return c.json({
      messages: limited.map((m: MessageWithParts) => ({
        ...m.info,
        parts: m.parts,
      })),
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      return c.json({ error: error.message }, 404);
    }
    throw error;
  }
});

export default app;
