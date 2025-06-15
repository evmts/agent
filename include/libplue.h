#ifndef LIBPLUE_H
#define LIBPLUE_H

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

#ifdef __cplusplus
}
#endif

#endif // LIBPLUE_H