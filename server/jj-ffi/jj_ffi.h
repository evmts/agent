#ifndef JJ_FFI_H
#define JJ_FFI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque workspace handle
typedef struct JjWorkspace JjWorkspace;

// Commit info structure
typedef struct JjCommitInfo {
    char* id;
    char* change_id;
    char* description;
    char* author_name;
    char* author_email;
    int64_t author_timestamp;
    char* committer_name;
    char* committer_email;
    int64_t committer_timestamp;
    char** parent_ids;
    size_t parent_ids_len;
    bool is_empty;
} JjCommitInfo;

// Bookmark info structure
typedef struct JjBookmarkInfo {
    char* name;
    char* target_id; // nullable
    bool is_local;
} JjBookmarkInfo;

// Operation info structure
typedef struct JjOperationInfo {
    char* id;
    char* description;
    int64_t timestamp;
} JjOperationInfo;

// Result structures
typedef struct JjResult {
    bool success;
    char* error_message;
} JjResult;

typedef struct JjWorkspaceResult {
    JjWorkspace* workspace;
    bool success;
    char* error_message;
} JjWorkspaceResult;

typedef struct JjCommitInfoResult {
    JjCommitInfo* commit;
    bool success;
    char* error_message;
} JjCommitInfoResult;

typedef struct JjBookmarkArrayResult {
    JjBookmarkInfo* bookmarks;
    size_t len;
    bool success;
    char* error_message;
} JjBookmarkArrayResult;

typedef struct JjCommitArrayResult {
    JjCommitInfo** commits;
    size_t len;
    bool success;
    char* error_message;
} JjCommitArrayResult;

typedef struct JjStringArrayResult {
    char** strings;
    size_t len;
    bool success;
    char* error_message;
} JjStringArrayResult;

typedef struct JjStringResult {
    char* string;
    bool success;
    char* error_message;
} JjStringResult;

typedef struct JjOperationInfoResult {
    JjOperationInfo* operation;
    bool success;
    char* error_message;
} JjOperationInfoResult;

// Core functions

/**
 * Initialize a new jj workspace at the given path
 * @param path Path where to create the workspace
 * @return Result containing workspace handle or error
 */
JjWorkspaceResult jj_workspace_init(const char* path);

/**
 * Open an existing jj workspace
 * @param path Path to the workspace root
 * @return Result containing workspace handle or error
 */
JjWorkspaceResult jj_workspace_open(const char* path);

/**
 * Initialize a jj workspace from an existing git repository
 * @param path Path to the git repository
 * @return Result containing workspace handle or error
 */
JjWorkspaceResult jj_workspace_init_colocated(const char* path);

/**
 * Get commit information by commit ID
 * @param workspace Workspace handle
 * @param commit_id Hex-encoded commit ID
 * @return Result containing commit info or error
 */
JjCommitInfoResult jj_get_commit(const JjWorkspace* workspace, const char* commit_id);

/**
 * List all bookmarks in the workspace
 * @param workspace Workspace handle
 * @return Result containing array of bookmarks or error
 */
JjBookmarkArrayResult jj_list_bookmarks(const JjWorkspace* workspace);

/**
 * List recent changes/commits
 * @param workspace Workspace handle
 * @param limit Maximum number of commits to return
 * @param bookmark Optional bookmark name to start from (can be NULL)
 * @return Result containing array of commits or error
 */
JjCommitArrayResult jj_list_changes(const JjWorkspace* workspace, uint32_t limit, const char* bookmark);

/**
 * List all files at a specific revision
 * @param workspace Workspace handle
 * @param revision Commit ID or bookmark name
 * @return Result containing array of file paths or error
 */
JjStringArrayResult jj_list_files(const JjWorkspace* workspace, const char* revision);

/**
 * Get file content at a specific revision
 * @param workspace Workspace handle
 * @param revision Commit ID or bookmark name
 * @param path File path within the repository
 * @return Result containing file content or error
 */
JjStringResult jj_get_file_content(const JjWorkspace* workspace, const char* revision, const char* path);

/**
 * Get the current operation info
 * @param workspace Workspace handle
 * @return Result containing operation info or error
 */
JjOperationInfoResult jj_get_current_operation(const JjWorkspace* workspace);

/**
 * Check if a path contains a jj workspace
 * @param path Path to check
 * @return true if the path contains a .jj directory
 */
bool jj_is_jj_workspace(const char* path);

// Memory management functions

/**
 * Free a workspace handle
 * @param workspace Workspace to free
 */
void jj_workspace_free(JjWorkspace* workspace);

/**
 * Free a commit info structure
 * @param commit Commit info to free
 */
void jj_commit_info_free(JjCommitInfo* commit);

/**
 * Free a bookmark info structure
 * @param bookmark Bookmark info to free
 */
void jj_bookmark_info_free(JjBookmarkInfo* bookmark);

/**
 * Free an operation info structure
 * @param operation Operation info to free
 */
void jj_operation_info_free(JjOperationInfo* operation);

/**
 * Free a C string
 * @param s String to free
 */
void jj_string_free(char* s);

/**
 * Free a string array
 * @param strings Array of strings to free
 * @param len Length of the array
 */
void jj_string_array_free(char** strings, size_t len);

/**
 * Free a bookmark array
 * @param bookmarks Array of bookmarks to free
 * @param len Length of the array
 */
void jj_bookmark_array_free(JjBookmarkInfo* bookmarks, size_t len);

/**
 * Free a commit array
 * @param commits Array of commits to free
 * @param len Length of the array
 */
void jj_commit_array_free(JjCommitInfo** commits, size_t len);

#ifdef __cplusplus
}
#endif

#endif // JJ_FFI_H
