/**
 * Message routes - send messages with SSE streaming.
 */

import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { getSession, getSessionMessages, appendSessionMessage } from '../../core';
import { NotFoundError } from '../../core/exceptions';
import { getServerEventBus } from '../event-bus';
import { AgentWrapper } from '../../ai';
import type { MessageWithParts } from '../../core/state';
import type { UserMessage, AssistantMessage, TextPart, ToolPart } from '../../core/models';

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
  let session;
  try {
    session = getSession(sessionId);
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
    parentID: userMessageId,
    modelID: userMessage.model.modelID,
    providerID: userMessage.model.providerID,
    mode: 'default',
    path: { cwd: sessionData.directory, root: sessionData.directory },
    cost: 0,
    tokens: { input: 0, output: 0, reasoning: 0 },
  };

  // Create agent wrapper
  const wrapper = new AgentWrapper({
    workingDir: sessionData.directory,
    defaultModel: userMessage.model.modelID,
    defaultAgentName: body.agent ?? 'build',
  });

  // Load conversation history
  const messages = await getSessionMessages(sessionId);
  // Skip the last message (which is the user message we just added)
  for (const msg of messages.slice(0, -1)) {
    if (msg.info.role === 'user') {
      const textPart = msg.parts.find((p) => p.type === 'text');
      if (textPart && 'text' in textPart) {
        wrapper.setHistory([
          ...wrapper.getHistory(),
          { role: 'user', content: textPart.text },
        ]);
      }
    } else if (msg.info.role === 'assistant') {
      const textPart = msg.parts.find((p) => p.type === 'text');
      if (textPart && 'text' in textPart) {
        wrapper.setHistory([
          ...wrapper.getHistory(),
          { role: 'assistant', content: textPart.text },
        ]);
      }
    }
  }

  // Stream the response
  return streamSSE(c, async (stream) => {
    const parts: Array<TextPart | ToolPart> = [];
    let textContent = '';

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

      // Stream agent response
      for await (const event of wrapper.streamAsync(userText)) {
        switch (event.type) {
          case 'text':
            textContent += event.data ?? '';
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

      // Create text part
      if (textContent) {
        parts.push({
          id: generateId('part_'),
          sessionID: sessionId,
          messageID: assistantMessageId,
          type: 'text',
          text: textContent,
        });
      }

      // Update assistant message time
      assistantMessage.time.completed = Date.now();

      // Store assistant message
      const assistantMessageWithParts: MessageWithParts = {
        info: assistantMessage,
        parts,
      };
      appendSessionMessage(sessionId, assistantMessageWithParts);
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
    }
  });
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
