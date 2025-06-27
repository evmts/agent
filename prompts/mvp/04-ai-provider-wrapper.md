# Implement AI Provider Wrapper Executable for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on creating the TypeScript/Bun executable that wraps all AI provider SDKs (Anthropic, OpenAI, GitHub Copilot, Bedrock, Google, Azure) into a unified interface for the Zig core.

## Context

<context>
<project_overview>
Plue uses a hybrid architecture where complex JavaScript libraries are wrapped as Bun executables:
- The Zig core spawns these executables and communicates via JSON IPC
- This avoids reimplementing complex protocols and auth flows in Zig
- AI providers have different APIs, authentication methods, and streaming protocols
- The wrapper provides a unified interface regardless of provider
</project_overview>

<architecture_context>
From previous implementation:
- Bun executable structure has been created in executables/
- Shared protocol types and utilities are available
- JSON IPC protocol is defined with request/response format
- Error handling patterns are established
</architecture_context>

<api_specification>
The wrapper must support these providers as defined in PLUE_CORE_API.md:
- Anthropic (API key auth)
- OpenAI (API key auth)  
- GitHub Copilot (OAuth with device flow)
- AWS Bedrock (AWS credentials)
- Google Vertex AI (Service account auth)
- Azure OpenAI (API key + endpoint)

All providers must support:
- Model listing
- Streaming chat completions
- Token counting
- Cost calculation
- Proper error handling
</api_specification>

<reference_implementation>
OpenCode (in opencode/) has provider implementations:
- opencode/packages/opencode/src/provider/provider.ts - Provider abstraction
- opencode/packages/opencode/src/provider/models.ts - Model definitions
- opencode/packages/opencode/src/provider/transform.ts - Message transformation
- opencode/packages/opencode/src/auth/anthropic.ts - Anthropic auth
- opencode/packages/opencode/src/auth/github-copilot.ts - Copilot OAuth
- Provider-specific implementations in src/provider/loaders/
</reference_implementation>
</context>

## Task: Implement AI Provider Wrapper Executable

### Requirements

1. **Create unified provider interface** that abstracts:
   - Authentication methods (API keys, OAuth, AWS creds)
   - Request/response formats
   - Streaming protocols (SSE, custom formats)
   - Error handling patterns
   - Rate limiting and retries

2. **Implement all supported providers**:
   - Anthropic Claude API
   - OpenAI GPT models
   - GitHub Copilot (via API)
   - AWS Bedrock (multiple model families)
   - Google Vertex AI
   - Azure OpenAI

3. **Support standard operations**:
   - List available models
   - Stream chat completions
   - Count tokens (input/output)
   - Calculate costs
   - Handle authentication

4. **Provide robust error handling**:
   - Network errors with retries
   - Authentication failures
   - Rate limiting
   - Timeout handling
   - Partial response recovery

### Detailed Steps

1. **Set up the plue-ai-provider executable structure**:
   ```typescript
   executables/plue-ai-provider/
   ├── src/
   │   ├── index.ts           // Main entry point
   │   ├── types.ts           // Shared types
   │   ├── providers/
   │   │   ├── base.ts        // Base provider interface
   │   │   ├── anthropic.ts   // Anthropic implementation
   │   │   ├── openai.ts      // OpenAI implementation
   │   │   ├── copilot.ts     // GitHub Copilot
   │   │   ├── bedrock.ts     // AWS Bedrock
   │   │   ├── vertex.ts      // Google Vertex AI
   │   │   └── azure.ts       // Azure OpenAI
   │   ├── auth/
   │   │   ├── oauth.ts       // OAuth flow handler
   │   │   └── device-flow.ts // GitHub device flow
   │   ├── streaming/
   │   │   ├── sse.ts         // Server-sent events parser
   │   │   └── transformer.ts // Response transformation
   │   └── utils/
   │       ├── tokenizer.ts   // Token counting
   │       └── retry.ts       // Retry logic
   ├── package.json
   └── tsconfig.json
   ```

2. **Define the unified provider interface**:
   ```typescript
   // types.ts
   export interface ChatMessage {
     role: 'system' | 'user' | 'assistant';
     content: string;
     name?: string;
   }
   
   export interface StreamChunk {
     type: 'content' | 'tool_call' | 'error' | 'done';
     content?: string;
     tool_call?: ToolCall;
     error?: string;
     usage?: Usage;
   }
   
   export interface Model {
     id: string;
     name: string;
     context_length: number;
     max_output: number;
     cost: {
       input: number;  // $ per million tokens
       output: number; // $ per million tokens
     };
   }
   
   // base.ts
   export abstract class BaseProvider {
     abstract listModels(): Promise<Model[]>;
     abstract streamChat(
       messages: ChatMessage[],
       model: string,
       options: ChatOptions
     ): AsyncGenerator<StreamChunk>;
     abstract countTokens(messages: ChatMessage[]): Promise<number>;
   }
   ```

3. **Implement request routing based on action**:
   ```typescript
   // index.ts
   interface Request {
     action: 'list_models' | 'stream_chat' | 'count_tokens' | 'authenticate';
     provider: string;
     params: any;
     timeout?: number;
   }
   
   async function handleRequest(request: Request): Promise<Response> {
     const provider = getProvider(request.provider);
     
     switch (request.action) {
       case 'list_models':
         return { success: true, data: await provider.listModels() };
         
       case 'stream_chat':
         // Special handling for streaming responses
         return streamResponse(provider, request.params);
         
       case 'count_tokens':
         return { 
           success: true, 
           data: await provider.countTokens(request.params.messages) 
         };
         
       case 'authenticate':
         return handleAuth(request.provider, request.params);
         
       default:
         throw new Error(`Unknown action: ${request.action}`);
     }
   }
   ```

4. **Implement Anthropic provider** as example:
   ```typescript
   // providers/anthropic.ts
   import Anthropic from '@anthropic-ai/sdk';
   
   export class AnthropicProvider extends BaseProvider {
     private client: Anthropic;
     
     constructor(apiKey: string) {
       super();
       this.client = new Anthropic({ apiKey });
     }
     
     async listModels(): Promise<Model[]> {
       // Return hardcoded list as Anthropic doesn't have list API
       return [
         {
           id: 'claude-3-opus-20240229',
           name: 'Claude 3 Opus',
           context_length: 200000,
           max_output: 4096,
           cost: { input: 15, output: 75 }
         },
         // ... other models
       ];
     }
     
     async *streamChat(
       messages: ChatMessage[],
       model: string,
       options: ChatOptions
     ): AsyncGenerator<StreamChunk> {
       const stream = await this.client.messages.create({
         model,
         messages: this.transformMessages(messages),
         stream: true,
         max_tokens: options.maxTokens ?? 4096,
       });
       
       for await (const chunk of stream) {
         if (chunk.type === 'content_block_delta') {
           yield {
             type: 'content',
             content: chunk.delta.text,
           };
         } else if (chunk.type === 'message_stop') {
           yield {
             type: 'done',
             usage: {
               input_tokens: chunk.usage?.input_tokens,
               output_tokens: chunk.usage?.output_tokens,
             }
           };
         }
       }
     }
     
     async countTokens(messages: ChatMessage[]): Promise<number> {
       // Use tiktoken or anthropic's token counting
       return this.client.countTokens({ messages });
     }
   }
   ```

5. **Handle streaming responses specially**:
   ```typescript
   // For streaming, output newline-delimited JSON chunks
   async function streamResponse(provider: BaseProvider, params: any) {
     const { messages, model, options } = params;
     
     try {
       for await (const chunk of provider.streamChat(messages, model, options)) {
         // Output each chunk as a separate line
         console.log(JSON.stringify({
           success: true,
           data: chunk,
           streaming: true
         }));
       }
     } catch (error) {
       console.log(JSON.stringify({
         success: false,
         error: {
           code: 'STREAM_ERROR',
           message: error.message
         }
       }));
     }
   }
   ```

6. **Implement OAuth authentication flow**:
   ```typescript
   // auth/device-flow.ts
   export async function githubDeviceFlow(): Promise<string> {
     // Implement GitHub's device flow
     const deviceCode = await initiateDeviceFlow();
     
     // Return instructions for user
     console.log(JSON.stringify({
       success: true,
       data: {
         type: 'device_flow',
         user_code: deviceCode.user_code,
         verification_uri: deviceCode.verification_uri,
         expires_in: deviceCode.expires_in
       }
     }));
     
     // Poll for completion
     const token = await pollForToken(deviceCode);
     return token;
   }
   ```

7. **Add comprehensive error handling**:
   ```typescript
   // utils/retry.ts
   export async function withRetry<T>(
     fn: () => Promise<T>,
     options: RetryOptions = {}
   ): Promise<T> {
     const maxRetries = options.maxRetries ?? 3;
     const backoff = options.backoff ?? 'exponential';
     
     for (let i = 0; i < maxRetries; i++) {
       try {
         return await fn();
       } catch (error) {
         if (!isRetryable(error) || i === maxRetries - 1) {
           throw error;
         }
         
         const delay = calculateDelay(i, backoff);
         await new Promise(resolve => setTimeout(resolve, delay));
       }
     }
   }
   
   function isRetryable(error: any): boolean {
     // Network errors, rate limits, temporary failures
     return error.code === 'ECONNRESET' ||
            error.status === 429 ||
            error.status >= 500;
   }
   ```

8. **Implement token counting utilities**:
   ```typescript
   // utils/tokenizer.ts
   import { encoding_for_model } from 'tiktoken';
   
   export class TokenCounter {
     private encodings = new Map<string, Tiktoken>();
     
     count(text: string, model: string): number {
       const encoding = this.getEncoding(model);
       return encoding.encode(text).length;
     }
     
     countMessages(messages: ChatMessage[], model: string): number {
       // Model-specific message formatting
       let total = 0;
       for (const message of messages) {
         total += 4; // Message overhead
         total += this.count(message.role, model);
         total += this.count(message.content, model);
       }
       return total;
     }
   }
   ```

### Implementation Approach

Follow TDD methodology:

1. **Write tests for each provider**:
   - Mock API responses
   - Test streaming behavior
   - Test error scenarios
   - Test authentication flows
   - Test token counting accuracy

2. **Implement providers incrementally**:
   - Start with Anthropic (simplest API)
   - Add OpenAI (similar pattern)
   - Implement GitHub Copilot (OAuth complexity)
   - Add cloud providers (Bedrock, Vertex, Azure)

3. **Test with real APIs**:
   - Use test API keys
   - Verify streaming works correctly
   - Test rate limiting behavior
   - Ensure costs are calculated correctly

### Git Workflow

```bash
git worktree add worktrees/ai-provider-wrapper -b feat/ai-provider-wrapper
cd worktrees/ai-provider-wrapper
```

Commits:
- `feat: create ai provider executable structure`
- `feat: implement base provider interface`
- `feat: add anthropic provider with streaming`
- `feat: implement openai provider`
- `feat: add github copilot with oauth`
- `feat: implement token counting utilities`
- `test: comprehensive provider test suite`
- `feat: add retry and error handling`

## Success Criteria

✅ **Task is complete when**:
1. All six providers are implemented and tested
2. Streaming works reliably for all providers
3. Authentication flows work (including OAuth)
4. Token counting is accurate for each model
5. Cost calculation matches provider pricing
6. Error handling is robust with retries
7. The executable compiles to under 20MB
8. Integration tests pass with real APIs

## Technical Considerations

<typescript_patterns>
- Use abstract base class for provider interface
- Leverage TypeScript's discriminated unions for responses
- Use async generators for streaming
- Implement proper cleanup on process exit
- Handle SIGTERM gracefully during streaming
</typescript_patterns>

<performance_requirements>
- Minimize memory usage during streaming
- Reuse HTTP connections where possible
- Implement request queuing for rate limits
- Cache model lists and token encodings
- Stream responses without buffering
</performance_requirements>

<security_considerations>
- Never log API keys or tokens
- Validate all input from Zig
- Sanitize error messages
- Use secure storage for OAuth tokens
- Implement request signing where required
</security_considerations>

Remember: This executable is critical for AI functionality. Provider APIs change frequently, so make the code maintainable and well-documented. Focus on reliability and proper error handling.