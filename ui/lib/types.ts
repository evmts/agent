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
  topics: string[];
  created_at: Date;
  updated_at: Date;
  // Joined fields
  username?: string;
  star_count?: number;
}

export interface Star {
  id: number;
  user_id: number;
  repository_id: number;
  created_at: Date;
}

export type WatchLevel = 'all' | 'releases' | 'ignore';

export interface Watch {
  id: number;
  user_id: number;
  repository_id: number;
  level: WatchLevel;
  created_at: Date;
  updated_at: Date;
}

export interface Milestone {
  id: number;
  repository_id: number;
  title: string;
  description: string | null;
  due_date: Date | null;
  state: 'open' | 'closed';
  created_at: Date;
  updated_at: Date;
  closed_at: Date | null;
  // Computed fields
  open_issues?: number;
  closed_issues?: number;
}

export interface Issue {
  id: number;
  repository_id: number;
  author_id: number;
  issue_number: number;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  milestone_id: number | null;
  created_at: Date;
  updated_at: Date;
  closed_at: Date | null;
  // Joined fields
  author_username?: string;
  milestone?: Milestone;
}

export interface Comment {
  id: number;
  issue_id: number;
  author_id: number;
  body: string;
  created_at: Date;
  updated_at?: Date;
  edited?: boolean;
  // Joined fields
  author_username?: string;
}

export interface Reaction {
  id: number;
  user_id: number;
  target_type: 'issue' | 'comment';
  target_id: number;
  emoji: string;
  created_at: Date;
  // Joined fields
  username?: string;
}

export interface ReactionGroup {
  emoji: string;
  count: number;
  users: Array<{ id: number; username: string }>;
  has_reacted: boolean;
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
// Branch Management Types
// =============================================================================

export interface Branch {
  id: number;
  repository_id: number;
  name: string;
  commit_id: string;
  commit_message: string | null;
  pusher_id: number | null;
  is_deleted: boolean;
  deleted_by_id: number | null;
  deleted_at: Date | null;
  commit_time: Date;
  created_at: Date;
  updated_at: Date;
  
  // Joined fields
  pusher_username?: string;
}

export interface ProtectedBranch {
  id: number;
  repository_id: number;
  rule_name: string;
  priority: number;

  // Push protection
  can_push: boolean;
  enable_whitelist: boolean;
  whitelist_user_ids: number[];
  whitelist_team_ids: number[];
  whitelist_deploy_keys: boolean;

  // Force push protection
  can_force_push: boolean;
  enable_force_push_allowlist: boolean;
  force_push_allowlist_user_ids: number[];
  force_push_allowlist_team_ids: number[];
  force_push_allowlist_deploy_keys: boolean;

  // Merge protection
  enable_merge_whitelist: boolean;
  merge_whitelist_user_ids: number[];
  merge_whitelist_team_ids: number[];

  // Status checks
  enable_status_check: boolean;
  status_check_contexts: string[];

  // Approvals
  enable_approvals_whitelist: boolean;
  approvals_whitelist_user_ids: number[];
  approvals_whitelist_team_ids: number[];
  required_approvals: number;
  block_on_rejected_reviews: boolean;
  block_on_official_review_requests: boolean;
  block_on_outdated_branch: boolean;
  dismiss_stale_approvals: boolean;
  ignore_stale_approvals: boolean;

  // Advanced
  require_signed_commits: boolean;
  protected_file_patterns: string | null;
  unprotected_file_patterns: string | null;
  block_admin_merge_override: boolean;

  created_at: Date;
  updated_at: Date;
}

export interface RenamedBranch {
  id: number;
  repository_id: number;
  from_name: string;
  to_name: string;
  created_at: Date;
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
  commits_ahead: number;
  commits_behind: number;
}