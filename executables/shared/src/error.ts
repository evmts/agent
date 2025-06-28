import type { ErrorResponse } from './protocol';

export abstract class ExecutableError extends Error {
  constructor(public code: string, message: string) {
    super(message);
    this.name = this.constructor.name;
    
    // Maintains proper stack trace for where our error was thrown (only available on V8)
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }

  toResponse(): ErrorResponse {
    return {
      success: false,
      error: {
        code: this.code,
        message: this.message,
      },
    };
  }
}

export class InvalidRequestError extends ExecutableError {
  constructor(message: string = 'Invalid request format') {
    super('INVALID_REQUEST', message);
  }
}

export class UnknownActionError extends ExecutableError {
  constructor(action: string) {
    super('UNKNOWN_ACTION', `Action '${action}' is not recognized`);
  }
}

export class TimeoutError extends ExecutableError {
  constructor(timeout: number) {
    super('TIMEOUT', `Operation timed out after ${timeout}ms`);
  }
}

export class ValidationError extends ExecutableError {
  constructor(message: string) {
    super('VALIDATION_ERROR', message);
  }
}

export class InternalError extends ExecutableError {
  constructor(message: string) {
    super('INTERNAL_ERROR', message);
  }
}

export class NotImplementedError extends ExecutableError {
  constructor(feature: string) {
    super('NOT_IMPLEMENTED', `Feature '${feature}' is not implemented yet`);
  }
}

// Helper to convert any error to ExecutableError
export function toExecutableError(error: unknown): ExecutableError {
  if (error instanceof ExecutableError) {
    return error;
  }
  
  if (error instanceof Error) {
    return new InternalError(error.message);
  }
  
  return new InternalError('An unknown error occurred');
}