#ifndef GhosttyVTBridge_h
#define GhosttyVTBridge_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct GNVTTerminal GNVTTerminal;

typedef void (*GNVTWriteCallback)(const uint8_t *data, size_t len, void *userdata);

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} GNVTColor;

typedef struct {
    size_t graphemeStart;
    uint32_t graphemeLength;
    uint8_t widthRole;
    GNVTColor foreground;
    GNVTColor background;
    GNVTColor underlineColor;
    bool bold;
    bool italic;
    bool faint;
    bool blink;
    bool inverse;
    bool invisible;
    bool strikethrough;
    bool overline;
    bool hasUnderlineColor;
    int underlineStyle;
} GNVTCell;

typedef struct {
    size_t graphemeStart;
    uint32_t graphemeLength;
    uint8_t widthRole;
} GNVTTextCell;

typedef enum {
    GNVT_CELL_WIDTH_NARROW = 0,
    GNVT_CELL_WIDTH_WIDE_HEAD = 1,
    GNVT_CELL_WIDTH_WIDE_SPACER_TAIL = 2,
    GNVT_CELL_WIDTH_WIDE_SPACER_HEAD = 3,
} GNVTCellWidthRole;

typedef struct {
    uint16_t columns;
    uint16_t rows;
    uint16_t cursorColumn;
    uint16_t cursorRow;
    bool cursorVisible;
    bool cursorBlinking;
    uint8_t cursorStyle;
    bool isAlternateScreen;
    bool hasMouseTracking;
    bool bracketedPasteMode;
    bool focusEventMode;
    size_t totalRows;
    size_t scrollbackRows;
    bool viewportAtBottom;
    const uint8_t *title;
    size_t titleLen;
    uint64_t titleSequence;
    const uint8_t *pwd;
    size_t pwdLen;
    /// Render dirty state: 0 clean, 1 partial, 2 full (see `TerminalRenderDirtyState` in Swift).
    uint8_t dirtyState;
} GNVTSnapshotMeta;

typedef enum {
    GNVT_KEY_UNIDENTIFIED = 0,
    GNVT_KEY_ESCAPE,
    GNVT_KEY_ENTER,
    GNVT_KEY_TAB,
    GNVT_KEY_BACKSPACE,
    GNVT_KEY_DELETE,
    GNVT_KEY_ARROW_UP,
    GNVT_KEY_ARROW_DOWN,
    GNVT_KEY_ARROW_LEFT,
    GNVT_KEY_ARROW_RIGHT,
    GNVT_KEY_HOME,
    GNVT_KEY_END,
    GNVT_KEY_PAGE_UP,
    GNVT_KEY_PAGE_DOWN,
    GNVT_KEY_SPACE,
    GNVT_KEY_A,
    GNVT_KEY_B,
    GNVT_KEY_C,
    GNVT_KEY_D,
    GNVT_KEY_E,
    GNVT_KEY_F,
    GNVT_KEY_G,
    GNVT_KEY_H,
    GNVT_KEY_I,
    GNVT_KEY_J,
    GNVT_KEY_K,
    GNVT_KEY_L,
    GNVT_KEY_M,
    GNVT_KEY_N,
    GNVT_KEY_O,
    GNVT_KEY_P,
    GNVT_KEY_Q,
    GNVT_KEY_R,
    GNVT_KEY_S,
    GNVT_KEY_T,
    GNVT_KEY_U,
    GNVT_KEY_V,
    GNVT_KEY_W,
    GNVT_KEY_X,
    GNVT_KEY_Y,
    GNVT_KEY_Z,
    GNVT_KEY_F1,
    GNVT_KEY_F2,
    GNVT_KEY_F3,
    GNVT_KEY_F4,
    GNVT_KEY_F5,
    GNVT_KEY_F6,
    GNVT_KEY_F7,
    GNVT_KEY_F8,
    GNVT_KEY_F9,
    GNVT_KEY_F10,
    GNVT_KEY_F11,
    GNVT_KEY_F12,
} GNVTKey;

typedef enum {
    GNVT_MOUSE_ACTION_PRESS = 0,
    GNVT_MOUSE_ACTION_RELEASE = 1,
    GNVT_MOUSE_ACTION_MOTION = 2,
} GNVTMouseAction;

typedef enum {
    GNVT_MOUSE_BUTTON_UNKNOWN = 0,
    GNVT_MOUSE_BUTTON_LEFT = 1,
    GNVT_MOUSE_BUTTON_RIGHT = 2,
    GNVT_MOUSE_BUTTON_MIDDLE = 3,
} GNVTMouseButton;

enum {
    GNVT_MOD_SHIFT = 1 << 0,
    GNVT_MOD_CONTROL = 1 << 1,
    GNVT_MOD_OPTION = 1 << 2,
    GNVT_MOD_COMMAND = 1 << 3,
};

GNVTTerminal *GNVTTerminalCreate(uint16_t columns,
                                 uint16_t rows,
                                 GNVTWriteCallback writeCallback,
                                 void *userdata);
void GNVTTerminalDestroy(GNVTTerminal *terminal);
void GNVTTerminalWrite(GNVTTerminal *terminal, const uint8_t *data, size_t len);
void GNVTTerminalResize(GNVTTerminal *terminal,
                        uint16_t columns,
                        uint16_t rows,
                        uint32_t cellWidth,
                        uint32_t cellHeight);
bool GNVTTerminalSnapshot(GNVTTerminal *terminal,
                          GNVTCell *cells,
                          size_t cellCount,
                          uint32_t *graphemes,
                          size_t graphemeCapacity,
                          bool *dirtyRows,
                          size_t dirtyRowCount,
                          size_t *requiredGraphemeCount,
                          GNVTSnapshotMeta *meta);

bool GNVTTerminalActiveAreaTextSnapshot(GNVTTerminal *terminal,
                                        GNVTTextCell *cells,
                                        size_t cellCount,
                                        uint32_t *graphemes,
                                        size_t graphemeCapacity,
                                        size_t *requiredGraphemeCount);
void GNVTTerminalScrollViewport(GNVTTerminal *terminal, intptr_t deltaRows);
bool GNVTTerminalEncodeKey(GNVTTerminal *terminal,
                           GNVTKey key,
                           uint16_t mods,
                           const char *utf8,
                           size_t utf8Len,
                           bool isRepeat,
                           char *output,
                           size_t outputLen,
                           size_t *written);
bool GNVTTerminalEncodeMouseWheel(GNVTTerminal *terminal,
                                  uint16_t column,
                                  uint16_t row,
                                  intptr_t deltaRows,
                                  char *output,
                                  size_t outputLen,
                                  size_t *written);
bool GNVTTerminalEncodeMouseEvent(GNVTTerminal *terminal,
                                  GNVTMouseAction action,
                                  GNVTMouseButton button,
                                  uint16_t column,
                                  uint16_t row,
                                  uint16_t mods,
                                  bool anyButtonPressed,
                                  char *output,
                                  size_t outputLen,
                                  size_t *written);
bool GNVTPasteEncode(char *data,
                     size_t dataLen,
                     bool bracketed,
                     char *output,
                     size_t outputLen,
                     size_t *written);
bool GNVTFocusEncode(bool focused,
                     char *output,
                     size_t outputLen,
                     size_t *written);

#endif
