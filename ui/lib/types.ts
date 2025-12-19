export interface User {
  id: number;
  username: string;
  display_name: string | null;
  bio: string | null;
  avatar_url: string | null;
  created_at: Date;
}

export interface AuthUser {
  id: number;
  username: string;
  email: string;
  displayName: string | null;
  isAdmin: boolean;
  isActive: boolean;
}

export interface Repository {
  id: number;
  user_id: number;
  name: string;
  description: string | null;
  is_public: boolean;
  default_branch: string;
  created_at: Date;
  updated_at: Date;
  // Joined fields
  username?: string;
}

export interface Issue {
  id: number;
  repository_id: number;
  author_id: number;
  issue_number: number;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  created_at: Date;
  updated_at: Date;
  closed_at: Date | null;
  // Joined fields
  author_username?: string;
}

export interface Comment {
  id: number;
  issue_id: number;
  author_id: number;
  body: string;
  created_at: Date;
  // Joined fields
  author_username?: string;
}

export interface TreeEntry {
  mode: string;
  type: 'blob' | 'tree';
  hash: string;
  name: string;
}

export interface Commit {
  hash: string;
  shortHash: string;
  authorName: string;
  authorEmail: string;
  timestamp: number;
  message: string;
}