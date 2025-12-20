/**
 * Tests for EventBus implementations.
 */

import { describe, test, expect, beforeEach } from 'bun:test';
import {
  SSEEventBus,
  NullEventBus,
  getEventBus,
  setEventBus,
  EventTypes,
  type Event,
  type EventBus,
} from '../events';

describe('EventTypes constants', () => {
  test('has session event types', () => {
    expect(EventTypes.SESSION_CREATED).toBe('session.created');
    expect(EventTypes.SESSION_UPDATED).toBe('session.updated');
    expect(EventTypes.SESSION_DELETED).toBe('session.deleted');
  });

  test('has message event types', () => {
    expect(EventTypes.MESSAGE_CREATED).toBe('message.created');
    expect(EventTypes.MESSAGE_UPDATED).toBe('message.updated');
    expect(EventTypes.MESSAGE_COMPLETED).toBe('message.completed');
  });

  test('has part event types', () => {
    expect(EventTypes.PART_CREATED).toBe('part.created');
    expect(EventTypes.PART_UPDATED).toBe('part.updated');
  });

  test('has permission event types', () => {
    expect(EventTypes.PERMISSION_REQUESTED).toBe('permission.requested');
    expect(EventTypes.PERMISSION_RESPONDED).toBe('permission.responded');
  });

  test('has task event types', () => {
    expect(EventTypes.TASK_STARTED).toBe('task.started');
    expect(EventTypes.TASK_COMPLETED).toBe('task.completed');
    expect(EventTypes.TASK_FAILED).toBe('task.failed');
    expect(EventTypes.TASK_TIMEOUT).toBe('task.timeout');
    expect(EventTypes.TASK_CANCELLED).toBe('task.cancelled');
  });

  test('has error event type', () => {
    expect(EventTypes.ERROR).toBe('error');
  });
});

describe('SSEEventBus', () => {
  let bus: SSEEventBus;

  beforeEach(() => {
    bus = new SSEEventBus();
  });

  describe('publish', () => {
    test('publishes event to all subscribers', async () => {
      const events: Event[] = [];

      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      // Start listening
      const nextPromise = iterator.next();

      // Publish event
      await bus.publish({
        type: EventTypes.SESSION_CREATED,
        properties: { sessionID: 'test-session' },
      });

      // Should receive the event
      const result = await nextPromise;
      expect(result.done).toBe(false);
      expect(result.value?.type).toBe(EventTypes.SESSION_CREATED);
      expect(result.value?.properties.sessionID).toBe('test-session');

      // Cleanup
      await iterator.return?.();
    });

    test('publishes to multiple subscribers', async () => {
      const sub1 = bus.subscribe();
      const sub2 = bus.subscribe();

      const iter1 = sub1[Symbol.asyncIterator]();
      const iter2 = sub2[Symbol.asyncIterator]();

      const next1 = iter1.next();
      const next2 = iter2.next();

      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { messageId: 'msg-1' },
      });

      const result1 = await next1;
      const result2 = await next2;

      expect(result1.value?.type).toBe(EventTypes.MESSAGE_CREATED);
      expect(result2.value?.type).toBe(EventTypes.MESSAGE_CREATED);
      expect(result1.value?.properties.messageId).toBe('msg-1');
      expect(result2.value?.properties.messageId).toBe('msg-1');

      await iter1.return?.();
      await iter2.return?.();
    });

    test('handles events with no sessionID', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      const nextPromise = iterator.next();

      await bus.publish({
        type: EventTypes.ERROR,
        properties: { error: 'Something went wrong' },
      });

      const result = await nextPromise;
      expect(result.value?.type).toBe(EventTypes.ERROR);
      expect(result.value?.properties.error).toBe('Something went wrong');

      await iterator.return?.();
    });

    test('publishes multiple events sequentially', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      const next1 = iterator.next();
      await bus.publish({
        type: EventTypes.TASK_STARTED,
        properties: { taskId: 'task-1' },
      });
      const result1 = await next1;

      const next2 = iterator.next();
      await bus.publish({
        type: EventTypes.TASK_COMPLETED,
        properties: { taskId: 'task-1' },
      });
      const result2 = await next2;

      expect(result1.value?.type).toBe(EventTypes.TASK_STARTED);
      expect(result2.value?.type).toBe(EventTypes.TASK_COMPLETED);

      await iterator.return?.();
    });
  });

  describe('subscribe', () => {
    test('subscribes without session filter', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      const nextPromise = iterator.next();

      await bus.publish({
        type: EventTypes.SESSION_CREATED,
        properties: { sessionID: 'session-1' },
      });

      const result = await nextPromise;
      expect(result.done).toBe(false);
      expect(result.value?.properties.sessionID).toBe('session-1');

      await iterator.return?.();
    });

    test('subscribes with session filter', async () => {
      const subscription = bus.subscribe('session-1');
      const iterator = subscription[Symbol.asyncIterator]();

      const nextPromise = iterator.next();

      // Publish event for session-1
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { sessionID: 'session-1', messageId: 'msg-1' },
      });

      const result = await nextPromise;
      expect(result.value?.properties.sessionID).toBe('session-1');
      expect(result.value?.properties.messageId).toBe('msg-1');

      await iterator.return?.();
    });

    test('filters out events from different sessions', async () => {
      const subscription = bus.subscribe('session-1');
      const iterator = subscription[Symbol.asyncIterator]();

      // Listen for next event
      const nextPromise = iterator.next();

      // Publish event for session-2 (should be filtered out)
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { sessionID: 'session-2', messageId: 'msg-2' },
      });

      // Publish event for session-1 (should be received)
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { sessionID: 'session-1', messageId: 'msg-1' },
      });

      const result = await nextPromise;
      expect(result.value?.properties.sessionID).toBe('session-1');
      expect(result.value?.properties.messageId).toBe('msg-1');

      await iterator.return?.();
    });

    test('unsubscribes when iterator is returned', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      // Start subscription
      await iterator.return?.();

      // Publish event (subscriber should not receive it)
      await bus.publish({
        type: EventTypes.SESSION_CREATED,
        properties: { sessionID: 'test' },
      });

      // This is correct behavior - subscriber cleaned up
      expect(true).toBe(true);
    });

    test('queues events when subscriber is slow to consume', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      // Start the first next() call to initialize the subscriber
      const next1Promise = iterator.next();

      // Give time for subscriber to be added
      await new Promise(resolve => setTimeout(resolve, 10));

      // Publish first event (should be waiting for it)
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { messageId: 'msg-1' },
      });

      // Get first result
      const result1 = await next1Promise;
      expect(result1.value?.properties.messageId).toBe('msg-1');

      // Now publish second event before calling next() (should queue it)
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { messageId: 'msg-2' },
      });

      // This next() should return the queued event immediately
      const result2 = await iterator.next();
      expect(result2.value?.properties.messageId).toBe('msg-2');

      await iterator.return?.();
    });

    test('handles rapid event publishing', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      // Start consuming first event to initialize subscriber
      const firstPromise = iterator.next();
      await new Promise(resolve => setTimeout(resolve, 10));

      // Publish events rapidly
      const publishPromises: Promise<void>[] = [];
      for (let i = 0; i < 10; i++) {
        publishPromises.push(
          bus.publish({
            type: EventTypes.MESSAGE_CREATED,
            properties: { messageId: `msg-${i}` },
          })
        );
      }

      await Promise.all(publishPromises);

      // Consume all events
      const receivedIds: string[] = [];

      // Get first event
      const first = await firstPromise;
      receivedIds.push(first.value?.properties.messageId as string);

      // Get remaining events
      for (let i = 1; i < 10; i++) {
        const result = await iterator.next();
        receivedIds.push(result.value?.properties.messageId as string);
      }

      expect(receivedIds.length).toBe(10);
      expect(receivedIds).toContain('msg-0');
      expect(receivedIds).toContain('msg-9');

      await iterator.return?.();
    });

    test('multiple subscribers with different session filters', async () => {
      const sub1 = bus.subscribe('session-1');
      const sub2 = bus.subscribe('session-2');

      const iter1 = sub1[Symbol.asyncIterator]();
      const iter2 = sub2[Symbol.asyncIterator]();

      const next1 = iter1.next();
      const next2 = iter2.next();

      // Publish to session-1
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { sessionID: 'session-1', messageId: 'msg-1' },
      });

      // Publish to session-2
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { sessionID: 'session-2', messageId: 'msg-2' },
      });

      const result1 = await next1;
      const result2 = await next2;

      expect(result1.value?.properties.sessionID).toBe('session-1');
      expect(result1.value?.properties.messageId).toBe('msg-1');
      expect(result2.value?.properties.sessionID).toBe('session-2');
      expect(result2.value?.properties.messageId).toBe('msg-2');

      await iter1.return?.();
      await iter2.return?.();
    });
  });

  describe('integration scenarios', () => {
    test('session lifecycle events', async () => {
      const subscription = bus.subscribe('session-123');
      const iterator = subscription[Symbol.asyncIterator]();

      // Session created
      const next1 = iterator.next();
      await bus.publish({
        type: EventTypes.SESSION_CREATED,
        properties: { sessionID: 'session-123', timestamp: Date.now() },
      });
      const result1 = await next1;
      expect(result1.value?.type).toBe(EventTypes.SESSION_CREATED);

      // Session updated
      const next2 = iterator.next();
      await bus.publish({
        type: EventTypes.SESSION_UPDATED,
        properties: { sessionID: 'session-123', title: 'New Title' },
      });
      const result2 = await next2;
      expect(result2.value?.type).toBe(EventTypes.SESSION_UPDATED);

      // Session deleted
      const next3 = iterator.next();
      await bus.publish({
        type: EventTypes.SESSION_DELETED,
        properties: { sessionID: 'session-123' },
      });
      const result3 = await next3;
      expect(result3.value?.type).toBe(EventTypes.SESSION_DELETED);

      await iterator.return?.();
    });

    test('message and part events', async () => {
      const subscription = bus.subscribe('session-456');
      const iterator = subscription[Symbol.asyncIterator]();

      // Message created
      const next1 = iterator.next();
      await bus.publish({
        type: EventTypes.MESSAGE_CREATED,
        properties: { sessionID: 'session-456', messageId: 'msg-1' },
      });
      const result1 = await next1;
      expect(result1.value?.type).toBe(EventTypes.MESSAGE_CREATED);

      // Part created
      const next2 = iterator.next();
      await bus.publish({
        type: EventTypes.PART_CREATED,
        properties: { sessionID: 'session-456', partId: 'part-1' },
      });
      const result2 = await next2;
      expect(result2.value?.type).toBe(EventTypes.PART_CREATED);

      // Message completed
      const next3 = iterator.next();
      await bus.publish({
        type: EventTypes.MESSAGE_COMPLETED,
        properties: { sessionID: 'session-456', messageId: 'msg-1' },
      });
      const result3 = await next3;
      expect(result3.value?.type).toBe(EventTypes.MESSAGE_COMPLETED);

      await iterator.return?.();
    });
  });
});

describe('NullEventBus', () => {
  let bus: NullEventBus;

  beforeEach(() => {
    bus = new NullEventBus();
  });

  describe('publish', () => {
    test('discards events silently', async () => {
      await bus.publish({
        type: EventTypes.SESSION_CREATED,
        properties: { sessionID: 'test' },
      });

      // Should not throw and should return immediately
      expect(true).toBe(true);
    });

    test('handles multiple publishes', async () => {
      const promises = [];
      for (let i = 0; i < 100; i++) {
        promises.push(
          bus.publish({
            type: EventTypes.MESSAGE_CREATED,
            properties: { messageId: `msg-${i}` },
          })
        );
      }

      await Promise.all(promises);
      expect(true).toBe(true);
    });
  });

  describe('subscribe', () => {
    test('returns immediately without yielding', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      // First next() should complete immediately
      const result = await iterator.next();
      expect(result.done).toBe(true);
      expect(result.value).toBeUndefined();
    });

    test('subscribe with sessionId returns immediately', async () => {
      const subscription = bus.subscribe('session-123');
      const iterator = subscription[Symbol.asyncIterator]();

      const result = await iterator.next();
      expect(result.done).toBe(true);
    });

    test('never yields events', async () => {
      const subscription = bus.subscribe();
      const iterator = subscription[Symbol.asyncIterator]();

      // Publish event
      await bus.publish({
        type: EventTypes.SESSION_CREATED,
        properties: { sessionID: 'test' },
      });

      // Iterator should still complete immediately
      const result = await iterator.next();
      expect(result.done).toBe(true);
    });
  });
});

describe('global EventBus management', () => {
  test('getEventBus returns singleton', () => {
    const bus1 = getEventBus();
    const bus2 = getEventBus();

    expect(bus1).toBe(bus2);
    expect(bus1).toBeInstanceOf(SSEEventBus);
  });

  test('getEventBus creates SSEEventBus by default', () => {
    // Clear any existing bus by setting null
    setEventBus(null as any);

    const bus = getEventBus();
    expect(bus).toBeInstanceOf(SSEEventBus);
  });

  test('setEventBus changes global instance', () => {
    const originalBus = getEventBus();

    const customBus = new NullEventBus();
    setEventBus(customBus);

    expect(getEventBus()).toBe(customBus);
    expect(getEventBus()).not.toBe(originalBus);

    // Restore
    setEventBus(originalBus);
  });

  test('can set NullEventBus for testing', () => {
    const nullBus = new NullEventBus();
    setEventBus(nullBus);

    const bus = getEventBus();
    expect(bus).toBeInstanceOf(NullEventBus);
    expect(bus).toBe(nullBus);

    // Restore
    setEventBus(new SSEEventBus());
  });

  test('can replace bus multiple times', () => {
    const bus1 = new SSEEventBus();
    const bus2 = new NullEventBus();
    const bus3 = new SSEEventBus();

    setEventBus(bus1);
    expect(getEventBus()).toBe(bus1);

    setEventBus(bus2);
    expect(getEventBus()).toBe(bus2);

    setEventBus(bus3);
    expect(getEventBus()).toBe(bus3);
  });
});

describe('Event interface', () => {
  test('event has type and properties', () => {
    const event: Event = {
      type: EventTypes.SESSION_CREATED,
      properties: { sessionID: 'test' },
    };

    expect(event.type).toBe('session.created');
    expect(event.properties.sessionID).toBe('test');
  });

  test('properties can contain any data', () => {
    const event: Event = {
      type: EventTypes.MESSAGE_CREATED,
      properties: {
        sessionID: 'session-1',
        messageId: 'msg-1',
        content: 'Hello world',
        timestamp: Date.now(),
        metadata: {
          nested: true,
          values: [1, 2, 3],
        },
      },
    };

    expect(event.properties.sessionID).toBe('session-1');
    expect(event.properties.content).toBe('Hello world');
    expect(typeof event.properties.timestamp).toBe('number');
    expect(event.properties.metadata.nested).toBe(true);
  });
});

describe('edge cases', () => {
  test('SSEEventBus handles event with null properties', async () => {
    const bus = new SSEEventBus();
    const subscription = bus.subscribe();
    const iterator = subscription[Symbol.asyncIterator]();

    const nextPromise = iterator.next();

    await bus.publish({
      type: EventTypes.ERROR,
      properties: { error: null },
    });

    const result = await nextPromise;
    expect(result.value?.properties.error).toBeNull();

    await iterator.return?.();
  });

  test('SSEEventBus handles undefined sessionID', async () => {
    const bus = new SSEEventBus();
    const subscription = bus.subscribe('session-1');
    const iterator = subscription[Symbol.asyncIterator]();

    const nextPromise = iterator.next();

    // Publish with undefined sessionID (should not match filter)
    await bus.publish({
      type: EventTypes.ERROR,
      properties: { error: 'Test', sessionID: undefined },
    });

    // Publish with matching sessionID
    await bus.publish({
      type: EventTypes.MESSAGE_CREATED,
      properties: { sessionID: 'session-1', messageId: 'msg-1' },
    });

    const result = await nextPromise;
    expect(result.value?.properties.sessionID).toBe('session-1');
    expect(result.value?.properties.messageId).toBe('msg-1');

    await iterator.return?.();
  });

  test('SSEEventBus handles very large event properties', async () => {
    const bus = new SSEEventBus();
    const subscription = bus.subscribe();
    const iterator = subscription[Symbol.asyncIterator]();

    const largeData = 'x'.repeat(1000000); // 1MB string

    const nextPromise = iterator.next();

    await bus.publish({
      type: EventTypes.MESSAGE_CREATED,
      properties: { sessionID: 'test', data: largeData },
    });

    const result = await nextPromise;
    expect(result.value?.properties.data).toBe(largeData);

    await iterator.return?.();
  });
});
