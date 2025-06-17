#ifndef LIBPLUE_H
#define LIBPLUE_H

#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize the Plue core library.
 * 
 * @return 0 on success, -1 on failure
 */
int plue_init(void);

/**
 * Deinitialize the Plue core library.
 * Cleans up all resources.
 */
void plue_deinit(void);

/**
 * Process a message through the Plue core.
 * 
 * @param message Null-terminated input message string
 * @return Null-terminated response string (must be freed with plue_free_string)
 */
const char* plue_process_message(const char* message);

/**
 * Free a string returned by the Plue library.
 * 
 * @param str String to free (returned by plue_process_message)
 */
void plue_free_string(const char* str);

// Enums matching Zig definitions
typedef enum {
    TabTypePrompt = 0,
    TabTypeFarcaster = 1,
    TabTypeAgent = 2,
    TabTypeTerminal = 3,
    TabTypeWeb = 4,
    TabTypeEditor = 5,
    TabTypeDiff = 6,
    TabTypeWorktree = 7
} TabType;

typedef enum {
    ThemeDark = 0,
    ThemeLight = 1
} Theme;

typedef enum {
    VimModeNormal = 0,
    VimModeInsert = 1,
    VimModeVisual = 2,
    VimModeCommand = 3
} VimMode;

// C-compatible state structs
typedef struct {
    _Bool processing;
    const char* current_content;
    const char* last_message;
} CPromptState;

typedef struct {
    unsigned int rows;
    unsigned int cols;
    const char* content;
    _Bool is_running;
} CTerminalState;

typedef struct {
    _Bool can_go_back;
    _Bool can_go_forward;
    _Bool is_loading;
    const char* current_url;
    const char* page_title;
} CWebState;

typedef struct {
    VimMode mode;
    const char* content;
    unsigned int cursor_row;
    unsigned int cursor_col;
    const char* status_line;
} CVimState;

typedef struct {
    _Bool processing;
    _Bool dagger_connected;
} CAgentState;

typedef struct {
    const char* selected_channel;
    _Bool is_loading;
    _Bool is_posting;
} CFarcasterState;

typedef struct {
    const char* file_path;
    const char* content;
    _Bool is_modified;
} CEditorState;

// Main application state
typedef struct {
    TabType current_tab;
    _Bool is_initialized;
    const char* error_message;
    _Bool openai_available;
    Theme current_theme;
    
    CPromptState prompt;
    CTerminalState terminal;
    CWebState web;
    CVimState vim;
    CAgentState agent;
    CFarcasterState farcaster;
    CEditorState editor;
} CAppState;

/**
 * Get current application state as C struct.
 * 
 * @return Pointer to CAppState (must call plue_free_state when done), or NULL on error
 */
CAppState* plue_get_state(void);

/**
 * Free resources allocated in CAppState.
 * 
 * @param state Pointer to the state struct to free
 */
void plue_free_state(CAppState* state);

/**
 * Process an event with optional JSON data.
 * 
 * @param event_type The event type enum value
 * @param json_data Optional JSON data for the event (can be NULL)
 * @return 0 on success, -1 on failure
 */
int plue_process_event(int event_type, const char* json_data);

// Ghostty Terminal Functions

/**
 * Initialize the Ghostty terminal.
 * 
 * @return 0 on success, negative value on failure
 */
int ghostty_terminal_init(void);

/**
 * Deinitialize the Ghostty terminal.
 * Cleans up all terminal resources.
 */
void ghostty_terminal_deinit(void);

/**
 * Create a new terminal surface.
 * 
 * @return 0 on success, negative value on failure
 */
int ghostty_terminal_create_surface(void);

/**
 * Set the terminal surface size.
 * 
 * @param width Terminal width in pixels
 * @param height Terminal height in pixels
 * @param scale Display scale factor
 */
void ghostty_terminal_set_size(unsigned int width, unsigned int height, double scale);

/**
 * Send key input to the terminal.
 * 
 * @param key Key name (null-terminated string)
 * @param modifiers Modifier keys bitmask
 * @param action Key action (press/release)
 */
void ghostty_terminal_send_key(const char* key, unsigned int modifiers, int action);

/**
 * Write data to the terminal PTY.
 * 
 * @param data Data buffer to write
 * @param len Length of data in bytes
 * @return Number of bytes written
 */
size_t ghostty_terminal_write(const unsigned char* data, size_t len);

/**
 * Read data from the terminal PTY.
 * 
 * @param buffer Buffer to read data into
 * @param buffer_len Maximum bytes to read
 * @return Number of bytes read
 */
size_t ghostty_terminal_read(unsigned char* buffer, size_t buffer_len);

/**
 * Draw/render the terminal surface.
 */
void ghostty_terminal_draw(void);

/**
 * Send text input to the terminal.
 * 
 * @param text Null-terminated text string to send
 */
void ghostty_terminal_send_text(const char* text);

// ============================================================================
// Mini Terminal - Simplified terminal implementation
// ============================================================================

/**
 * Initialize the mini terminal.
 * 
 * @return 0 on success, -1 on failure
 */
int mini_terminal_init(void);

/**
 * Start the terminal process.
 * 
 * @return 0 on success, -1 on failure
 */
int mini_terminal_start(void);

/**
 * Stop the terminal process.
 */
void mini_terminal_stop(void);

/**
 * Write text to the terminal.
 * 
 * @param text Null-terminated text string to write
 * @return 0 on success, -1 on failure
 */
int mini_terminal_write(const char* text);

/**
 * Read output from the terminal.
 * 
 * @param buffer Buffer to read data into
 * @param size Maximum bytes to read
 * @return Number of bytes read
 */
size_t mini_terminal_read(unsigned char* buffer, size_t size);

/**
 * Send a command to the terminal (adds newline).
 * 
 * @param cmd Null-terminated command string
 * @return 0 on success, -1 on failure
 */
int mini_terminal_send_command(const char* cmd);

// ============================================================================
// PTY Terminal - Proper pseudo-terminal implementation
// ============================================================================

/**
 * Initialize the PTY terminal.
 * 
 * @return 0 on success, -1 on failure
 */
int pty_terminal_init(void);

/**
 * Start the PTY terminal with a shell.
 * 
 * @return 0 on success, -1 on failure
 */
int pty_terminal_start(void);

/**
 * Stop the PTY terminal process.
 */
void pty_terminal_stop(void);

/**
 * Write data to the PTY.
 * 
 * @param data Data buffer to write
 * @param len Length of data in bytes
 * @return Number of bytes written, -1 on error
 */
ssize_t pty_terminal_write(const unsigned char* data, size_t len);

/**
 * Read data from the PTY.
 * 
 * @param buffer Buffer to read data into
 * @param buffer_len Maximum bytes to read
 * @return Number of bytes read, 0 if no data, -1 on error
 */
ssize_t pty_terminal_read(unsigned char* buffer, size_t buffer_len);

/**
 * Send text to the PTY (convenience function).
 * 
 * @param text Null-terminated text string to send
 */
void pty_terminal_send_text(const char* text);

/**
 * Resize the PTY.
 * 
 * @param cols Number of columns
 * @param rows Number of rows
 */
void pty_terminal_resize(unsigned short cols, unsigned short rows);

/**
 * Deinitialize the PTY terminal.
 * Cleans up all resources.
 */
void pty_terminal_deinit(void);

// ============================================================================
// macOS PTY - Minimal working PTY for macOS
// ============================================================================

/**
 * Initialize the macOS PTY.
 * 
 * @return 0 on success, -1 on failure
 */
int macos_pty_init(void);

/**
 * Start the macOS PTY with a shell.
 * 
 * @return 0 on success, -1 on failure
 */
int macos_pty_start(void);

/**
 * Stop the macOS PTY process.
 */
void macos_pty_stop(void);

/**
 * Write data to the macOS PTY.
 * 
 * @param data Data buffer to write
 * @param len Length of data in bytes
 * @return Number of bytes written, -1 on error
 */
ssize_t macos_pty_write(const unsigned char* data, size_t len);

/**
 * Read data from the macOS PTY.
 * 
 * @param buffer Buffer to read data into
 * @param buffer_len Maximum bytes to read
 * @return Number of bytes read, 0 if no data, -1 on error
 */
ssize_t macos_pty_read(unsigned char* buffer, size_t buffer_len);

/**
 * Send text to the macOS PTY.
 * 
 * @param text Null-terminated text string to send
 */
void macos_pty_send_text(const char* text);

/**
 * Get the master file descriptor.
 * 
 * @return File descriptor or -1 if not available
 */
int macos_pty_get_fd(void);

/**
 * Resize the macOS PTY.
 * 
 * @param cols Number of columns
 * @param rows Number of rows
 */
void macos_pty_resize(unsigned short cols, unsigned short rows);

/**
 * Deinitialize the macOS PTY.
 * Cleans up all resources.
 */
void macos_pty_deinit(void);

// ============================================================================
// Simple Terminal - Better PTY implementation with proper openpty support
// ============================================================================

/**
 * Initialize the simple terminal.
 * 
 * @return 0 on success, -1 on failure
 */
int simple_terminal_init(void);

/**
 * Start the simple terminal with a shell.
 * 
 * @return 0 on success, -1 on failure
 */
int simple_terminal_start(void);

/**
 * Stop the simple terminal process.
 */
void simple_terminal_stop(void);

/**
 * Write text to the terminal.
 * 
 * @param text Null-terminated text string to write
 * @return 0 on success, -1 on error
 */
int simple_terminal_write(const char* text);

/**
 * Process terminal output (read and buffer).
 * 
 * @return 0 on success, -1 on error
 */
int simple_terminal_process(void);

/**
 * Get buffered terminal output.
 * 
 * @param buffer Buffer to copy output into
 * @param size Maximum bytes to copy
 * @return Number of bytes copied
 */
size_t simple_terminal_get_output(unsigned char* buffer, size_t size);

/**
 * Clear the output buffer.
 */
void simple_terminal_clear(void);

/**
 * Resize the terminal.
 * 
 * @param cols Number of columns
 * @param rows Number of rows
 * @return 0 on success, -1 on error
 */
int simple_terminal_resize(unsigned short cols, unsigned short rows);

#ifdef __cplusplus
}
#endif

#endif // LIBPLUE_H