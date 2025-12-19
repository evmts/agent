/**
 * Core domain exceptions.
 *
 * These exceptions are transport-agnostic and should be caught by the server
 * layer to convert into appropriate HTTP responses.
 */

export class CoreError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CoreError';
  }
}

export class NotFoundError extends CoreError {
  resource: string;
  identifier: string;

  constructor(resource: string, identifier: string) {
    super(`${resource} not found: ${identifier}`);
    this.name = 'NotFoundError';
    this.resource = resource;
    this.identifier = identifier;
  }
}

export class InvalidOperationError extends CoreError {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidOperationError';
  }
}

export class PermissionDeniedError extends CoreError {
  operation: string;

  constructor(operation: string, message?: string) {
    super(message ?? `Permission denied for operation: ${operation}`);
    this.name = 'PermissionDeniedError';
    this.operation = operation;
  }
}

export class ValidationError extends CoreError {
  field?: string;

  constructor(message: string, field?: string) {
    super(message);
    this.name = 'ValidationError';
    this.field = field;
  }
}

export class TimeoutError extends CoreError {
  timeoutMs: number;

  constructor(operation: string, timeoutMs: number) {
    super(`Operation timed out after ${timeoutMs}ms: ${operation}`);
    this.name = 'TimeoutError';
    this.timeoutMs = timeoutMs;
  }
}
