/**
 * Event types and EventBus implementation.
 *
 * The EventBus provides pub/sub for domain events.
 * Events are published by core and consumed by the server for SSE streaming.
 */

// =============================================================================
// Event Types
// =============================================================================

export interface Event {
  type: string;
  properties: Record<string, unknown>;
}

/** Event type constants */
export const EventTypes = {
  // Session events
  SESSION_CREATED: 'session.created',
  SESSION_UPDATED: 'session.updated',
  SESSION_DELETED: 'session.deleted',

  // Message events
  MESSAGE_CREATED: 'message.created',
  MESSAGE_UPDATED: 'message.updated',
  MESSAGE_COMPLETED: 'message.completed',

  // Part events
  PART_CREATED: 'part.created',
  PART_UPDATED: 'part.updated',

  // Permission events
  PERMISSION_REQUESTED: 'permission.requested',
  PERMISSION_RESPONDED: 'permission.responded',

  // Task events
  TASK_STARTED: 'task.started',
  TASK_COMPLETED: 'task.completed',
  TASK_FAILED: 'task.failed',
  TASK_TIMEOUT: 'task.timeout',
  TASK_CANCELLED: 'task.cancelled',

  // Error events
  ERROR: 'error',
} as const;

export type EventType = (typeof EventTypes)[keyof typeof EventTypes];

// =============================================================================
// EventBus Interface
// =============================================================================

export interface EventBus {
  publish(event: Event): Promise<void>;
  subscribe(sessionId?: string): AsyncGenerator<Event, void, unknown>;
}

// =============================================================================
// SSE EventBus Implementation
// =============================================================================

interface Subscriber {
  sessionId?: string;
  handler: (event: Event) => void;
}

export class SSEEventBus implements EventBus {
  private subscribers = new Set<Subscriber>();

  async publish(event: Event): Promise<void> {
    const sessionId = event.properties.sessionID as string | undefined;

    for (const subscriber of this.subscribers) {
      // Send to all subscribers if no session filter, or if session matches
      if (!subscriber.sessionId || subscriber.sessionId === sessionId) {
        subscriber.handler(event);
      }
    }
  }

  async *subscribe(sessionId?: string): AsyncGenerator<Event, void, unknown> {
    const queue: Event[] = [];
    let resolveNext: ((event: Event) => void) | null = null;

    const subscriber: Subscriber = {
      sessionId,
      handler: (event: Event) => {
        if (resolveNext) {
          resolveNext(event);
          resolveNext = null;
        } else {
          queue.push(event);
        }
      },
    };

    this.subscribers.add(subscriber);

    try {
      while (true) {
        if (queue.length > 0) {
          yield queue.shift()!;
        } else {
          yield await new Promise<Event>((resolve) => {
            resolveNext = resolve;
          });
        }
      }
    } finally {
      this.subscribers.delete(subscriber);
    }
  }
}

// =============================================================================
// Null EventBus (for testing)
// =============================================================================

export class NullEventBus implements EventBus {
  async publish(_event: Event): Promise<void> {
    // Discard the event
  }

  async *subscribe(_sessionId?: string): AsyncGenerator<Event, void, unknown> {
    // Never yields - immediately returns
    return;
  }
}

// =============================================================================
// Global EventBus Instance
// =============================================================================

let globalEventBus: EventBus | null = null;

export function getEventBus(): EventBus {
  if (!globalEventBus) {
    globalEventBus = new SSEEventBus();
  }
  return globalEventBus;
}

export function setEventBus(bus: EventBus): void {
  globalEventBus = bus;
}
