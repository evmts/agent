#![deny(clippy::all)]

use napi::bindgen_prelude::*;
use napi_derive::napi;
use std::path::PathBuf;
use std::sync::Arc;

use jj_lib::backend::{CommitId, TreeValue};
use jj_lib::commit::Commit;
use jj_lib::config::StackedConfig;
use jj_lib::object_id::ObjectId;
use jj_lib::repo::{ReadonlyRepo, Repo, StoreFactories};
use jj_lib::repo_path::RepoPathBuf;
use jj_lib::settings::UserSettings;
use jj_lib::workspace::{default_working_copy_factories, Workspace};
use tokio::io::AsyncReadExt;

/// Commit information returned to JavaScript
#[napi(object)]
#[derive(Clone)]
pub struct JjCommitInfo {
    pub id: String,
    pub change_id: String,
    pub description: String,
    pub author_name: String,
    pub author_email: String,
    pub author_timestamp: i64,
    pub committer_name: String,
    pub committer_email: String,
    pub committer_timestamp: i64,
    pub parent_ids: Vec<String>,
    pub is_empty: bool,
}

/// File change information
#[napi(object)]
#[derive(Clone)]
pub struct JjFileChange {
    pub path: String,
    pub change_type: String, // "added", "modified", "deleted"
}

/// Branch information
#[napi(object)]
#[derive(Clone)]
pub struct JjBranchInfo {
    pub name: String,
    pub target_id: Option<String>,
    pub is_local: bool,
    pub remote: Option<String>,
}

/// Operation information
#[napi(object)]
#[derive(Clone)]
pub struct JjOperationInfo {
    pub id: String,
    pub description: String,
    pub timestamp: i64,
}

fn create_settings() -> Result<UserSettings> {
    let config = StackedConfig::with_defaults();
    UserSettings::from_config(config)
        .map_err(|e| napi::Error::from_reason(format!("Failed to create settings: {}", e)))
}

/// Main JJ Workspace wrapper
#[napi]
pub struct JjWorkspace {
    workspace_root: PathBuf,
    repo_path: PathBuf,
}

#[napi]
impl JjWorkspace {
    /// Initialize a new jj workspace at the given path
    #[napi(factory)]
    pub fn init(path: String) -> Result<JjWorkspace> {
        let workspace_root = PathBuf::from(&path);
        let settings = create_settings()?;

        let (workspace, _repo) = Workspace::init_internal_git(&settings, &workspace_root)
            .map_err(|e| napi::Error::from_reason(format!("Failed to init workspace: {}", e)))?;

        let repo_path = workspace.repo_path().to_path_buf();

        Ok(JjWorkspace {
            workspace_root,
            repo_path,
        })
    }

    /// Initialize a jj workspace from an existing git repository
    #[napi(factory)]
    pub fn init_colocated(path: String) -> Result<JjWorkspace> {
        let workspace_root = PathBuf::from(&path);
        let settings = create_settings()?;

        let (workspace, _repo) = Workspace::init_colocated_git(&settings, &workspace_root)
            .map_err(|e| napi::Error::from_reason(format!("Failed to init colocated workspace: {}", e)))?;

        let repo_path = workspace.repo_path().to_path_buf();

        Ok(JjWorkspace {
            workspace_root,
            repo_path,
        })
    }

    /// Open an existing jj workspace
    #[napi(factory)]
    pub fn open(path: String) -> Result<JjWorkspace> {
        let workspace_root = PathBuf::from(&path);
        let settings = create_settings()?;

        let workspace = Workspace::load(
            &settings,
            &workspace_root,
            &StoreFactories::default(),
            &default_working_copy_factories(),
        )
        .map_err(|e| napi::Error::from_reason(format!("Failed to open workspace: {}", e)))?;

        let repo_path = workspace.repo_path().to_path_buf();

        Ok(JjWorkspace {
            workspace_root,
            repo_path,
        })
    }

    /// Get the workspace root path
    #[napi(getter)]
    pub fn root(&self) -> String {
        self.workspace_root.to_string_lossy().to_string()
    }

    /// Get the repository path
    #[napi(getter)]
    pub fn repo_path(&self) -> String {
        self.repo_path.to_string_lossy().to_string()
    }

    /// Load the repository for this workspace
    fn load_repo(&self) -> Result<(Workspace, Arc<ReadonlyRepo>)> {
        let settings = create_settings()?;
        let workspace = Workspace::load(
            &settings,
            &self.workspace_root,
            &StoreFactories::default(),
            &default_working_copy_factories(),
        )
        .map_err(|e| napi::Error::from_reason(format!("Failed to load workspace: {}", e)))?;

        let repo = workspace
            .repo_loader()
            .load_at_head()
            .map_err(|e| napi::Error::from_reason(format!("Failed to load repo: {}", e)))?;

        Ok((workspace, repo))
    }

    /// Get commit by ID (hex string)
    #[napi]
    pub fn get_commit(&self, commit_id: String) -> Result<JjCommitInfo> {
        let (_workspace, repo) = self.load_repo()?;

        let id = CommitId::try_from_hex(&commit_id)
            .ok_or_else(|| napi::Error::from_reason(format!("Invalid commit ID: {}", commit_id)))?;

        let commit = repo
            .store()
            .get_commit(&id)
            .map_err(|e| napi::Error::from_reason(format!("Failed to get commit: {}", e)))?;

        Ok(self.commit_to_info(&commit, repo.as_ref()))
    }

    /// List all bookmarks (formerly branches)
    /// Also includes git branches for colocated repos where git refs haven't been imported
    #[napi]
    pub fn list_bookmarks(&self) -> Result<Vec<JjBranchInfo>> {
        let (_workspace, repo) = self.load_repo()?;
        let view = repo.view();

        let mut bookmarks = Vec::new();
        let mut seen_names = std::collections::HashSet::new();

        // First, get jj bookmarks
        for (name, target) in view.local_bookmarks() {
            let name_str = name.as_str().to_string();
            seen_names.insert(name_str.clone());
            bookmarks.push(JjBranchInfo {
                name: name_str,
                target_id: target.as_normal().map(|id| id.hex()),
                is_local: true,
                remote: None,
            });
        }

        // For colocated repos: also list git branches that aren't in jj bookmarks
        let git_refs_dir = self.workspace_root.join(".git/refs/heads");
        if git_refs_dir.exists() {
            if let Ok(entries) = std::fs::read_dir(&git_refs_dir) {
                for entry in entries.flatten() {
                    if let Ok(name) = entry.file_name().into_string() {
                        if !seen_names.contains(&name) {
                            // Read the commit ID from the ref file
                            let ref_path = entry.path();
                            let target_id = std::fs::read_to_string(&ref_path)
                                .ok()
                                .map(|s| s.trim().to_string());

                            bookmarks.push(JjBranchInfo {
                                name,
                                target_id,
                                is_local: true,
                                remote: None,
                            });
                        }
                    }
                }
            }
        }

        Ok(bookmarks)
    }

    /// Get the current operation info
    #[napi]
    pub fn get_current_operation(&self) -> Result<JjOperationInfo> {
        let (_workspace, repo) = self.load_repo()?;

        let current_op = repo.operation();
        let metadata = current_op.metadata();

        Ok(JjOperationInfo {
            id: current_op.id().hex(),
            description: metadata.description.clone(),
            timestamp: metadata.time.end.timestamp.0,
        })
    }

    /// Get the root commit (empty initial commit)
    #[napi]
    pub fn get_root_commit(&self) -> Result<JjCommitInfo> {
        let (_workspace, repo) = self.load_repo()?;
        let store = repo.store();
        let root_commit = store.root_commit();
        Ok(self.commit_to_info(&root_commit, repo.as_ref()))
    }

    /// List all heads (commits with no children)
    #[napi]
    pub fn list_heads(&self) -> Result<Vec<String>> {
        let (_workspace, repo) = self.load_repo()?;
        let view = repo.view();
        Ok(view.heads().iter().map(|id| id.hex()).collect())
    }

    /// List all files at a specific revision (change_id, commit_id, or bookmark name)
    #[napi]
    pub fn list_files(&self, revision: String) -> Result<Vec<String>> {
        let (_workspace, repo) = self.load_repo()?;
        let commit = self.resolve_revision(&repo, &revision)?;
        let tree = commit.tree();

        let mut files = Vec::new();
        for (path, value_result) in tree.entries() {
            // Skip errors and non-file entries
            if let Ok(value) = value_result {
                if let Some(Some(TreeValue::File { .. })) = value.as_resolved() {
                    files.push(path.as_internal_file_string().to_string());
                }
            }
        }

        Ok(files)
    }

    /// Get file content at a specific revision
    #[napi]
    pub fn get_file_content(&self, revision: String, path: String) -> Result<Option<String>> {
        let (_workspace, repo) = self.load_repo()?;
        let commit = self.resolve_revision(&repo, &revision)?;
        let tree = commit.tree();

        let repo_path = RepoPathBuf::from_internal_string(&path)
            .map_err(|e| napi::Error::from_reason(format!("Invalid path '{}': {}", path, e)))?;

        let value = tree.path_value(&repo_path)
            .map_err(|e| napi::Error::from_reason(format!("Failed to get path value: {}", e)))?;

        // Check if it's a resolved file
        if let Some(Some(TreeValue::File { id, .. })) = value.as_resolved() {
            let store = repo.store();

            // Create a runtime to block on async file read
            let rt = tokio::runtime::Runtime::new()
                .map_err(|e| napi::Error::from_reason(format!("Failed to create runtime: {}", e)))?;

            let content = rt.block_on(async {
                let mut reader = store.read_file(&repo_path, id).await
                    .map_err(|e| napi::Error::from_reason(format!("Failed to read file: {}", e)))?;

                let mut buf = Vec::new();
                reader.read_to_end(&mut buf).await
                    .map_err(|e| napi::Error::from_reason(format!("Failed to read content: {}", e)))?;

                Ok::<String, napi::Error>(String::from_utf8_lossy(&buf).to_string())
            })?;

            Ok(Some(content))
        } else {
            Ok(None)
        }
    }

    /// List recent changes/commits with full info
    #[napi]
    pub fn list_changes(&self, limit: Option<u32>, bookmark: Option<String>) -> Result<Vec<JjCommitInfo>> {
        let (_workspace, repo) = self.load_repo()?;
        let limit = limit.unwrap_or(50) as usize;

        // Walk from heads using a simple BFS
        let view = repo.view();
        let mut changes = Vec::new();
        let mut seen = std::collections::HashSet::new();
        let mut stack: Vec<CommitId> = view.heads().iter().cloned().collect();

        // If bookmark specified, start from that bookmark's target
        if let Some(ref bm) = bookmark {
            stack.clear();
            for (name, target) in view.local_bookmarks() {
                if name.as_str() == bm {
                    if let Some(id) = target.as_normal() {
                        stack.push(id.clone());
                    }
                    break;
                }
            }
        }

        while let Some(commit_id) = stack.pop() {
            if changes.len() >= limit {
                break;
            }
            if !seen.insert(commit_id.clone()) {
                continue;
            }

            if let Ok(commit) = repo.store().get_commit(&commit_id) {
                changes.push(self.commit_to_info(&commit, repo.as_ref()));

                // Add parents to stack
                for parent_id in commit.parent_ids() {
                    if !seen.contains(parent_id) {
                        stack.push(parent_id.clone());
                    }
                }
            }
        }

        Ok(changes)
    }

    /// Resolve a revision string (change_id, commit_id, or bookmark name) to a commit
    fn resolve_revision(&self, repo: &Arc<ReadonlyRepo>, revision: &str) -> Result<Commit> {
        // Try as commit id first (40 hex chars)
        if let Some(id) = CommitId::try_from_hex(revision) {
            if let Ok(commit) = repo.store().get_commit(&id) {
                return Ok(commit);
            }
        }

        // Try as bookmark name (jj's equivalent of branches)
        let view = repo.view();
        for (name, target) in view.local_bookmarks() {
            if name.as_str() == revision {
                if let Some(id) = target.as_normal() {
                    return repo.store().get_commit(id)
                        .map_err(|e| napi::Error::from_reason(format!("Failed to get commit: {}", e)));
                }
            }
        }

        // For colocated repos: try to read git refs directly from .git
        // This handles the case where git branches weren't imported as jj bookmarks
        let git_ref_path = self.workspace_root.join(".git/refs/heads").join(revision);
        if git_ref_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&git_ref_path) {
                let commit_hex = content.trim();
                if let Some(id) = CommitId::try_from_hex(commit_hex) {
                    if let Ok(commit) = repo.store().get_commit(&id) {
                        return Ok(commit);
                    }
                }
            }
        }

        // Also try packed-refs for git
        let packed_refs_path = self.workspace_root.join(".git/packed-refs");
        if packed_refs_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&packed_refs_path) {
                let ref_name = format!("refs/heads/{}", revision);
                for line in content.lines() {
                    if line.starts_with('#') {
                        continue;
                    }
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 && parts[1] == ref_name {
                        if let Some(id) = CommitId::try_from_hex(parts[0]) {
                            if let Ok(commit) = repo.store().get_commit(&id) {
                                return Ok(commit);
                            }
                        }
                    }
                }
            }
        }

        // Try as change id prefix - walk all reachable commits to find matching change id
        if revision.len() >= 4 && revision.len() <= 40 && revision.chars().all(|c| c.is_ascii_hexdigit()) {
            let mut stack: Vec<CommitId> = view.heads().iter().cloned().collect();
            let mut seen = std::collections::HashSet::new();

            while let Some(commit_id) = stack.pop() {
                if !seen.insert(commit_id.clone()) {
                    continue;
                }

                if let Ok(commit) = repo.store().get_commit(&commit_id) {
                    if commit.change_id().hex().starts_with(revision) {
                        return Ok(commit);
                    }
                    for parent_id in commit.parent_ids() {
                        if !seen.contains(parent_id) {
                            stack.push(parent_id.clone());
                        }
                    }
                }
            }
        }

        Err(napi::Error::from_reason(format!("Could not resolve revision: {}", revision)))
    }

    fn commit_to_info(&self, commit: &Commit, repo: &dyn Repo) -> JjCommitInfo {
        let author = commit.author();
        let committer = commit.committer();
        let is_empty = commit.is_empty(repo).unwrap_or(true);

        JjCommitInfo {
            id: commit.id().hex(),
            change_id: commit.change_id().hex(),
            description: commit.description().to_string(),
            author_name: author.name.clone(),
            author_email: author.email.clone(),
            author_timestamp: author.timestamp.timestamp.0,
            committer_name: committer.name.clone(),
            committer_email: committer.email.clone(),
            committer_timestamp: committer.timestamp.timestamp.0,
            parent_ids: commit.parent_ids().iter().map(|id| id.hex()).collect(),
            is_empty,
        }
    }
}

/// Check if a path contains a jj workspace
#[napi]
pub fn is_jj_workspace(path: String) -> bool {
    let workspace_root = PathBuf::from(&path);
    workspace_root.join(".jj").exists()
}

/// Check if a path contains a git repository
#[napi]
pub fn is_git_repo(path: String) -> bool {
    let repo_path = PathBuf::from(&path);
    repo_path.join(".git").exists()
}
