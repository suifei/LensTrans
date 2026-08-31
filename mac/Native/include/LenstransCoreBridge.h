#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LenstransCoreBlock {
    const char *text;
    float x;
    float y;
    float width;
    float height;
    float line_height;
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    uint8_t background_red;
    uint8_t background_green;
    uint8_t background_blue;
    float background_variance;
} LenstransCoreBlock;

typedef struct LenstransCoreLayout {
    float x;
    float y;
    float width;
    float height;
    float font_px;
    float line_height_px;
    float margin_px;
    float background_alpha;
    int mode;
    int covers_source;
    int show_source;
    uint8_t text_red;
    uint8_t text_green;
    uint8_t text_blue;
    uint8_t fill_red;
    uint8_t fill_green;
    uint8_t fill_blue;
} LenstransCoreLayout;

enum {
    LT_BOX_HIDDEN = 0,
    LT_BOX_EDITING = 1,
    LT_BOX_WATCHING = 2,
    LT_BOX_TRANSLATING = 3,
    LT_BOX_PAUSED = 4,
};

enum {
    LT_BOX_EVENT_SHOW = 1,
    LT_BOX_EVENT_EDIT = 2,
    LT_BOX_EVENT_WATCH = 3,
    LT_BOX_EVENT_PAUSE = 4,
    LT_BOX_EVENT_HIDE = 5,
    LT_BOX_EVENT_TOGGLE_EDIT = 6,
};

enum {
    LT_ENGINE_AUTO = 0,
    LT_ENGINE_LOCAL = 1,
    LT_ENGINE_CLOUD = 2,
};

enum {
    LT_ENGINE_NONE = 0,
    LT_ENGINE_KIND_LOCAL = 1,
    LT_ENGINE_KIND_CLOUD = 2,
};

enum {
    LT_PRESENT_IMMERSIVE = 0,
    LT_PRESENT_STICKER = 1,
    LT_PRESENT_STICKER_CONTRAST = 2,
};

int lenstrans_core_transition(int state, int event);
int lenstrans_core_route(int preference, int privacy, size_t text_chars,
                         int local_ready, int cloud_ready);
int lenstrans_core_present_mode(float background_variance, int contrast, int render_lock);

int lenstrans_core_layout_block(const LenstransCoreBlock *block, const char *translation,
                                int frame_width, int frame_height, int target_width,
                                int target_height, int contrast, int render_lock,
                                int sticker_alpha, int font_scale, LenstransCoreLayout *out);

int lenstrans_core_build_prompt(const char *text, const char *source_language,
                                const char *target_language, char *out, size_t out_capacity);

#ifdef __cplusplus
}
#endif
