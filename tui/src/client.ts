/**
 * API client for the Plue backend server.
 */

export interface Session {
  id: string;
  title?: string;
  directory: string;
  model?: string;
  status: string;
  time: {
    created: number;
    updated?: number;
  };
}

export interface Message {
  id: string;
  sessionID: string;
  role: 'user' | 'assistant';
  time: { created: number; completed?: number };
  parts: Array<{
    id: string;
    type: string;
    text?: string;
  }>;
}

export interface StreamEvent {
  type: string;
  properties: Record<string, any>;
}

export class PlueClient {
  private baseUrl: string;
  private timeout: number;

  constructor(baseUrl: string = 'http://localhost:4000', timeout: number = 30000) {
    this.baseUrl = baseUrl;
    this.timeout = timeout;
  }

  /**
   * Fetch with timeout support
   */
  private async fetchWithTimeout(
    url: string,
    options?: RequestInit
  ): Promise<Response> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);

    try {
      const res = await fetch(url, {
        ...options,
        signal: controller.signal,
      });
      return res;
    } catch (err: any) {
      if (err.name === 'AbortError') {
        throw new Error(`Request timeout after ${this.timeout}ms`);
      }
      throw err;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  /**
   * Check if server is reachable
   */
  async healthCheck(): Promise<boolean> {
    try {
      const res = await this.fetchWithTimeout(`${this.baseUrl}/health`);
      return res.ok;
    } catch {
      return false;
    }
  }

  /**
   * Create a new session
   */
  async createSession(options?: {
    directory?: string;
    title?: string;
    model?: string;
  }): Promise<Session> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/sessions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        directory: options?.directory ?? process.cwd(),
        title: options?.title,
        model: options?.model,
      }),
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to create session');
    }

    const data = await res.json();
    return data.session;
  }

  /**
   * List all sessions
   */
  async listSessions(): Promise<Session[]> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/sessions`);

    if (!res.ok) {
      throw new Error('Failed to list sessions');
    }

    const data = await res.json();
    // Handle both array and object responses
    if (Array.isArray(data.sessions)) {
      return data.sessions;
    }
    // Convert object to array if needed
    return Object.values(data.sessions || {});
  }

  /**
   * Get a session by ID
   */
  async getSession(sessionId: string): Promise<Session> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/sessions/${sessionId}`);

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to get session');
    }

    const data = await res.json();
    return data.session;
  }

  /**
   * Get messages for a session
   */
  async getMessages(sessionId: string, limit: number = 50): Promise<Message[]> {
    const res = await this.fetchWithTimeout(
      `${this.baseUrl}/session/${sessionId}/messages?limit=${limit}`
    );

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to get messages');
    }

    const data = await res.json();
    return data.messages || [];
  }

  /**
   * Send a message and stream the response
   */
  async *sendMessage(
    sessionId: string,
    content: string,
    options?: { model?: string }
  ): AsyncGenerator<StreamEvent> {
    const res = await fetch(`${this.baseUrl}/session/${sessionId}/message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content,
        model: options?.model ? { modelID: options.model } : undefined,
      }),
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to send message');
    }

    if (!res.body) {
      throw new Error('No response body');
    }

    // Parse SSE stream
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (line.startsWith('data:')) {
          const data = line.slice(5).trim();
          if (data) {
            try {
              const event = JSON.parse(data) as StreamEvent;
              yield event;
            } catch {
              // Ignore parse errors
            }
          }
        }
      }
    }

    // Process remaining buffer
    if (buffer.startsWith('data:')) {
      const data = buffer.slice(5).trim();
      if (data) {
        try {
          const event = JSON.parse(data) as StreamEvent;
          yield event;
        } catch {
          // Ignore parse errors
        }
      }
    }
  }

  /**
   * Abort a session's active task
   */
  async abortSession(sessionId: string): Promise<void> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/sessions/${sessionId}/abort`, {
      method: 'POST',
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to abort session');
    }
  }

  /**
   * Delete a session
   */
  async deleteSession(sessionId: string): Promise<void> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/sessions/${sessionId}`, {
      method: 'DELETE',
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to delete session');
    }
  }

  /**
   * Get session diff
   */
  async getSessionDiff(sessionId: string): Promise<any[]> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/sessions/${sessionId}/diff`);

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Failed to get diff');
    }

    const data = await res.json();
    return data.diffs || [];
  }
}
