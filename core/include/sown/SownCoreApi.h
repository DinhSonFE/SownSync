#pragma once
#include <stdint.h>
#ifdef _WIN32
#define SOWN_API __declspec(dllexport)
#else
#define SOWN_API
#endif
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int connected, locked, transport;
  int64_t position_ns;
  double playback_rate, fps;
  uint64_t sequence;
} SownState;

typedef struct {
  uint32_t id;
  int64_t time_ns;
  int64_t warning_ns;
  char department[64];
  char name[192];
  int valid;
} SownCue;

SOWN_API int sown_init(void);
SOWN_API void sown_shutdown(void);
SOWN_API int sown_get_state(SownState* out_state);
SOWN_API int sown_get_current_cue(SownCue* out_cue);
SOWN_API int sown_get_next_cue(SownCue* out_cue, int64_t* countdown_ns);
SOWN_API int sown_get_cue_count(void);
SOWN_API int sown_is_reaper_connected(void);
SOWN_API const char* sown_get_project_name(void);
SOWN_API const char* sown_get_active_source(void);
SOWN_API const char* sown_version(void);

#ifdef __cplusplus
}
#endif
