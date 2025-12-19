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

// =============================================================================
// Pull Request Types
// =============================================================================

export type PullRequestStatus =
  | 'checking'
  | 'mergeable'
  | 'conflict'
  | 'merged'
  | 'error'
  | 'empty';

export type MergeStyle = 'merge' | 'squash' | 'rebase';

export type ReviewType = 'pending' | 'comment' | 'approve' | 'request_changes';

export interface PullRequest {
  id: number;
  issue_id: number;

  // Branch info
  head_repo_id: number | null;
  head_branch: string;
  head_commit_id: string | null;
  base_repo_id: number;
  base_branch: string;
  merge_base: string | null;

  // Status
  status: PullRequestStatus;

  // Merge info
  has_merged: boolean;
  merged_at: Date | null;
  merged_by: number | null;
  merged_commit_id: string | null;
  merge_style: MergeStyle | null;

  // Stats
  commits_ahead: number;
  commits_behind: number;
  additions: number;
  deletions: number;
  changed_files: number;
  conflicted_files: string[] | null;

  allow_maintainer_edit: boolean;
  created_at: Date;
  updated_at: Date;

  // Joined fields
  issue?: Issue;
  head_repo?: Repository;
  base_repo?: Repository;
  merger?: User;
}

export interface Review {
  id: number;
  pull_request_id: number;
  reviewer_id: number;
  type: ReviewType;
  content: string | null;
  commit_id: string | null;
  official: boolean;
  stale: boolean;
  dismissed: boolean;
  created_at: Date;
  updated_at: Date;

  // Joined
  reviewer?: User;
}

export interface ReviewComment {
  id: number;
  review_id: number;
  pull_request_id: number;
  author_id: number;
  commit_id: string;
  file_path: string;
  diff_side: 'left' | 'right';
  line: number;
  body: string;
  invalidated: boolean;
  resolved: boolean;
  created_at: Date;
  updated_at: Date;

  // Joined
  author?: User;
}

export interface DiffFile {
  name: string;
  oldName?: string;
  status: 'added' | 'modified' | 'deleted' | 'renamed';
  additions: number;
  deletions: number;
  changes: number;
  patch: string;
  isBinary: boolean;
}

export interface CompareInfo {
  merge_base: string;
  base_commit_id: string;
  head_commit_id: string;
  commits: Commit[];
  files: DiffFile[];
  total_additions: number;
  total_deletions: number;
  total_files: number;
}