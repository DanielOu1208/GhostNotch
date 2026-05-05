#include "GhosttyVTBridge.h"

#include <stdlib.h>
#include <string.h>
#include <ghostty/vt.h>

struct GNVTTerminal {
    GhosttyTerminal terminal;
    GhosttyRenderState renderState;
    GhosttyRenderStateRowIterator rowIterator;
    GhosttyRenderStateRowCells rowCells;
    GNVTWriteCallback writeCallback;
    void *userdata;
};

static const GNVTColor GNVTDefaultForeground = {220, 224, 232};
static const GNVTColor GNVTDefaultBackground = {0, 0, 0};
static const GNVTColor GNVTDefaultCursor = {245, 245, 245};

static const GNVTColor GNVTAnsiPalette16[16] = {
    {69, 71, 90},
    {243, 139, 168},
    {166, 227, 161},
    {249, 226, 175},
    {137, 180, 250},
    {245, 194, 231},
    {148, 226, 213},
    {186, 194, 222},
    {88, 91, 112},
    {243, 139, 168},
    {166, 227, 161},
    {249, 226, 175},
    {137, 180, 250},
    {245, 194, 231},
    {148, 226, 213},
    {245, 245, 245},
};

static uint8_t GNVTXtermColorLevel(int index) {
    static const uint8_t levels[6] = {0, 95, 135, 175, 215, 255};
    return levels[index < 0 ? 0 : (index > 5 ? 5 : index)];
}

static void GNVTBuildColorPalette(GhosttyColorRgb palette[256]) {
    for (int index = 0; index < 16; index += 1) {
        palette[index] = (GhosttyColorRgb){
            GNVTAnsiPalette16[index].red,
            GNVTAnsiPalette16[index].green,
            GNVTAnsiPalette16[index].blue,
        };
    }

    for (int index = 16; index < 232; index += 1) {
        int cubeIndex = index - 16;
        palette[index] = (GhosttyColorRgb){
            GNVTXtermColorLevel((cubeIndex / 36) % 6),
            GNVTXtermColorLevel((cubeIndex / 6) % 6),
            GNVTXtermColorLevel(cubeIndex % 6),
        };
    }

    for (int index = 232; index < 256; index += 1) {
        uint8_t value = (uint8_t)(8 + ((index - 232) * 10));
        palette[index] = (GhosttyColorRgb){value, value, value};
    }
}

static GNVTColor GNVTColorFromGhostty(GhosttyColorRgb color) {
    GNVTColor result = {color.r, color.g, color.b};
    return result;
}

static void GNVTWritePty(GhosttyTerminal terminal,
                         void *userdata,
                         const uint8_t *data,
                         size_t len) {
    (void)terminal;
    GNVTTerminal *wrapper = (GNVTTerminal *)userdata;
    if (wrapper == NULL || wrapper->writeCallback == NULL || data == NULL || len == 0) {
        return;
    }

    wrapper->writeCallback(data, len, wrapper->userdata);
}

static bool GNVTDeviceAttributes(GhosttyTerminal terminal,
                                 void *userdata,
                                 GhosttyDeviceAttributes *outAttrs) {
    (void)terminal;
    (void)userdata;
    if (outAttrs == NULL) {
        return false;
    }

    memset(outAttrs, 0, sizeof(*outAttrs));
    outAttrs->primary.conformance_level = GHOSTTY_DA_CONFORMANCE_LEVEL_2;
    outAttrs->primary.features[0] = GHOSTTY_DA_FEATURE_ANSI_COLOR;
    outAttrs->primary.num_features = 1;
    outAttrs->secondary.device_type = GHOSTTY_DA_DEVICE_TYPE_VT220;
    outAttrs->secondary.firmware_version = 0;
    outAttrs->secondary.rom_cartridge = 0;
    outAttrs->tertiary.unit_id = 0;
    return true;
}

GNVTTerminal *GNVTTerminalCreate(uint16_t columns,
                                 uint16_t rows,
                                 GNVTWriteCallback writeCallback,
                                 void *userdata) {
    GNVTTerminal *wrapper = calloc(1, sizeof(GNVTTerminal));
    if (wrapper == NULL) {
        return NULL;
    }

    GhosttyTerminalOptions options = {
        .cols = columns,
        .rows = rows,
        .max_scrollback = 1000,
    };

    if (ghostty_terminal_new(NULL, &wrapper->terminal, options) != GHOSTTY_SUCCESS ||
        ghostty_render_state_new(NULL, &wrapper->renderState) != GHOSTTY_SUCCESS ||
        ghostty_render_state_row_iterator_new(NULL, &wrapper->rowIterator) != GHOSTTY_SUCCESS ||
        ghostty_render_state_row_cells_new(NULL, &wrapper->rowCells) != GHOSTTY_SUCCESS) {
        GNVTTerminalDestroy(wrapper);
        return NULL;
    }

    wrapper->writeCallback = writeCallback;
    wrapper->userdata = userdata;

    GhosttyColorRgb foreground = {GNVTDefaultForeground.red, GNVTDefaultForeground.green, GNVTDefaultForeground.blue};
    GhosttyColorRgb background = {GNVTDefaultBackground.red, GNVTDefaultBackground.green, GNVTDefaultBackground.blue};
    GhosttyColorRgb cursor = {GNVTDefaultCursor.red, GNVTDefaultCursor.green, GNVTDefaultCursor.blue};
    GhosttyColorRgb palette[256];
    GNVTBuildColorPalette(palette);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &foreground);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &background);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cursor);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, &palette);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_USERDATA, wrapper);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, (const void *)GNVTWritePty);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES, (const void *)GNVTDeviceAttributes);

    return wrapper;
}

void GNVTTerminalDestroy(GNVTTerminal *terminal) {
    if (terminal == NULL) {
        return;
    }

    ghostty_render_state_row_cells_free(terminal->rowCells);
    ghostty_render_state_row_iterator_free(terminal->rowIterator);
    ghostty_render_state_free(terminal->renderState);
    ghostty_terminal_free(terminal->terminal);
    free(terminal);
}

void GNVTTerminalWrite(GNVTTerminal *terminal, const uint8_t *data, size_t len) {
    if (terminal == NULL || terminal->terminal == NULL || data == NULL || len == 0) {
        return;
    }

    ghostty_terminal_vt_write(terminal->terminal, data, len);
}

void GNVTTerminalResize(GNVTTerminal *terminal,
                        uint16_t columns,
                        uint16_t rows,
                        uint32_t cellWidth,
                        uint32_t cellHeight) {
    if (terminal == NULL || terminal->terminal == NULL) {
        return;
    }

    ghostty_terminal_resize(terminal->terminal, columns, rows, cellWidth, cellHeight);
}

bool GNVTTerminalSnapshot(GNVTTerminal *terminal,
                          GNVTCell *cells,
                          size_t cellCount,
                          GNVTSnapshotMeta *meta) {
    if (terminal == NULL || terminal->terminal == NULL || terminal->renderState == NULL || cells == NULL || meta == NULL) {
        return false;
    }

    if (ghostty_render_state_update(terminal->renderState, terminal->terminal) != GHOSTTY_SUCCESS) {
        return false;
    }

    uint16_t columns = 0;
    uint16_t rows = 0;
    uint16_t cursorColumn = 0;
    uint16_t cursorRow = 0;
    bool cursorVisible = true;
    bool hasCursorPosition = false;
    GhosttyTerminalScreen activeScreen = GHOSTTY_TERMINAL_SCREEN_PRIMARY;

    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_COLS, &columns);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_ROWS, &rows);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &cursorVisible);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &hasCursorPosition);
    if (hasCursorPosition) {
        ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cursorColumn);
        ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &cursorRow);
    }
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &activeScreen);

    size_t required = (size_t)columns * (size_t)rows;
    if (cellCount < required) {
        return false;
    }

    for (size_t index = 0; index < required; index += 1) {
        cells[index].codepoint = 0;
        cells[index].foreground = GNVTDefaultForeground;
        cells[index].background = GNVTDefaultBackground;
        cells[index].bold = false;
        cells[index].italic = false;
        cells[index].inverse = false;
    }

    if (ghostty_render_state_get(terminal->renderState,
                                 GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                                 &terminal->rowIterator) != GHOSTTY_SUCCESS) {
        return false;
    }

    uint16_t row = 0;
    while (row < rows && ghostty_render_state_row_iterator_next(terminal->rowIterator)) {
        if (ghostty_render_state_row_get(terminal->rowIterator,
                                         GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                                         &terminal->rowCells) != GHOSTTY_SUCCESS) {
            row += 1;
            continue;
        }

        for (uint16_t column = 0; column < columns; column += 1) {
            if (ghostty_render_state_row_cells_select(terminal->rowCells, column) != GHOSTTY_SUCCESS) {
                continue;
            }

            GNVTCell *cell = &cells[(size_t)row * (size_t)columns + (size_t)column];
            uint32_t graphemeLen = 0;
            GhosttyStyle style = GHOSTTY_INIT_SIZED(GhosttyStyle);

            if (ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
                                                   &graphemeLen) == GHOSTTY_SUCCESS &&
                graphemeLen > 0) {
                uint32_t firstCodepoint = 0;
                ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                                                   &firstCodepoint);
                cell->codepoint = firstCodepoint;
            }

            if (ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
                                                   &style) == GHOSTTY_SUCCESS) {
                cell->bold = style.bold;
                cell->italic = style.italic;
                cell->inverse = style.inverse;
            }

            GhosttyColorRgb foreground;
            GhosttyColorRgb background;
            if (ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR,
                                                   &foreground) == GHOSTTY_SUCCESS) {
                cell->foreground = GNVTColorFromGhostty(foreground);
            }
            if (ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR,
                                                   &background) == GHOSTTY_SUCCESS) {
                cell->background = GNVTColorFromGhostty(background);
            }
        }

        row += 1;
    }

    meta->columns = columns;
    meta->rows = rows;
    meta->cursorColumn = cursorColumn;
    meta->cursorRow = cursorRow;
    meta->cursorVisible = cursorVisible && hasCursorPosition;
    meta->isAlternateScreen = activeScreen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE;
    return true;
}

bool GNVTPasteEncode(char *data,
                     size_t dataLen,
                     bool bracketed,
                     char *output,
                     size_t outputLen,
                     size_t *written) {
    return ghostty_paste_encode(data, dataLen, bracketed, output, outputLen, written) == GHOSTTY_SUCCESS;
}

bool GNVTFocusEncode(bool focused,
                     char *output,
                     size_t outputLen,
                     size_t *written) {
    GhosttyFocusEvent event = focused ? GHOSTTY_FOCUS_GAINED : GHOSTTY_FOCUS_LOST;
    return ghostty_focus_encode(event, output, outputLen, written) == GHOSTTY_SUCCESS;
}
