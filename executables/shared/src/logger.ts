export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

export class Logger {
  private static level: LogLevel = LogLevel.INFO;
  private static correlationId?: string;

  static setLevel(level: LogLevel) {
    Logger.level = level;
  }

  static setCorrelationId(id: string) {
    Logger.correlationId = id;
  }

  private static formatMessage(level: string, message: string, ...args: unknown[]): string {
    const timestamp = new Date().toISOString();
    const corr = Logger.correlationId ? ` [${Logger.correlationId}]` : '';
    const formattedArgs = args.length > 0 ? ' ' + args.map(arg => 
      typeof arg === 'object' ? JSON.stringify(arg) : String(arg)
    ).join(' ') : '';
    
    return `[${timestamp}] [${level}]${corr} ${message}${formattedArgs}`;
  }

  static debug(message: string, ...args: unknown[]) {
    if (Logger.level <= LogLevel.DEBUG) {
      console.error(Logger.formatMessage('DEBUG', message, ...args));
    }
  }

  static info(message: string, ...args: unknown[]) {
    if (Logger.level <= LogLevel.INFO) {
      console.error(Logger.formatMessage('INFO', message, ...args));
    }
  }

  static warn(message: string, ...args: unknown[]) {
    if (Logger.level <= LogLevel.WARN) {
      console.error(Logger.formatMessage('WARN', message, ...args));
    }
  }

  static error(message: string, ...args: unknown[]) {
    if (Logger.level <= LogLevel.ERROR) {
      console.error(Logger.formatMessage('ERROR', message, ...args));
    }
  }

  static fatal(message: string, ...args: unknown[]) {
    console.error(Logger.formatMessage('FATAL', message, ...args));
  }
}