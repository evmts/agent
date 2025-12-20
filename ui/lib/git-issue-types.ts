/**
 * Git-based Issue Tracking Types
 *
 * Types for issues stored as markdown files with YAML frontmatter
 * in a nested git repository at .plue/issues/
 */

export interface IssueAuthor {
  id: number;
  username: string;
}

export interface IssueFrontmatter {
  id: number;
  title: string;
  state: "open" | "closed";
  author: IssueAuthor;
  created_at: string;
  updated_at: string;
  closed_at: string | null;
  labels: string[];
  assignees: string[];
  milestone: string | null;
}

export interface CommentFrontmatter {
  id: number;
  author: IssueAuthor;
  created_at: string;
  updated_at?: string;
  edited?: boolean;
}

export interface GitIssue extends IssueFrontmatter {
  number: number;
  body: string;
}

export interface GitComment extends CommentFrontmatter {
  body: string;
}

export interface IssueLabel {
  name: string;
  color: string;
  description?: string;
}

export interface IssueConfig {
  version: number;
  next_issue_number: number;
  labels: IssueLabel[];
  default_assignees: string[];
}

export interface CreateIssueInput {
  title: string;
  body: string;
  author: IssueAuthor;
  labels?: string[];
  assignees?: string[];
  milestone?: string;
}

export interface UpdateIssueInput {
  title?: string;
  body?: string;
  state?: "open" | "closed";
  labels?: string[];
  assignees?: string[];
  milestone?: string | null;
}

export interface CreateCommentInput {
  body: string;
  author: IssueAuthor;
}

export interface UpdateCommentInput {
  body: string;
}

export interface IssueHistoryEntry {
  commitHash: string;
  message: string;
  author: string;
  timestamp: Date;
  action: string;
}

export interface Milestone {
  id: number;
  repository_id: number;
  title: string;
  description: string | null;
  due_date: string | null;
  state: "open" | "closed";
  created_at: string;
  updated_at: string;
  closed_at: string | null;
  open_issues?: number;
  closed_issues?: number;
}

export interface CreateMilestoneInput {
  title: string;
  description?: string;
  due_date?: string;
}

export interface UpdateMilestoneInput {
  title?: string;
  description?: string;
  due_date?: string | null;
  state?: "open" | "closed";
}
