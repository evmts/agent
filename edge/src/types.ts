export interface Env {
  // Durable Objects
  DATA_SYNC: DurableObjectNamespace;

  // Environment variables
  ORIGIN_HOST: string;
  ELECTRIC_URL: string;
  JWT_SECRET: string;
}

export interface User {
  id: number;
  username: string;
  displayName: string | null;
  avatarUrl: string | null;
  bio: string | null;
  createdAt: string;
}

export interface Repository {
  id: number;
  userId: number;
  name: string;
  description: string | null;
  isPublic: boolean;
  defaultBranch: string;
  createdAt: string;
  updatedAt: string;
  // Joined fields
  username?: string;
}

export interface Issue {
  id: number;
  repositoryId: number;
  authorId: number;
  issueNumber: number;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  createdAt: string;
  updatedAt: string;
  closedAt: string | null;
  // Joined fields
  authorUsername?: string;
}

export interface Comment {
  id: number;
  issueId: number;
  authorId: number;
  body: string;
  createdAt: string;
  // Joined fields
  authorUsername?: string;
}

export interface PullRequest {
  id: number;
  issueId: number;
  headRepoId: number | null;
  headBranch: string;
  baseRepoId: number;
  baseBranch: string;
  status: 'checking' | 'mergeable' | 'conflict' | 'merged';
  hasMerged: boolean;
  createdAt: string;
  updatedAt: string;
  // From joined issue
  title?: string;
  body?: string;
  state?: string;
  authorUsername?: string;
  issueNumber?: number;
}

export interface Review {
  id: number;
  pullRequestId: number;
  reviewerId: number;
  type: 'comment' | 'approve' | 'request_changes';
  content: string | null;
  createdAt: string;
  // Joined fields
  reviewerUsername?: string;
}

export interface JWTPayload {
  userId: number;
  username: string;
  isAdmin: boolean;
  exp: number;
}

export interface RouteMatch {
  type: 'edge' | 'origin';
  handler?: string;
  params?: Record<string, string>;
}
