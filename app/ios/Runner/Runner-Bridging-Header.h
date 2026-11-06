#import "GeneratedPluginRegistrant.h"

#include <stdint.h>

// The Rust core, for native code when Dart may not be running (app/rust/src/ios.rs). Each but dsip_init answers NULL,
// or what went wrong as a string freed with dsip_string_free.
void dsip_init(const char *dir, const char *gateway);
char *dsip_wake(void);
char *dsip_set_push(const char *provider, const char *app, const char *token, const char *environment);
/// The next event for CallKit as JSON; NULL when none came in time.
char *dsip_next_call_event(int64_t timeout_ms);
char *dsip_act(const char *json);
void dsip_string_free(char *s);
