#![deny(clippy::all)]

use napi::bindgen_prelude::*;
use napi_derive::napi;
use std::path::PathBuf;
use std::sync::Arc;

use jj_lib::backend::CommitId;
use jj_lib::commit::Commit;
use jj_lib::config::StackedConfig;
use jj_lib::object_id::ObjectId;
use jj_lib::repo::{ReadonlyRepo, Repo, StoreFactories};
use jj_lib::settings::UserSettings;
use jj_lib::workspace::{default_working_copy_factories, Workspace};
use pollster::FutureExt;

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
    #[napi]
    pub fn list_bookmarks(&self) -> Result<Vec<JjBranchInfo>> {
        let (_workspace, repo) = self.load_repo()?;
        let view = repo.view();

        let mut bookmarks = Vec::new();

        for (name, target) in view.local_bookmarks() {
            bookmarks.push(JjBranchInfo {
                name: name.as_str().to_string(),
                target_id: target.as_normal().map(|id| id.hex()),
                is_local: true,
                remote: None,
            });
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
            timestamp: metadata.time.end.timestamp.0 as i64,
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
            author_timestamp: author.timestamp.timestamp.0 as i64,
            committer_name: committer.name.clone(),
            committer_email: committer.email.clone(),
            committer_timestamp: committer.timestamp.timestamp.0 as i64,
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
