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

#ifdef __cplusplus
}
#endif

#endif // LIBPLUE_H