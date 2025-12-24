/**
 * Tests for structured JSON logging in Edge Worker
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Logger } from './logger';

describe('Logger', () => {
  let mockRequest: Request;
  let consoleSpy: any;

  beforeEach(() => {
    // Create a mock request
    mockRequest = new Request('https://plue.dev/test/path', {
      method: 'GET',
      headers: {
        'CF-Connecting-IP': '1.2.3.4',
      },
    });

    // Spy on console methods
    consoleSpy = {
      info: vi.spyOn(console, 'info').mockImplementation(() => {}),
      warn: vi.spyOn(console, 'warn').mockImplementation(() => {}),
      error: vi.spyOn(console, 'error').mockImplementation(() => {}),
      debug: vi.spyOn(console, 'debug').mockImplementation(() => {}),
    };
  });

  it('should generate a request ID if not provided', () => {
    const logger = new Logger(mockRequest);
    const requestId = logger.getRequestId();

    expect(requestId).toBeDefined();
    expect(requestId.length).toBeGreaterThan(0);
  });

  it('should use existing X-Request-ID if present', () => {
    const existingRequestId = 'existing-req-123';
    const requestWithId = new Request('https://plue.dev/test', {
      headers: {
        'X-Request-ID': existingRequestId,
      },
    });

    const logger = new Logger(requestWithId);
    expect(logger.getRequestId()).toBe(existingRequestId);
  });

  it('should output structured JSON logs', () => {
    const logger = new Logger(mockRequest);
    logger.info('Test message', { userId: 'user123' });

    expect(consoleSpy.info).toHaveBeenCalled();
    const logOutput = consoleSpy.info.mock.calls[0][0];
    const logEntry = JSON.parse(logOutput);

    expect(logEntry).toMatchObject({
      level: 'info',
      message: 'Test message',
      context: expect.objectContaining({
        requestId: expect.any(String),
        clientIP: '1.2.3.4',
        path: '/test/path',
        method: 'GET',
        userId: 'user123',
      }),
    });
    expect(logEntry.timestamp).toBeDefined();
    expect(logEntry.duration_ms).toBeGreaterThanOrEqual(0);
  });

  it('should track request duration', async () => {
    const logger = new Logger(mockRequest);

    // Wait a bit
    await new Promise(resolve => setTimeout(resolve, 10));

    const duration = logger.getDuration();
    expect(duration).toBeGreaterThanOrEqual(10);
  });

  it('should set user address', () => {
    const logger = new Logger(mockRequest);
    logger.setUserAddress('0x1234567890abcdef');
    logger.info('Test with user');

    const logOutput = consoleSpy.info.mock.calls[0][0];
    const logEntry = JSON.parse(logOutput);

    expect(logEntry.context.userAddress).toBe('0x1234567890abcdef');
  });

  it('should log errors with stack traces', () => {
    const logger = new Logger(mockRequest);
    const error = new Error('Something went wrong');
    logger.error('Error occurred', error);

    expect(consoleSpy.error).toHaveBeenCalled();
    const logOutput = consoleSpy.error.mock.calls[0][0];
    const logEntry = JSON.parse(logOutput);

    expect(logEntry.level).toBe('error');
    expect(logEntry.message).toBe('Error occurred');
    expect(logEntry.context.error).toBe('Something went wrong');
    expect(logEntry.context.stack).toContain('Error: Something went wrong');
  });

  it('should add custom context', () => {
    const logger = new Logger(mockRequest);
    logger.addContext('customField', 'customValue');
    logger.info('Test');

    const logOutput = consoleSpy.info.mock.calls[0][0];
    const logEntry = JSON.parse(logOutput);

    expect(logEntry.context.customField).toBe('customValue');
  });
});
