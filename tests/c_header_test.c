// Minimal C compile test to ensure the public header compiles cleanly
// with typical warning flags and the callback typedefs are usable.
#include "libsmithers.h"

// Verify enum value stability for tooling/tests relying on numeric tags.
_Static_assert(SMITHERS_ACTION_STATUS == 12, "SMITHERS_ACTION_STATUS must equal 12");

static void test_types(void) {
    smithers_app_t app = (smithers_app_t)0;
    smithers_surface_t surface = (smithers_surface_t)0;
    (void)app; (void)surface;

    smithers_action_tag_e tag = SMITHERS_ACTION_CHAT_SEND;
    (void)tag;

    smithers_action_payload_u payload;
    (void)payload;

    smithers_runtime_config_s runtime = (smithers_runtime_config_s){0};
    smithers_config_s config = (smithers_config_s){ .runtime = runtime };
    (void)config;
}

static void test_action_cb_impl(void* userdata, smithers_action_tag_e tag, const void* data, size_t len) {
    (void)userdata; (void)tag; (void)data; (void)len;
}

static void test_callbacks(void) {
    smithers_action_cb cb = test_action_cb_impl;
    (void)cb;
    smithers_wakeup_cb w = (smithers_wakeup_cb)0;
    (void)w;
}

int main(void) {
    test_types();
    test_callbacks();
    return 0;
}
