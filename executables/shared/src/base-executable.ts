import { 
  RequestSchema, 
  Logger, 
  toExecutableError,
  InvalidRequestError,
  TimeoutError,
  type Request,
  type Response 
} from './index';

export type ActionHandler = (params: Record<string, unknown>) => Promise<Record<string, unknown>>;
export type ActionHandlers = Record<string, ActionHandler>;

export interface ExecutableOptions {
  name: string;
  handlers: ActionHandlers;
  defaultTimeout?: number;
  logLevel?: import('./logger').LogLevel;
}

export class BaseExecutable {
  private readonly name: string;
  private readonly handlers: ActionHandlers;
  private readonly defaultTimeout: number;

  constructor(options: ExecutableOptions) {
    this.name = options.name;
    this.handlers = options.handlers;
    this.defaultTimeout = options.defaultTimeout ?? 30000;
    
    if (options.logLevel !== undefined) {
      Logger.setLevel(options.logLevel);
    }
  }

  async handleRequest(request: unknown): Promise<Response> {
    try {
      // Validate request
      const validation = RequestSchema.safeParse(request);
      if (!validation.success) {
        throw new InvalidRequestError(validation.error.errors.map(e => `${e.path.join('.')}: ${e.message}`).join(', '));
      }

      const { action, params, timeout = this.defaultTimeout } = validation.data;
      
      // Set correlation ID for this request
      const correlationId = `${Date.now()}-${Math.random().toString(36).substring(7)}`;
      Logger.setCorrelationId(correlationId);
      
      Logger.info(`Handling action: ${action}`);

      // Check if handler exists
      const handler = this.handlers[action];
      if (!handler) {
        throw new import('./error').UnknownActionError(action);
      }

      // Execute with timeout
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new TimeoutError(timeout)), timeout);
      });

      const result = await Promise.race([
        handler(params),
        timeoutPromise
      ]);

      Logger.info(`Action completed successfully: ${action}`);
      
      return {
        success: true,
        data: result,
      };
    } catch (error) {
      const executableError = toExecutableError(error);
      Logger.error(`Action failed: ${executableError.code}`, executableError.message);
      return executableError.toResponse();
    }
  }

  async run() {
    // Setup signal handlers for graceful shutdown
    process.on('SIGTERM', () => {
      Logger.info('Received SIGTERM, shutting down gracefully');
      process.exit(0);
    });

    process.on('SIGINT', () => {
      Logger.info('Received SIGINT, shutting down gracefully');
      process.exit(0);
    });

    try {
      Logger.info(`${this.name} starting up`);
      
      // Read from stdin
      const input = await Bun.stdin.text();
      
      if (!input || input.trim() === '') {
        throw new InvalidRequestError('No input received from stdin');
      }

      Logger.debug('Received input', { length: input.length });

      // Parse JSON
      let request: unknown;
      try {
        request = JSON.parse(input);
      } catch (e) {
        throw new InvalidRequestError('Failed to parse JSON input');
      }

      // Handle request
      const response = await this.handleRequest(request);
      
      // Write response to stdout
      process.stdout.write(JSON.stringify(response));
      
      // Exit successfully
      process.exit(0);
    } catch (error) {
      // Catastrophic error - log and exit with error response
      const executableError = toExecutableError(error);
      Logger.fatal(`Fatal error: ${executableError.code}`, executableError.message);
      
      process.stdout.write(JSON.stringify(executableError.toResponse()));
      process.exit(1);
    }
  }
}