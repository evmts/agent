/**
 * Structured logging module with log levels.
 *
 * Provides consistent, structured logging across the application.
 * Supports different log levels and formats output for production vs development.
 */

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  FATAL = 4,
}

const LOG_LEVEL_NAMES: Record<LogLevel, string> = {
  [LogLevel.DEBUG]: 'DEBUG',
  [LogLevel.INFO]: 'INFO',
  [LogLevel.WARN]: 'WARN',
  [LogLevel.ERROR]: 'ERROR',
  [LogLevel.FATAL]: 'FATAL',
};

interface LogContext {
  [key: string]: unknown;
}

interface LogEntry {
  timestamp: string;
  level: string;
  message: string;
  context?: LogContext;
  error?: {
    name: string;
    message: string;
    stack?: string;
  };
}

/**
 * Parse log level from environment variable.
 */
function getLogLevel(): LogLevel {
  const level = process.env.LOG_LEVEL?.toUpperCase();
  switch (level) {
    case 'DEBUG': return LogLevel.DEBUG;
    case 'INFO': return LogLevel.INFO;
    case 'WARN': return LogLevel.WARN;
    case 'ERROR': return LogLevel.ERROR;
    case 'FATAL': return LogLevel.FATAL;
    default:
      // Default to DEBUG in development, INFO in production
      return process.env.NODE_ENV === 'production' ? LogLevel.INFO : LogLevel.DEBUG;
  }
}

const currentLogLevel = getLogLevel();
const isProduction = process.env.NODE_ENV === 'production';

/**
 * Format a log entry for output.
 */
function formatLogEntry(entry: LogEntry): string {
  if (isProduction) {
    // JSON format for production (machine-readable)
    return JSON.stringify(entry);
  }

  // Human-readable format for development
  const { timestamp, level, message, context, error } = entry;
  const time = timestamp.split('T')[1].split('.')[0]; // HH:MM:SS
  let output = `[${time}] ${level.padEnd(5)} ${message}`;

  if (context && Object.keys(context).length > 0) {
    output += ` ${JSON.stringify(context)}`;
  }

  if (error) {
    output += `\n  Error: ${error.name}: ${error.message}`;
    if (error.stack && !isProduction) {
      output += `\n${error.stack.split('\n').slice(1).map(l => `  ${l}`).join('\n')}`;
    }
  }

  return output;
}

/**
 * Write a log entry to the appropriate output.
 */
function writeLog(level: LogLevel, entry: LogEntry): void {
  const formatted = formatLogEntry(entry);

  if (level >= LogLevel.ERROR) {
    console.error(formatted);
  } else if (level === LogLevel.WARN) {
    console.warn(formatted);
  } else {
    console.log(formatted);
  }
}

/**
 * Create a log entry and write it if the level is enabled.
 */
function log(level: LogLevel, message: string, context?: LogContext, error?: Error): void {
  if (level < currentLogLevel) {
    return;
  }

  const entry: LogEntry = {
    timestamp: new Date().toISOString(),
    level: LOG_LEVEL_NAMES[level],
    message,
  };

  if (context && Object.keys(context).length > 0) {
    entry.context = context;
  }

  if (error) {
    entry.error = {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }

  writeLog(level, entry);
}

/**
 * Logger interface for creating scoped loggers.
 */
export interface Logger {
  debug(message: string, context?: LogContext): void;
  info(message: string, context?: LogContext): void;
  warn(message: string, context?: LogContext, error?: Error): void;
  error(message: string, context?: LogContext, error?: Error): void;
  fatal(message: string, context?: LogContext, error?: Error): void;
  child(scope: string): Logger;
}

/**
 * Create a logger with an optional scope prefix.
 */
function createLogger(scope?: string): Logger {
  const prefix = scope ? `[${scope}] ` : '';

  return {
    debug(message: string, context?: LogContext) {
      log(LogLevel.DEBUG, prefix + message, context);
    },
    info(message: string, context?: LogContext) {
      log(LogLevel.INFO, prefix + message, context);
    },
    warn(message: string, context?: LogContext, error?: Error) {
      log(LogLevel.WARN, prefix + message, context, error);
    },
    error(message: string, context?: LogContext, error?: Error) {
      log(LogLevel.ERROR, prefix + message, context, error);
    },
    fatal(message: string, context?: LogContext, error?: Error) {
      log(LogLevel.FATAL, prefix + message, context, error);
    },
    child(childScope: string) {
      return createLogger(scope ? `${scope}:${childScope}` : childScope);
    },
  };
}

// Default logger instance
export const logger = createLogger();

// Named scope loggers for common modules
export const serverLogger = createLogger('server');
export const authLogger = createLogger('auth');
export const dbLogger = createLogger('db');
export const agentLogger = createLogger('agent');
export const snapshotLogger = createLogger('snapshot');
export const ptyLogger = createLogger('pty');

// Export factory function for custom scopes
export { createLogger };

export default logger;
