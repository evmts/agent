import { z } from 'zod';

// Request schema
export const RequestSchema = z.object({
  action: z.string(),
  params: z.record(z.unknown()),
  timeout: z.number().int().positive().default(30000).optional(),
});

export type Request = z.infer<typeof RequestSchema>;

// Success response schema
export const SuccessResponseSchema = z.object({
  success: z.literal(true),
  data: z.record(z.unknown()),
});

export type SuccessResponse = z.infer<typeof SuccessResponseSchema>;

// Error response schema
export const ErrorResponseSchema = z.object({
  success: z.literal(false),
  error: z.object({
    code: z.string(),
    message: z.string(),
  }),
});

export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

// Union response type
export type Response = SuccessResponse | ErrorResponse;

// Response type guard
export function isSuccessResponse(response: Response): response is SuccessResponse {
  return response.success === true;
}

export function isErrorResponse(response: Response): response is ErrorResponse {
  return response.success === false;
}

// Helper to create responses
export function successResponse(data: Record<string, unknown>): SuccessResponse {
  return {
    success: true,
    data,
  };
}

export function errorResponse(code: string, message: string): ErrorResponse {
  return {
    success: false,
    error: {
      code,
      message,
    },
  };
}