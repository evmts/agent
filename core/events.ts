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
  lastActivity: number;
}

export class SSEEventBus implements EventBus {
  private subscribers = new Set<Subscriber>();
  private cleanupInterval: Timer | null = null;
  private readonly SUBSCRIBER_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes
  private readonly CLEANUP_INTERVAL_MS = 60 * 1000; // 1 minute

  constructor() {
    // Start periodic cleanup of stale subscribers
    this.startCleanupTimer();
  }

  private startCleanupTimer(): void {
    this.cleanupInterval = setInterval(() => {
      const now = Date.now();
      const staleSubscribers: Subscriber[] = [];

      for (const subscriber of this.subscribers) {
        if (now - subscriber.lastActivity > this.SUBSCRIBER_TIMEOUT_MS) {
          staleSubscribers.push(subscriber);
        }
      }

      if (staleSubscribers.length > 0) {
        console.warn(
          `[EventBus] Cleaning up ${staleSubscribers.length} stale subscriber(s) (inactive > ${this.SUBSCRIBER_TIMEOUT_MS / 1000}s)`
        );
        for (const subscriber of staleSubscribers) {
          this.subscribers.delete(subscriber);
        }
      }
    }, this.CLEANUP_INTERVAL_MS);
  }

  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
    this.subscribers.clear();
  }

  async publish(event: Event): Promise<void> {
    const sessionId = event.properties.sessionID as string | undefined;
    const now = Date.now();

    for (const subscriber of this.subscribers) {
      // Send to all subscribers if no session filter, or if session matches
      if (!subscriber.sessionId || subscriber.sessionId === sessionId) {
        subscriber.handler(event);
        subscriber.lastActivity = now; // Update activity timestamp
      }
    }
  }

  async *subscribe(sessionId?: string): AsyncGenerator<Event, void, unknown> {
    const MAX_QUEUE_SIZE = 1000; // Prevent unbounded queue growth
    const queue: Event[] = [];
    let resolveNext: ((event: Event) => void) | null = null;
    let eventsDropped = 0;

    const subscriber: Subscriber = {
      sessionId,
      lastActivity: Date.now(),
      handler: (event: Event) => {
        subscriber.lastActivity = Date.now(); // Update on each event
        if (resolveNext) {
          resolveNext(event);
          resolveNext = null;
        } else {
          // Enforce queue size limit - drop oldest events if queue is full
          if (queue.length >= MAX_QUEUE_SIZE) {
            queue.shift(); // Remove oldest event
            eventsDropped++;
            if (eventsDropped === 1 || eventsDropped % 100 === 0) {
              console.warn(
                `[EventBus] Queue overflow for subscriber (session: ${sessionId ?? 'global'}), ${eventsDropped} events dropped`
              );
            }
          }
          queue.push(event);
        }
      },
    };

    this.subscribers.add(subscriber);

    try {
      while (true) {
        if (queue.length > 0) {
          subscriber.lastActivity = Date.now(); // Update on yield
          yield queue.shift()!;
        } else {
          subscriber.lastActivity = Date.now(); // Update before waiting
          yield await new Promise<Event>((resolve) => {
            resolveNext = resolve;
          });
        }
      }
    } finally {
      this.subscribers.delete(subscriber);
      if (eventsDropped > 0) {
        console.warn(
          `[EventBus] Subscriber cleanup (session: ${sessionId ?? 'global'}), total events dropped: ${eventsDropped}`
        );
      }
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

  // biome-ignore lint/correctness/useYield: NullEventBus intentionally never yields
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
