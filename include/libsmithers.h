
//
// libsmithers C API — THE Zig↔Swift contract
//
// Canonical sync points (keep signatures and enums in lockstep):
//   - src/capi.zig     (Zig extern types mirroring this header, comptime sync check)
//   - src/action.zig   (action tags + payload shapes)
//   - src/lib.zig      (C API export functions)
//
// This header follows the libghostty C API conventions.
//
#ifndef LIBSMITHERS_H
#define LIBSMITHERS_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

//-------------------------------------------------------------------
// Opaque types (Swift never sees internals)
//-------------------------------------------------------------------
typedef struct smithers_app_s* smithers_app_t;         // App handle
typedef struct smithers_surface_s* smithers_surface_t; // Per-workspace surface (reserved)

//-------------------------------------------------------------------
// Shared ABI types
//-------------------------------------------------------------------
typedef struct smithers_string_s { // pointer + length (no NUL contract)
    const uint8_t* ptr;
    size_t len;
} smithers_string_s;

//-------------------------------------------------------------------
// Action and Event tags (unified enum; actions = host→Zig, events = Zig→host).
// Keep action values in sync with Zig action.Tag. Events are appended.
//-------------------------------------------------------------------
typedef enum smithers_action_tag_e {
    SMITHERS_ACTION_CHAT_SEND = 0,
    SMITHERS_ACTION_WORKSPACE_OPEN = 1,
    SMITHERS_ACTION_WORKSPACE_CLOSE = 2,
    SMITHERS_ACTION_AGENT_SPAWN = 3,
    SMITHERS_ACTION_AGENT_CANCEL = 4,
    SMITHERS_ACTION_FILE_SAVE = 5,
    SMITHERS_ACTION_FILE_OPEN = 6,
    SMITHERS_ACTION_SEARCH = 7,
    SMITHERS_ACTION_JJ_COMMIT = 8,
    SMITHERS_ACTION_JJ_UNDO = 9,
    SMITHERS_ACTION_SETTINGS_CHANGE = 10,
    SMITHERS_ACTION_SUGGESTION_REFRESH = 11,
    SMITHERS_ACTION_STATUS = 12,
    // --- Events (Zig → host via smithers_action_cb) ---
    // SMITHERS_EVENT_CHAT_DELTA: UTF-8 text chunk streamed during a turn.
    //   - callback payload: data=ptr to bytes, len=byte count
    // SMITHERS_EVENT_TURN_COMPLETE: signals the end of the turn.
    //   - callback payload: data=NULL, len=0
    SMITHERS_EVENT_CHAT_DELTA = 13,
    SMITHERS_EVENT_TURN_COMPLETE = 14,
} smithers_action_tag_e;

//-------------------------------------------------------------------
// Callbacks
//-------------------------------------------------------------------
typedef void (*smithers_wakeup_cb)(void* userdata);
typedef void (*smithers_action_cb)(void* userdata,
                                   smithers_action_tag_e tag,
                                   const void* data,
                                   size_t len);

//-------------------------------------------------------------------
// Runtime & App config
//-------------------------------------------------------------------
typedef struct smithers_runtime_config_s {
    smithers_wakeup_cb wakeup;   // optional
    smithers_action_cb action;   // optional
    void* userdata;              // passthrough to callbacks
} smithers_runtime_config_s;

typedef struct smithers_config_s {
    smithers_runtime_config_s runtime; // required
} smithers_config_s;

//-------------------------------------------------------------------
// Payload union (C ABI)
// Note: Events use the raw (data,len) params of smithers_action_cb and do not
// require entries in this union. The union is defined for actions only.
//-------------------------------------------------------------------
typedef union smithers_action_payload_u {
    // string payloads
    smithers_string_s chat_send;       // message text
    smithers_string_s workspace_open;  // path
    smithers_string_s agent_spawn;     // task description
    smithers_string_s search;          // query
    smithers_string_s jj_commit;       // description

    // complex
    struct { smithers_string_s path; uint32_t line; uint32_t column; } file_open;
    struct { smithers_string_s path; smithers_string_s content; } file_save;
    struct { smithers_string_s key; smithers_string_s value; } settings_change;

    // integral/void-like (explicit pad to avoid zero-size issues)
    struct { uint64_t id; } agent_cancel;
    struct { uint8_t _pad; } workspace_close;
    struct { uint8_t _pad; } jj_undo;
    struct { uint8_t _pad; } suggestion_refresh;
    struct { uint8_t _pad; } status;
} smithers_action_payload_u;

//-------------------------------------------------------------------
// Lifecycle & dispatch
//-------------------------------------------------------------------
smithers_app_t smithers_app_new(const smithers_config_s* config);
void smithers_app_free(smithers_app_t app);
void smithers_app_action(smithers_app_t app, smithers_action_tag_e tag, smithers_action_payload_u payload);

#ifdef __cplusplus
}
#endif
#endif // LIBSMITHERS_H
