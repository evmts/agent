/// <reference path="../.astro/types.d.ts" />
/// <reference types="astro/client" />

declare namespace App {
  interface Locals {
    user?: {
      id: number;
      username: string;
      email: string | null;
      displayName: string | null;
      isAdmin: boolean;
      isActive: boolean;
      walletAddress: string;
    };
  }
}

declare module '*.astro' {
  const Component: any;
  export default Component;
}

// Global type augmentations
declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NODE_ENV: 'development' | 'production' | 'test';
      DATABASE_URL: string;
      PUBLIC_CLIENT_API_URL?: string;
      ANTHROPIC_API_KEY?: string;
      HOST?: string;
      PORT?: string;
      WORKING_DIR?: string;
    }
  }
}

// Astro specific types
declare module 'astro:content' {
  export { z } from 'astro/zod';
}

// Import meta environment
interface ImportMetaEnv {
  readonly PUBLIC_CLIENT_API_URL?: string;
  // Add other env variables that are accessed via import.meta.env
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}