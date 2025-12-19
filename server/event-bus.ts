/**
 * SSE Event Bus for streaming events to clients.
 */

import type { Event, EventBus } from '../core/events';

interface Subscriber {
  sessionId?: string;
  send: (event: Event) => void;
  close: () => void;
}

/**
 * Server-side SSE EventBus implementation.
 *
 * Manages SSE connections and broadcasts events to subscribers.
 */
export class ServerEventBus implements EventBus {
  private subscribers = new Set<Subscriber>();

  /**
   * Publish an event to all relevant subscribers.
   */
  async publish(event: Event): Promise<void> {
    const sessionId = event.properties.sessionID as string | undefined;

    for (const subscriber of this.subscribers) {
      // Send to all subscribers if no session filter, or if session matches
      if (!subscriber.sessionId || subscriber.sessionId === sessionId) {
        try {
          subscriber.send(event);
        } catch {
          // Remove broken connections
          this.subscribers.delete(subscriber);
        }
      }
    }
  }

  /**
   * Subscribe to events (returns async generator for streaming).
   */
  async *subscribe(sessionId?: string): AsyncGenerator<Event, void, unknown> {
    const queue: Event[] = [];
    let resolveNext: ((event: Event) => void) | null = null;
    let closed = false;

    const subscriber: Subscriber = {
      sessionId,
      send: (event: Event) => {
        if (closed) return;
        if (resolveNext) {
          resolveNext(event);
          resolveNext = null;
        } else {
          queue.push(event);
        }
      },
      close: () => {
        closed = true;
        if (resolveNext) {
          // Resolve with a special "close" event
          resolveNext = null;
        }
      },
    };

    this.subscribers.add(subscriber);

    try {
      while (!closed) {
        if (queue.length > 0) {
          yield queue.shift()!;
        } else {
          const event = await new Promise<Event>((resolve) => {
            resolveNext = resolve;
          });
          if (event) yield event;
        }
      }
    } finally {
      this.subscribers.delete(subscriber);
    }
  }

  /**
   * Add a subscriber with manual send/close callbacks.
   */
  addSubscriber(
    sessionId: string | undefined,
    send: (event: Event) => void,
    close: () => void
  ): () => void {
    const subscriber: Subscriber = { sessionId, send, close };
    this.subscribers.add(subscriber);

    // Return unsubscribe function
    return () => {
      this.subscribers.delete(subscriber);
    };
  }

  /**
   * Get subscriber count.
   */
  getSubscriberCount(): number {
    return this.subscribers.size;
  }
}

// Global event bus instance
let globalEventBus: ServerEventBus | null = null;

export function getServerEventBus(): ServerEventBus {
  if (!globalEventBus) {
    globalEventBus = new ServerEventBus();
  }
  return globalEventBus;
}

export function setServerEventBus(bus: ServerEventBus): void {
  globalEventBus = bus;
}
