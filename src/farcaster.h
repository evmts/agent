#ifndef FARCASTER_H
#define FARCASTER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

// Opaque pointer to Farcaster client
typedef struct FarcasterClient FarcasterClient;

// Client lifecycle
FarcasterClient* fc_client_create(uint64_t fid, const char* private_key_hex);
void fc_client_destroy(FarcasterClient* client);

// Cast operations
const char* fc_post_cast(FarcasterClient* client, const char* text, const char* channel_url);
const char* fc_get_casts_by_channel(FarcasterClient* client, const char* channel_url, uint32_t limit);

// Reaction operations
const char* fc_like_cast(FarcasterClient* client, const char* cast_hash, uint64_t cast_fid);
const char* fc_recast_cast(FarcasterClient* client, const char* cast_hash, uint64_t cast_fid);
const char* fc_unlike_cast(FarcasterClient* client, const char* cast_hash, uint64_t cast_fid);
const char* fc_unrecast_cast(FarcasterClient* client, const char* cast_hash, uint64_t cast_fid);

// Follow operations
const char* fc_follow_user(FarcasterClient* client, uint64_t target_fid);
const char* fc_unfollow_user(FarcasterClient* client, uint64_t target_fid);
const char* fc_get_followers(FarcasterClient* client, uint64_t fid);
const char* fc_get_following(FarcasterClient* client, uint64_t fid);

// User operations
const char* fc_get_user_profile(FarcasterClient* client, uint64_t fid);

// Memory management
void fc_free_string(const char* str);

#ifdef __cplusplus
}
#endif

#endif // FARCASTER_H