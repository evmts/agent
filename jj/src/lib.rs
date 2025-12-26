#![allow(clippy::missing_safety_doc)]

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use jj_lib::backend::{CommitId, TreeValue};
use jj_lib::commit::Commit;
use jj_lib::config::StackedConfig;
use jj_lib::object_id::ObjectId;
use jj_lib::repo::{ReadonlyRepo, Repo, StoreFactories};
use jj_lib::repo_path::RepoPathBuf;
use jj_lib::settings::UserSettings;
use jj_lib::workspace::{default_working_copy_factories, Workspace};

// Opaque handle for JjWorkspace
pub struct JjWorkspace {
    workspace_root: PathBuf,
    #[allow(dead_code)]
    repo_path: PathBuf,
}

// C-compatible commit info structure
#[repr(C)]
pub struct JjCommitInfo {
    pub id: *mut c_char,
    pub change_id: *mut c_char,
    pub description: *mut c_char,
    pub author_name: *mut c_char,
    pub author_email: *mut c_char,
    pub author_timestamp: i64,
    pub committer_name: *mut c_char,
    pub committer_email: *mut c_char,
    pub committer_timestamp: i64,
    pub parent_ids: *mut *mut c_char,
    pub parent_ids_len: usize,
    pub is_empty: bool,
}

// C-compatible bookmark info structure
#[repr(C)]
pub struct JjBookmarkInfo {
    pub name: *mut c_char,
    pub target_id: *mut c_char, // nullable (null pointer means None)
    pub is_local: bool,
}

// C-compatible operation info structure
#[repr(C)]
pub struct JjOperationInfo {
    pub id: *mut c_char,
    pub description: *mut c_char,
    pub timestamp: i64,
}

// C-compatible string array
#[repr(C)]
pub struct JjStringArray {
    pub strings: *mut *mut c_char,
    pub len: usize,
}

// C-compatible result types
#[repr(C)]
pub struct JjResult {
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjWorkspaceResult {
    pub workspace: *mut JjWorkspace,
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjCommitInfoResult {
    pub commit: *mut JjCommitInfo,
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjBookmarkArrayResult {
    pub bookmarks: *mut JjBookmarkInfo,
    pub len: usize,
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjCommitArrayResult {
    pub commits: *mut *mut JjCommitInfo,
    pub len: usize,
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjStringArrayResult {
    pub strings: *mut *mut c_char,
    pub len: usize,
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjStringResult {
    pub string: *mut c_char,
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjOperationInfoResult {
    pub operation: *mut JjOperationInfo,
    pub success: bool,
    pub error_message: *mut c_char,
}

#[repr(C)]
pub struct JjTreeHash {
    pub hash: *mut c_char, // hex-encoded tree root hash
    pub success: bool,
    pub error_message: *mut c_char,
}

// Helper functions
fn create_settings() -> Result<UserSettings, String> {
    let config = StackedConfig::with_defaults();
    UserSettings::from_config(config).map_err(|e| format!("Failed to create settings: {}", e))
}

fn load_repo(workspace_root: &Path) -> Result<(Workspace, Arc<ReadonlyRepo>), String> {
    let settings = create_settings()?;
    let workspace = Workspace::load(
        &settings,
        workspace_root,
        &StoreFactories::default(),
        &default_working_copy_factories(),
    )
    .map_err(|e| format!("Failed to load workspace: {}", e))?;

    let repo = workspace
        .repo_loader()
        .load_at_head()
        .map_err(|e| format!("Failed to load repo: {}", e))?;

    Ok((workspace, repo))
}

fn commit_to_info(commit: &Commit, repo: &dyn Repo) -> JjCommitInfo {
    let author = commit.author();
    let committer = commit.committer();
    let is_empty = commit.is_empty(repo).unwrap_or(true);

    let parent_ids: Vec<*mut c_char> = commit
        .parent_ids()
        .iter()
        .map(|id| {
            CString::new(id.hex())
                .unwrap_or_default()
                .into_raw()
        })
        .collect();

    let parent_ids_len = parent_ids.len();
    let parent_ids_ptr = if parent_ids_len > 0 {
        let boxed = parent_ids.into_boxed_slice();
        Box::into_raw(boxed) as *mut *mut c_char
    } else {
        std::ptr::null_mut()
    };

    JjCommitInfo {
        id: CString::new(commit.id().hex()).unwrap_or_default().into_raw(),
        change_id: CString::new(commit.change_id().hex()).unwrap_or_default().into_raw(),
        description: CString::new(commit.description()).unwrap_or_default().into_raw(),
        author_name: CString::new(author.name.clone()).unwrap_or_default().into_raw(),
        author_email: CString::new(author.email.clone()).unwrap_or_default().into_raw(),
        author_timestamp: author.timestamp.timestamp.0,
        committer_name: CString::new(committer.name.clone()).unwrap_or_default().into_raw(),
        committer_email: CString::new(committer.email.clone()).unwrap_or_default().into_raw(),
        committer_timestamp: committer.timestamp.timestamp.0,
        parent_ids: parent_ids_ptr,
        parent_ids_len,
        is_empty,
    }
}

// FFI Functions

/// Initialize a new jj workspace at the given path
#[no_mangle]
pub unsafe extern "C" fn jj_workspace_init(path: *const c_char) -> JjWorkspaceResult {
    if path.is_null() {
        return JjWorkspaceResult {
            workspace: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Path is null").unwrap().into_raw(),
        };
    }

    let c_str = CStr::from_ptr(path);
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjWorkspaceResult {
                workspace: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let workspace_root = PathBuf::from(path_str);
    let settings = match create_settings() {
        Ok(s) => s,
        Err(e) => {
            return JjWorkspaceResult {
                workspace: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    match Workspace::init_internal_git(&settings, &workspace_root) {
        Ok((workspace, _repo)) => {
            let repo_path = workspace.repo_path().to_path_buf();
            let jj_workspace = Box::new(JjWorkspace {
                workspace_root,
                repo_path,
            });

            JjWorkspaceResult {
                workspace: Box::into_raw(jj_workspace),
                success: true,
                error_message: std::ptr::null_mut(),
            }
        }
        Err(e) => JjWorkspaceResult {
            workspace: std::ptr::null_mut(),
            success: false,
            error_message: CString::new(format!("Failed to init workspace: {}", e))
                .unwrap()
                .into_raw(),
        },
    }
}

/// Open an existing jj workspace
#[no_mangle]
pub unsafe extern "C" fn jj_workspace_open(path: *const c_char) -> JjWorkspaceResult {
    if path.is_null() {
        return JjWorkspaceResult {
            workspace: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Path is null").unwrap().into_raw(),
        };
    }

    let c_str = CStr::from_ptr(path);
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjWorkspaceResult {
                workspace: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let workspace_root = PathBuf::from(path_str);
    let settings = match create_settings() {
        Ok(s) => s,
        Err(e) => {
            return JjWorkspaceResult {
                workspace: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    match Workspace::load(
        &settings,
        &workspace_root,
        &StoreFactories::default(),
        &default_working_copy_factories(),
    ) {
        Ok(workspace) => {
            let repo_path = workspace.repo_path().to_path_buf();
            let jj_workspace = Box::new(JjWorkspace {
                workspace_root,
                repo_path,
            });

            JjWorkspaceResult {
                workspace: Box::into_raw(jj_workspace),
                success: true,
                error_message: std::ptr::null_mut(),
            }
        }
        Err(e) => JjWorkspaceResult {
            workspace: std::ptr::null_mut(),
            success: false,
            error_message: CString::new(format!("Failed to open workspace: {}", e))
                .unwrap()
                .into_raw(),
        },
    }
}

/// Initialize a jj workspace from an existing git repository
#[no_mangle]
pub unsafe extern "C" fn jj_workspace_init_colocated(path: *const c_char) -> JjWorkspaceResult {
    if path.is_null() {
        return JjWorkspaceResult {
            workspace: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Path is null").unwrap().into_raw(),
        };
    }

    let c_str = CStr::from_ptr(path);
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjWorkspaceResult {
                workspace: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let workspace_root = PathBuf::from(path_str);
    let settings = match create_settings() {
        Ok(s) => s,
        Err(e) => {
            return JjWorkspaceResult {
                workspace: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    match Workspace::init_colocated_git(&settings, &workspace_root) {
        Ok((workspace, _repo)) => {
            let repo_path = workspace.repo_path().to_path_buf();
            let jj_workspace = Box::new(JjWorkspace {
                workspace_root,
                repo_path,
            });

            JjWorkspaceResult {
                workspace: Box::into_raw(jj_workspace),
                success: true,
                error_message: std::ptr::null_mut(),
            }
        }
        Err(e) => JjWorkspaceResult {
            workspace: std::ptr::null_mut(),
            success: false,
            error_message: CString::new(format!("Failed to init colocated workspace: {}", e))
                .unwrap()
                .into_raw(),
        },
    }
}

/// Get commit by ID (hex string)
#[no_mangle]
pub unsafe extern "C" fn jj_get_commit(
    workspace: *const JjWorkspace,
    commit_id: *const c_char,
) -> JjCommitInfoResult {
    if workspace.is_null() {
        return JjCommitInfoResult {
            commit: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Workspace is null").unwrap().into_raw(),
        };
    }

    if commit_id.is_null() {
        return JjCommitInfoResult {
            commit: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Commit ID is null").unwrap().into_raw(),
        };
    }

    let ws = &*workspace;
    let c_str = CStr::from_ptr(commit_id);
    let commit_id_str = match c_str.to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjCommitInfoResult {
                commit: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let (_workspace, repo) = match load_repo(&ws.workspace_root) {
        Ok(r) => r,
        Err(e) => {
            return JjCommitInfoResult {
                commit: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    let id = match CommitId::try_from_hex(commit_id_str) {
        Some(id) => id,
        None => {
            return JjCommitInfoResult {
                commit: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid commit ID: {}", commit_id_str))
                    .unwrap()
                    .into_raw(),
            };
        }
    };

    match repo.store().get_commit(&id) {
        Ok(commit) => {
            let info = commit_to_info(&commit, repo.as_ref());
            JjCommitInfoResult {
                commit: Box::into_raw(Box::new(info)),
                success: true,
                error_message: std::ptr::null_mut(),
            }
        }
        Err(e) => JjCommitInfoResult {
            commit: std::ptr::null_mut(),
            success: false,
            error_message: CString::new(format!("Failed to get commit: {}", e))
                .unwrap()
                .into_raw(),
        },
    }
}

/// List all bookmarks
#[no_mangle]
pub unsafe extern "C" fn jj_list_bookmarks(
    workspace: *const JjWorkspace,
) -> JjBookmarkArrayResult {
    if workspace.is_null() {
        return JjBookmarkArrayResult {
            bookmarks: std::ptr::null_mut(),
            len: 0,
            success: false,
            error_message: CString::new("Workspace is null").unwrap().into_raw(),
        };
    }

    let ws = &*workspace;
    let (_workspace, repo) = match load_repo(&ws.workspace_root) {
        Ok(r) => r,
        Err(e) => {
            return JjBookmarkArrayResult {
                bookmarks: std::ptr::null_mut(),
                len: 0,
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    let view = repo.view();
    let mut bookmarks = Vec::new();

    for (name, target) in view.local_bookmarks() {
        let target_id = target.as_normal().map(|id| {
            CString::new(id.hex())
                .unwrap_or_default()
                .into_raw()
        });

        bookmarks.push(JjBookmarkInfo {
            name: CString::new(name.as_str())
                .unwrap_or_default()
                .into_raw(),
            target_id: target_id.unwrap_or(std::ptr::null_mut()),
            is_local: true,
        });
    }

    let len = bookmarks.len();
    let bookmarks_ptr = if len > 0 {
        let boxed = bookmarks.into_boxed_slice();
        Box::into_raw(boxed) as *mut JjBookmarkInfo
    } else {
        std::ptr::null_mut()
    };

    JjBookmarkArrayResult {
        bookmarks: bookmarks_ptr,
        len,
        success: true,
        error_message: std::ptr::null_mut(),
    }
}

/// List recent changes/commits
#[no_mangle]
pub unsafe extern "C" fn jj_list_changes(
    workspace: *const JjWorkspace,
    limit: u32,
    bookmark: *const c_char,
) -> JjCommitArrayResult {
    if workspace.is_null() {
        return JjCommitArrayResult {
            commits: std::ptr::null_mut(),
            len: 0,
            success: false,
            error_message: CString::new("Workspace is null").unwrap().into_raw(),
        };
    }

    let ws = &*workspace;
    let bookmark_str = if bookmark.is_null() {
        None
    } else {
        let c_str = CStr::from_ptr(bookmark);
        match c_str.to_str() {
            Ok(s) => Some(s.to_string()),
            Err(_) => None,
        }
    };

    let (_workspace, repo) = match load_repo(&ws.workspace_root) {
        Ok(r) => r,
        Err(e) => {
            return JjCommitArrayResult {
                commits: std::ptr::null_mut(),
                len: 0,
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    let limit = limit as usize;
    let view = repo.view();
    let mut changes = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut stack: Vec<CommitId> = view.heads().iter().cloned().collect();

    // If bookmark specified, start from that bookmark's target
    if let Some(ref bm) = bookmark_str {
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
            let info = commit_to_info(&commit, repo.as_ref());
            changes.push(Box::into_raw(Box::new(info)));

            // Add parents to stack
            for parent_id in commit.parent_ids() {
                if !seen.contains(parent_id) {
                    stack.push(parent_id.clone());
                }
            }
        }
    }

    let len = changes.len();
    let commits_ptr = if len > 0 {
        let boxed = changes.into_boxed_slice();
        Box::into_raw(boxed) as *mut *mut JjCommitInfo
    } else {
        std::ptr::null_mut()
    };

    JjCommitArrayResult {
        commits: commits_ptr,
        len,
        success: true,
        error_message: std::ptr::null_mut(),
    }
}

/// List all files at a specific revision
#[no_mangle]
pub unsafe extern "C" fn jj_list_files(
    workspace: *const JjWorkspace,
    revision: *const c_char,
) -> JjStringArrayResult {
    if workspace.is_null() {
        return JjStringArrayResult {
            strings: std::ptr::null_mut(),
            len: 0,
            success: false,
            error_message: CString::new("Workspace is null").unwrap().into_raw(),
        };
    }

    if revision.is_null() {
        return JjStringArrayResult {
            strings: std::ptr::null_mut(),
            len: 0,
            success: false,
            error_message: CString::new("Revision is null").unwrap().into_raw(),
        };
    }

    let ws = &*workspace;
    let c_str = CStr::from_ptr(revision);
    let revision_str = match c_str.to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjStringArrayResult {
                strings: std::ptr::null_mut(),
                len: 0,
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let (_workspace, repo) = match load_repo(&ws.workspace_root) {
        Ok(r) => r,
        Err(e) => {
            return JjStringArrayResult {
                strings: std::ptr::null_mut(),
                len: 0,
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    // Resolve revision to commit
    let commit = match CommitId::try_from_hex(revision_str) {
        Some(id) => match repo.store().get_commit(&id) {
            Ok(c) => c,
            Err(e) => {
                return JjStringArrayResult {
                    strings: std::ptr::null_mut(),
                    len: 0,
                    success: false,
                    error_message: CString::new(format!("Failed to get commit: {}", e))
                        .unwrap()
                        .into_raw(),
                };
            }
        },
        None => {
            return JjStringArrayResult {
                strings: std::ptr::null_mut(),
                len: 0,
                success: false,
                error_message: CString::new(format!("Invalid commit ID: {}", revision_str))
                    .unwrap()
                    .into_raw(),
            };
        }
    };

    let tree = commit.tree();
    let mut files = Vec::new();

    for (path, value_result) in tree.entries() {
        if let Ok(value) = value_result {
            if let Some(Some(TreeValue::File { .. })) = value.as_resolved() {
                files.push(
                    CString::new(path.as_internal_file_string())
                        .unwrap_or_default()
                        .into_raw(),
                );
            }
        }
    }

    let len = files.len();
    let files_ptr = if len > 0 {
        let boxed = files.into_boxed_slice();
        Box::into_raw(boxed) as *mut *mut c_char
    } else {
        std::ptr::null_mut()
    };

    JjStringArrayResult {
        strings: files_ptr,
        len,
        success: true,
        error_message: std::ptr::null_mut(),
    }
}

/// Get file content at a specific revision
#[no_mangle]
pub unsafe extern "C" fn jj_get_file_content(
    workspace: *const JjWorkspace,
    revision: *const c_char,
    path: *const c_char,
) -> JjStringResult {
    if workspace.is_null() {
        return JjStringResult {
            string: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Workspace is null").unwrap().into_raw(),
        };
    }

    if revision.is_null() {
        return JjStringResult {
            string: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Revision is null").unwrap().into_raw(),
        };
    }

    if path.is_null() {
        return JjStringResult {
            string: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Path is null").unwrap().into_raw(),
        };
    }

    let ws = &*workspace;
    let revision_str = match CStr::from_ptr(revision).to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjStringResult {
                string: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let path_str = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjStringResult {
                string: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let (_workspace, repo) = match load_repo(&ws.workspace_root) {
        Ok(r) => r,
        Err(e) => {
            return JjStringResult {
                string: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    // Resolve revision to commit
    let commit = match CommitId::try_from_hex(revision_str) {
        Some(id) => match repo.store().get_commit(&id) {
            Ok(c) => c,
            Err(e) => {
                return JjStringResult {
                    string: std::ptr::null_mut(),
                    success: false,
                    error_message: CString::new(format!("Failed to get commit: {}", e))
                        .unwrap()
                        .into_raw(),
                };
            }
        },
        None => {
            return JjStringResult {
                string: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid commit ID: {}", revision_str))
                    .unwrap()
                    .into_raw(),
            };
        }
    };

    let tree = commit.tree();
    let repo_path = match RepoPathBuf::from_internal_string(path_str) {
        Ok(p) => p,
        Err(e) => {
            return JjStringResult {
                string: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid path '{}': {}", path_str, e))
                    .unwrap()
                    .into_raw(),
            };
        }
    };

    let value = match tree.path_value(&repo_path) {
        Ok(v) => v,
        Err(e) => {
            return JjStringResult {
                string: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Failed to get path value: {}", e))
                    .unwrap()
                    .into_raw(),
            };
        }
    };

    if let Some(Some(TreeValue::File { id, .. })) = value.as_resolved() {
        let store = repo.store();

        // Create a runtime to block on async file read
        let rt = match tokio::runtime::Runtime::new() {
            Ok(r) => r,
            Err(e) => {
                return JjStringResult {
                    string: std::ptr::null_mut(),
                    success: false,
                    error_message: CString::new(format!("Failed to create runtime: {}", e))
                        .unwrap()
                        .into_raw(),
                };
            }
        };

        match rt.block_on(async {
            use tokio::io::AsyncReadExt;
            let mut reader = store.read_file(&repo_path, id).await?;
            let mut buf = Vec::new();
            reader.read_to_end(&mut buf).await?;
            Ok::<Vec<u8>, Box<dyn std::error::Error>>(buf)
        }) {
            Ok(content) => {
                let content_str = String::from_utf8_lossy(&content).to_string();
                JjStringResult {
                    string: CString::new(content_str).unwrap_or_default().into_raw(),
                    success: true,
                    error_message: std::ptr::null_mut(),
                }
            }
            Err(e) => JjStringResult {
                string: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Failed to read file: {}", e))
                    .unwrap()
                    .into_raw(),
            },
        }
    } else {
        JjStringResult {
            string: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("File not found").unwrap().into_raw(),
        }
    }
}

/// Get the current operation info
#[no_mangle]
pub unsafe extern "C" fn jj_get_current_operation(
    workspace: *const JjWorkspace,
) -> JjOperationInfoResult {
    if workspace.is_null() {
        return JjOperationInfoResult {
            operation: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Workspace is null").unwrap().into_raw(),
        };
    }

    let ws = &*workspace;
    let (_workspace, repo) = match load_repo(&ws.workspace_root) {
        Ok(r) => r,
        Err(e) => {
            return JjOperationInfoResult {
                operation: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    let current_op = repo.operation();
    let metadata = current_op.metadata();

    let info = JjOperationInfo {
        id: CString::new(current_op.id().hex())
            .unwrap_or_default()
            .into_raw(),
        description: CString::new(metadata.description.clone())
            .unwrap_or_default()
            .into_raw(),
        timestamp: metadata.time.end.timestamp.0,
    };

    JjOperationInfoResult {
        operation: Box::into_raw(Box::new(info)),
        success: true,
        error_message: std::ptr::null_mut(),
    }
}

/// Get the tree hash (merkle root) for a revision
///
/// # Safety
/// workspace must be a valid pointer from jj_workspace_open
/// revision must be a valid null-terminated C string
#[no_mangle]
pub unsafe extern "C" fn jj_get_tree_hash(
    workspace: *const JjWorkspace,
    revision: *const c_char,
) -> JjTreeHash {
    if workspace.is_null() {
        return JjTreeHash {
            hash: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Workspace is null").unwrap().into_raw(),
        };
    }

    if revision.is_null() {
        return JjTreeHash {
            hash: std::ptr::null_mut(),
            success: false,
            error_message: CString::new("Revision is null").unwrap().into_raw(),
        };
    }

    let ws = &*workspace;
    let c_str = CStr::from_ptr(revision);
    let revision_str = match c_str.to_str() {
        Ok(s) => s,
        Err(e) => {
            return JjTreeHash {
                hash: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid UTF-8: {}", e)).unwrap().into_raw(),
            };
        }
    };

    let (_workspace, repo) = match load_repo(&ws.workspace_root) {
        Ok(r) => r,
        Err(e) => {
            return JjTreeHash {
                hash: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(e).unwrap().into_raw(),
            };
        }
    };

    // Resolve revision to commit
    let commit = match CommitId::try_from_hex(revision_str) {
        Some(id) => match repo.store().get_commit(&id) {
            Ok(c) => c,
            Err(e) => {
                return JjTreeHash {
                    hash: std::ptr::null_mut(),
                    success: false,
                    error_message: CString::new(format!("Failed to get commit: {}", e))
                        .unwrap()
                        .into_raw(),
                };
            }
        },
        None => {
            return JjTreeHash {
                hash: std::ptr::null_mut(),
                success: false,
                error_message: CString::new(format!("Invalid commit ID: {}", revision_str))
                    .unwrap()
                    .into_raw(),
            };
        }
    };

    // Get the tree from the commit and then its ID
    let tree = commit.tree();
    let tree_ids = tree.tree_ids();

    // Get the resolved tree ID (if there are conflicts, return an error)
    let tree_id = match tree_ids.as_resolved() {
        Some(id) => id,
        None => {
            return JjTreeHash {
                hash: std::ptr::null_mut(),
                success: false,
                error_message: CString::new("Tree has unresolved conflicts")
                    .unwrap()
                    .into_raw(),
            };
        }
    };

    let tree_hash = tree_id.hex();

    JjTreeHash {
        hash: CString::new(tree_hash).unwrap_or_default().into_raw(),
        success: true,
        error_message: std::ptr::null_mut(),
    }
}

/// Check if a path contains a jj workspace
#[no_mangle]
pub unsafe extern "C" fn jj_is_jj_workspace(path: *const c_char) -> bool {
    if path.is_null() {
        return false;
    }

    let c_str = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    let workspace_root = PathBuf::from(c_str);
    workspace_root.join(".jj").exists()
}

// Memory management functions

/// Free a workspace handle
#[no_mangle]
pub unsafe extern "C" fn jj_workspace_free(workspace: *mut JjWorkspace) {
    if !workspace.is_null() {
        let _ = Box::from_raw(workspace);
    }
}

/// Free a commit info structure
#[no_mangle]
pub unsafe extern "C" fn jj_commit_info_free(commit: *mut JjCommitInfo) {
    if !commit.is_null() {
        let c = Box::from_raw(commit);
        if !c.id.is_null() {
            let _ = CString::from_raw(c.id);
        }
        if !c.change_id.is_null() {
            let _ = CString::from_raw(c.change_id);
        }
        if !c.description.is_null() {
            let _ = CString::from_raw(c.description);
        }
        if !c.author_name.is_null() {
            let _ = CString::from_raw(c.author_name);
        }
        if !c.author_email.is_null() {
            let _ = CString::from_raw(c.author_email);
        }
        if !c.committer_name.is_null() {
            let _ = CString::from_raw(c.committer_name);
        }
        if !c.committer_email.is_null() {
            let _ = CString::from_raw(c.committer_email);
        }
        if !c.parent_ids.is_null() {
            let parent_ids = Box::from_raw(std::slice::from_raw_parts_mut(c.parent_ids, c.parent_ids_len));
            for ptr in parent_ids.iter() {
                if !ptr.is_null() {
                    let _ = CString::from_raw(*ptr);
                }
            }
        }
    }
}

/// Free a bookmark info structure
#[no_mangle]
pub unsafe extern "C" fn jj_bookmark_info_free(bookmark: *mut JjBookmarkInfo) {
    if !bookmark.is_null() {
        let b = Box::from_raw(bookmark);
        if !b.name.is_null() {
            let _ = CString::from_raw(b.name);
        }
        if !b.target_id.is_null() {
            let _ = CString::from_raw(b.target_id);
        }
    }
}

/// Free an operation info structure
#[no_mangle]
pub unsafe extern "C" fn jj_operation_info_free(operation: *mut JjOperationInfo) {
    if !operation.is_null() {
        let o = Box::from_raw(operation);
        if !o.id.is_null() {
            let _ = CString::from_raw(o.id);
        }
        if !o.description.is_null() {
            let _ = CString::from_raw(o.description);
        }
    }
}

/// Free a C string
#[no_mangle]
pub unsafe extern "C" fn jj_string_free(s: *mut c_char) {
    if !s.is_null() {
        let _ = CString::from_raw(s);
    }
}

/// Free a string array
#[no_mangle]
pub unsafe extern "C" fn jj_string_array_free(strings: *mut *mut c_char, len: usize) {
    if !strings.is_null() {
        let arr = Box::from_raw(std::slice::from_raw_parts_mut(strings, len));
        for ptr in arr.iter() {
            if !ptr.is_null() {
                let _ = CString::from_raw(*ptr);
            }
        }
    }
}

/// Free a bookmark array
#[no_mangle]
pub unsafe extern "C" fn jj_bookmark_array_free(bookmarks: *mut JjBookmarkInfo, len: usize) {
    if !bookmarks.is_null() {
        let mut arr = Box::from_raw(std::slice::from_raw_parts_mut(bookmarks, len));
        for bookmark in arr.iter_mut() {
            if !bookmark.name.is_null() {
                let _ = CString::from_raw(bookmark.name);
            }
            if !bookmark.target_id.is_null() {
                let _ = CString::from_raw(bookmark.target_id);
            }
        }
    }
}

/// Free a commit array
#[no_mangle]
pub unsafe extern "C" fn jj_commit_array_free(commits: *mut *mut JjCommitInfo, len: usize) {
    if !commits.is_null() {
        let arr = Box::from_raw(std::slice::from_raw_parts_mut(commits, len));
        for ptr in arr.iter() {
            if !ptr.is_null() {
                jj_commit_info_free(*ptr);
            }
        }
    }
}

/// Free a tree hash result
#[no_mangle]
pub unsafe extern "C" fn jj_free_tree_hash(result: JjTreeHash) {
    if !result.hash.is_null() {
        let _ = CString::from_raw(result.hash);
    }
    if !result.error_message.is_null() {
        let _ = CString::from_raw(result.error_message);
    }
}
