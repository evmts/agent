/**
 * Tests for core domain exceptions.
 */

import { describe, test, expect } from 'bun:test';
import {
  CoreError,
  NotFoundError,
  InvalidOperationError,
  PermissionDeniedError,
  ValidationError,
  TimeoutError,
} from '../exceptions';

describe('CoreError', () => {
  test('creates error with message', () => {
    const error = new CoreError('Something went wrong');

    expect(error.message).toBe('Something went wrong');
    expect(error.name).toBe('CoreError');
  });

  test('is an instance of Error', () => {
    const error = new CoreError('Test error');

    expect(error instanceof Error).toBe(true);
    expect(error instanceof CoreError).toBe(true);
  });

  test('can be thrown and caught', () => {
    expect(() => {
      throw new CoreError('Test error');
    }).toThrow('Test error');
  });

  test('maintains stack trace', () => {
    const error = new CoreError('Test error');

    expect(error.stack).toBeDefined();
    expect(error.stack).toContain('CoreError');
  });
});

describe('NotFoundError', () => {
  test('creates error with resource and identifier', () => {
    const error = new NotFoundError('Session', 'session-123');

    expect(error.message).toBe('Session not found: session-123');
    expect(error.name).toBe('NotFoundError');
    expect(error.resource).toBe('Session');
    expect(error.identifier).toBe('session-123');
  });

  test('is an instance of CoreError', () => {
    const error = new NotFoundError('User', 'user-456');

    expect(error instanceof Error).toBe(true);
    expect(error instanceof CoreError).toBe(true);
    expect(error instanceof NotFoundError).toBe(true);
  });

  test('works with different resource types', () => {
    const resources = ['Session', 'User', 'Repository', 'Issue', 'Message'];

    resources.forEach((resource) => {
      const error = new NotFoundError(resource, 'id-123');
      expect(error.message).toBe(`${resource} not found: id-123`);
      expect(error.resource).toBe(resource);
    });
  });

  test('works with various identifier formats', () => {
    const identifiers = ['123', 'abc-def', 'user@example.com', '/path/to/file'];

    identifiers.forEach((id) => {
      const error = new NotFoundError('Resource', id);
      expect(error.identifier).toBe(id);
      expect(error.message).toContain(id);
    });
  });

  test('can be caught and properties accessed', () => {
    try {
      throw new NotFoundError('File', '/path/to/missing.txt');
    } catch (e) {
      if (e instanceof NotFoundError) {
        expect(e.resource).toBe('File');
        expect(e.identifier).toBe('/path/to/missing.txt');
      }
    }
  });
});

describe('InvalidOperationError', () => {
  test('creates error with message', () => {
    const error = new InvalidOperationError('Cannot delete active session');

    expect(error.message).toBe('Cannot delete active session');
    expect(error.name).toBe('InvalidOperationError');
  });

  test('is an instance of CoreError', () => {
    const error = new InvalidOperationError('Invalid operation');

    expect(error instanceof Error).toBe(true);
    expect(error instanceof CoreError).toBe(true);
    expect(error instanceof InvalidOperationError).toBe(true);
  });

  test('works with various operation descriptions', () => {
    const operations = [
      'Cannot modify read-only resource',
      'Session already started',
      'Cannot add message to completed conversation',
      'Resource is locked',
    ];

    operations.forEach((op) => {
      const error = new InvalidOperationError(op);
      expect(error.message).toBe(op);
    });
  });

  test('can be thrown and caught', () => {
    expect(() => {
      throw new InvalidOperationError('Invalid state transition');
    }).toThrow('Invalid state transition');
  });
});

describe('PermissionDeniedError', () => {
  test('creates error with operation', () => {
    const error = new PermissionDeniedError('deleteUser');

    expect(error.message).toBe('Permission denied for operation: deleteUser');
    expect(error.name).toBe('PermissionDeniedError');
    expect(error.operation).toBe('deleteUser');
  });

  test('creates error with custom message', () => {
    const error = new PermissionDeniedError(
      'accessRepository',
      'You do not have access to this private repository'
    );

    expect(error.message).toBe('You do not have access to this private repository');
    expect(error.operation).toBe('accessRepository');
  });

  test('is an instance of CoreError', () => {
    const error = new PermissionDeniedError('writeFile');

    expect(error instanceof Error).toBe(true);
    expect(error instanceof CoreError).toBe(true);
    expect(error instanceof PermissionDeniedError).toBe(true);
  });

  test('uses default message when custom message not provided', () => {
    const error = new PermissionDeniedError('modifySettings');

    expect(error.message).toBe('Permission denied for operation: modifySettings');
  });

  test('works with various operations', () => {
    const operations = ['read', 'write', 'delete', 'execute', 'admin'];

    operations.forEach((op) => {
      const error = new PermissionDeniedError(op);
      expect(error.operation).toBe(op);
      expect(error.message).toContain(op);
    });
  });

  test('can be caught and properties accessed', () => {
    try {
      throw new PermissionDeniedError('deleteRepository', 'Only owners can delete repositories');
    } catch (e) {
      if (e instanceof PermissionDeniedError) {
        expect(e.operation).toBe('deleteRepository');
        expect(e.message).toBe('Only owners can delete repositories');
      }
    }
  });
});

describe('ValidationError', () => {
  test('creates error with message', () => {
    const error = new ValidationError('Invalid email format');

    expect(error.message).toBe('Invalid email format');
    expect(error.name).toBe('ValidationError');
    expect(error.field).toBeUndefined();
  });

  test('creates error with field', () => {
    const error = new ValidationError('Must be at least 3 characters', 'username');

    expect(error.message).toBe('Must be at least 3 characters');
    expect(error.field).toBe('username');
  });

  test('is an instance of CoreError', () => {
    const error = new ValidationError('Validation failed');

    expect(error instanceof Error).toBe(true);
    expect(error instanceof CoreError).toBe(true);
    expect(error instanceof ValidationError).toBe(true);
  });

  test('works with various field names', () => {
    const fields = ['email', 'password', 'username', 'bio', 'url'];

    fields.forEach((field) => {
      const error = new ValidationError('Invalid value', field);
      expect(error.field).toBe(field);
    });
  });

  test('field is optional', () => {
    const errorWithField = new ValidationError('Invalid input', 'field1');
    const errorWithoutField = new ValidationError('Invalid input');

    expect(errorWithField.field).toBe('field1');
    expect(errorWithoutField.field).toBeUndefined();
  });

  test('can be caught and properties accessed', () => {
    try {
      throw new ValidationError('Email must be valid', 'email');
    } catch (e) {
      if (e instanceof ValidationError) {
        expect(e.message).toBe('Email must be valid');
        expect(e.field).toBe('email');
      }
    }
  });

  test('works with nested field paths', () => {
    const error = new ValidationError('Invalid nested value', 'user.profile.email');

    expect(error.field).toBe('user.profile.email');
  });
});

describe('TimeoutError', () => {
  test('creates error with operation and timeout', () => {
    const error = new TimeoutError('fetch data', 5000);

    expect(error.message).toBe('Operation timed out after 5000ms: fetch data');
    expect(error.name).toBe('TimeoutError');
    expect(error.timeoutMs).toBe(5000);
  });

  test('is an instance of CoreError', () => {
    const error = new TimeoutError('operation', 1000);

    expect(error instanceof Error).toBe(true);
    expect(error instanceof CoreError).toBe(true);
    expect(error instanceof TimeoutError).toBe(true);
  });

  test('works with various timeout values', () => {
    const timeouts = [100, 1000, 5000, 30000, 60000];

    timeouts.forEach((timeout) => {
      const error = new TimeoutError('test operation', timeout);
      expect(error.timeoutMs).toBe(timeout);
      expect(error.message).toContain(`${timeout}ms`);
    });
  });

  test('works with various operations', () => {
    const operations = [
      'database query',
      'API request',
      'file read',
      'agent response',
      'tool execution',
    ];

    operations.forEach((op) => {
      const error = new TimeoutError(op, 3000);
      expect(error.message).toContain(op);
    });
  });

  test('can be caught and properties accessed', () => {
    try {
      throw new TimeoutError('execute command', 10000);
    } catch (e) {
      if (e instanceof TimeoutError) {
        expect(e.timeoutMs).toBe(10000);
        expect(e.message).toContain('execute command');
        expect(e.message).toContain('10000ms');
      }
    }
  });

  test('formats message correctly', () => {
    const error = new TimeoutError('complex operation name', 2500);

    expect(error.message).toBe('Operation timed out after 2500ms: complex operation name');
  });
});

describe('Error inheritance hierarchy', () => {
  test('all errors inherit from CoreError', () => {
    const errors = [
      new NotFoundError('Resource', 'id'),
      new InvalidOperationError('Invalid'),
      new PermissionDeniedError('operation'),
      new ValidationError('Invalid'),
      new TimeoutError('operation', 1000),
    ];

    errors.forEach((error) => {
      expect(error instanceof CoreError).toBe(true);
      expect(error instanceof Error).toBe(true);
    });
  });

  test('errors maintain correct name property', () => {
    const errors = [
      { error: new CoreError('test'), name: 'CoreError' },
      { error: new NotFoundError('Resource', 'id'), name: 'NotFoundError' },
      { error: new InvalidOperationError('test'), name: 'InvalidOperationError' },
      { error: new PermissionDeniedError('op'), name: 'PermissionDeniedError' },
      { error: new ValidationError('test'), name: 'ValidationError' },
      { error: new TimeoutError('op', 1000), name: 'TimeoutError' },
    ];

    errors.forEach(({ error, name }) => {
      expect(error.name).toBe(name);
    });
  });

  test('errors can be distinguished by instanceof', () => {
    const notFoundError = new NotFoundError('User', 'user-123');
    const validationError = new ValidationError('Invalid input');

    expect(notFoundError instanceof NotFoundError).toBe(true);
    expect(notFoundError instanceof ValidationError).toBe(false);

    expect(validationError instanceof ValidationError).toBe(true);
    expect(validationError instanceof NotFoundError).toBe(false);
  });

  test('errors can be caught selectively', () => {
    const throwNotFound = () => {
      throw new NotFoundError('Session', 'session-123');
    };

    try {
      throwNotFound();
    } catch (e) {
      if (e instanceof NotFoundError) {
        expect(e.resource).toBe('Session');
        expect(e.identifier).toBe('session-123');
      } else {
        // Should not reach here
        expect(false).toBe(true);
      }
    }
  });
});

describe('Error usage patterns', () => {
  test('errors work with try-catch', () => {
    expect(() => {
      try {
        throw new NotFoundError('User', 'user-999');
      } catch (e) {
        if (e instanceof NotFoundError) {
          throw new ValidationError('User does not exist', 'userId');
        }
      }
    }).toThrow(ValidationError);
  });

  test('errors can be re-thrown', () => {
    const originalError = new InvalidOperationError('Cannot proceed');

    expect(() => {
      try {
        throw originalError;
      } catch (e) {
        throw e;
      }
    }).toThrow(InvalidOperationError);
  });

  test('error messages are accessible', () => {
    const errors = [
      new CoreError('Core error message'),
      new NotFoundError('User', 'user-123'),
      new ValidationError('Validation failed', 'field'),
    ];

    errors.forEach((error) => {
      expect(error.message).toBeTruthy();
      expect(typeof error.message).toBe('string');
    });
  });
});
