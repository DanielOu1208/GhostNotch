#include "GhosttyVTBridge.h"

#include <stdlib.h>
#include <string.h>
#include <ghostty/vt.h>

struct GNVTTerminal {
    GhosttyTerminal terminal;
    GhosttyRenderState renderState;
    GhosttyRenderStateRowIterator rowIterator;
    GhosttyRenderStateRowCells rowCells;
    GhosttyKeyEncoder keyEncoder;
    GhosttyMouseEncoder mouseEncoder;
    GNVTWriteCallback writeCallback;
    void *userdata;
    uint16_t columns;
    uint16_t rows;
    uint32_t cellWidth;
    uint32_t cellHeight;
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

static GNVTColor GNVTColorFromPaletteIndex(GhosttyColorPaletteIndex index) {
    if (index < 16) {
        return GNVTAnsiPalette16[index];
    }

    if (index < 232) {
        int cubeIndex = index - 16;
        return (GNVTColor){
            GNVTXtermColorLevel((cubeIndex / 36) % 6),
            GNVTXtermColorLevel((cubeIndex / 6) % 6),
            GNVTXtermColorLevel(cubeIndex % 6),
        };
    }

    uint8_t value = (uint8_t)(8 + ((index - 232) * 10));
    return (GNVTColor){value, value, value};
}

static bool GNVTColorFromStyleColor(GhosttyStyleColor color, GNVTColor *result) {
    if (result == NULL) {
        return false;
    }

    switch (color.tag) {
        case GHOSTTY_STYLE_COLOR_RGB:
            *result = GNVTColorFromGhostty(color.value.rgb);
            return true;
        case GHOSTTY_STYLE_COLOR_PALETTE:
            *result = GNVTColorFromPaletteIndex(color.value.palette);
            return true;
        case GHOSTTY_STYLE_COLOR_NONE:
        default:
            return false;
    }
}

static GNVTCellWidthRole GNVTWidthRoleFromGhosttyWide(GhosttyCellWide wide) {
    switch (wide) {
        case GHOSTTY_CELL_WIDE_WIDE:
            return GNVT_CELL_WIDTH_WIDE_HEAD;
        case GHOSTTY_CELL_WIDE_SPACER_TAIL:
            return GNVT_CELL_WIDTH_WIDE_SPACER_TAIL;
        case GHOSTTY_CELL_WIDE_SPACER_HEAD:
            return GNVT_CELL_WIDTH_WIDE_SPACER_HEAD;
        case GHOSTTY_CELL_WIDE_NARROW:
        default:
            return GNVT_CELL_WIDTH_NARROW;
    }
}

static void GNVTResetCell(GNVTCell *cell) {
    cell->graphemeStart = 0;
    cell->graphemeLength = 0;
    cell->widthRole = GNVT_CELL_WIDTH_NARROW;
    cell->foreground = GNVTDefaultForeground;
    cell->background = GNVTDefaultBackground;
    cell->underlineColor = GNVTDefaultForeground;
    cell->bold = false;
    cell->italic = false;
    cell->faint = false;
    cell->blink = false;
    cell->inverse = false;
    cell->invisible = false;
    cell->strikethrough = false;
    cell->overline = false;
    cell->hasUnderlineColor = false;
    cell->underlineStyle = GHOSTTY_SGR_UNDERLINE_NONE;
}

static GhosttyKey GNVTGhosttyKeyFromKey(GNVTKey key) {
    switch (key) {
        case GNVT_KEY_ESCAPE: return GHOSTTY_KEY_ESCAPE;
        case GNVT_KEY_ENTER: return GHOSTTY_KEY_ENTER;
        case GNVT_KEY_TAB: return GHOSTTY_KEY_TAB;
        case GNVT_KEY_BACKSPACE: return GHOSTTY_KEY_BACKSPACE;
        case GNVT_KEY_DELETE: return GHOSTTY_KEY_DELETE;
        case GNVT_KEY_ARROW_UP: return GHOSTTY_KEY_ARROW_UP;
        case GNVT_KEY_ARROW_DOWN: return GHOSTTY_KEY_ARROW_DOWN;
        case GNVT_KEY_ARROW_LEFT: return GHOSTTY_KEY_ARROW_LEFT;
        case GNVT_KEY_ARROW_RIGHT: return GHOSTTY_KEY_ARROW_RIGHT;
        case GNVT_KEY_HOME: return GHOSTTY_KEY_HOME;
        case GNVT_KEY_END: return GHOSTTY_KEY_END;
        case GNVT_KEY_PAGE_UP: return GHOSTTY_KEY_PAGE_UP;
        case GNVT_KEY_PAGE_DOWN: return GHOSTTY_KEY_PAGE_DOWN;
        case GNVT_KEY_SPACE: return GHOSTTY_KEY_SPACE;
        case GNVT_KEY_A: return GHOSTTY_KEY_A;
        case GNVT_KEY_B: return GHOSTTY_KEY_B;
        case GNVT_KEY_C: return GHOSTTY_KEY_C;
        case GNVT_KEY_D: return GHOSTTY_KEY_D;
        case GNVT_KEY_E: return GHOSTTY_KEY_E;
        case GNVT_KEY_F: return GHOSTTY_KEY_F;
        case GNVT_KEY_G: return GHOSTTY_KEY_G;
        case GNVT_KEY_H: return GHOSTTY_KEY_H;
        case GNVT_KEY_I: return GHOSTTY_KEY_I;
        case GNVT_KEY_J: return GHOSTTY_KEY_J;
        case GNVT_KEY_K: return GHOSTTY_KEY_K;
        case GNVT_KEY_L: return GHOSTTY_KEY_L;
        case GNVT_KEY_M: return GHOSTTY_KEY_M;
        case GNVT_KEY_N: return GHOSTTY_KEY_N;
        case GNVT_KEY_O: return GHOSTTY_KEY_O;
        case GNVT_KEY_P: return GHOSTTY_KEY_P;
        case GNVT_KEY_Q: return GHOSTTY_KEY_Q;
        case GNVT_KEY_R: return GHOSTTY_KEY_R;
        case GNVT_KEY_S: return GHOSTTY_KEY_S;
        case GNVT_KEY_T: return GHOSTTY_KEY_T;
        case GNVT_KEY_U: return GHOSTTY_KEY_U;
        case GNVT_KEY_V: return GHOSTTY_KEY_V;
        case GNVT_KEY_W: return GHOSTTY_KEY_W;
        case GNVT_KEY_X: return GHOSTTY_KEY_X;
        case GNVT_KEY_Y: return GHOSTTY_KEY_Y;
        case GNVT_KEY_Z: return GHOSTTY_KEY_Z;
        case GNVT_KEY_F1: return GHOSTTY_KEY_F1;
        case GNVT_KEY_F2: return GHOSTTY_KEY_F2;
        case GNVT_KEY_F3: return GHOSTTY_KEY_F3;
        case GNVT_KEY_F4: return GHOSTTY_KEY_F4;
        case GNVT_KEY_F5: return GHOSTTY_KEY_F5;
        case GNVT_KEY_F6: return GHOSTTY_KEY_F6;
        case GNVT_KEY_F7: return GHOSTTY_KEY_F7;
        case GNVT_KEY_F8: return GHOSTTY_KEY_F8;
        case GNVT_KEY_F9: return GHOSTTY_KEY_F9;
        case GNVT_KEY_F10: return GHOSTTY_KEY_F10;
        case GNVT_KEY_F11: return GHOSTTY_KEY_F11;
        case GNVT_KEY_F12: return GHOSTTY_KEY_F12;
        case GNVT_KEY_UNIDENTIFIED:
        default: return GHOSTTY_KEY_UNIDENTIFIED;
    }
}

static GhosttyMods GNVTGhosttyModsFromMods(uint16_t mods) {
    GhosttyMods result = 0;
    if ((mods & GNVT_MOD_SHIFT) != 0) {
        result |= GHOSTTY_MODS_SHIFT;
    }
    if ((mods & GNVT_MOD_CONTROL) != 0) {
        result |= GHOSTTY_MODS_CTRL;
    }
    if ((mods & GNVT_MOD_OPTION) != 0) {
        result |= GHOSTTY_MODS_ALT;
    }
    if ((mods & GNVT_MOD_COMMAND) != 0) {
        result |= GHOSTTY_MODS_SUPER;
    }
    return result;
}

static GhosttyMouseAction GNVTGhosttyMouseActionFromAction(GNVTMouseAction action) {
    switch (action) {
        case GNVT_MOUSE_ACTION_PRESS: return GHOSTTY_MOUSE_ACTION_PRESS;
        case GNVT_MOUSE_ACTION_RELEASE: return GHOSTTY_MOUSE_ACTION_RELEASE;
        case GNVT_MOUSE_ACTION_MOTION: return GHOSTTY_MOUSE_ACTION_MOTION;
        default: return GHOSTTY_MOUSE_ACTION_MOTION;
    }
}

static GhosttyMouseButton GNVTGhosttyMouseButtonFromButton(GNVTMouseButton button) {
    switch (button) {
        case GNVT_MOUSE_BUTTON_LEFT: return GHOSTTY_MOUSE_BUTTON_LEFT;
        case GNVT_MOUSE_BUTTON_RIGHT: return GHOSTTY_MOUSE_BUTTON_RIGHT;
        case GNVT_MOUSE_BUTTON_MIDDLE: return GHOSTTY_MOUSE_BUTTON_MIDDLE;
        case GNVT_MOUSE_BUTTON_UNKNOWN:
        default: return GHOSTTY_MOUSE_BUTTON_UNKNOWN;
    }
}

static GhosttyMouseEncoderSize GNVTMouseEncoderSize(GNVTTerminal *terminal) {
    uint32_t cellWidth = terminal->cellWidth == 0 ? 1 : terminal->cellWidth;
    uint32_t cellHeight = terminal->cellHeight == 0 ? 1 : terminal->cellHeight;
    return (GhosttyMouseEncoderSize){
        .size = sizeof(GhosttyMouseEncoderSize),
        .screen_width = (uint32_t)terminal->columns * cellWidth,
        .screen_height = (uint32_t)terminal->rows * cellHeight,
        .cell_width = cellWidth,
        .cell_height = cellHeight,
        .padding_top = 0,
        .padding_bottom = 0,
        .padding_right = 0,
        .padding_left = 0,
    };
}

static GhosttyMousePosition GNVTMousePosition(GNVTTerminal *terminal, uint16_t column, uint16_t row) {
    uint32_t cellWidth = terminal->cellWidth == 0 ? 1 : terminal->cellWidth;
    uint32_t cellHeight = terminal->cellHeight == 0 ? 1 : terminal->cellHeight;
    return (GhosttyMousePosition){
        .x = ((float)column + 0.5f) * (float)cellWidth,
        .y = ((float)row + 0.5f) * (float)cellHeight,
    };
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
        ghostty_render_state_row_cells_new(NULL, &wrapper->rowCells) != GHOSTTY_SUCCESS ||
        ghostty_key_encoder_new(NULL, &wrapper->keyEncoder) != GHOSTTY_SUCCESS ||
        ghostty_mouse_encoder_new(NULL, &wrapper->mouseEncoder) != GHOSTTY_SUCCESS) {
        GNVTTerminalDestroy(wrapper);
        return NULL;
    }

    wrapper->writeCallback = writeCallback;
    wrapper->userdata = userdata;
    wrapper->columns = columns;
    wrapper->rows = rows;
    wrapper->cellWidth = 8;
    wrapper->cellHeight = 16;

    GhosttyColorRgb foreground = {GNVTDefaultForeground.red, GNVTDefaultForeground.green, GNVTDefaultForeground.blue};
    GhosttyColorRgb background = {GNVTDefaultBackground.red, GNVTDefaultBackground.green, GNVTDefaultBackground.blue};
    GhosttyColorRgb cursor = {GNVTDefaultCursor.red, GNVTDefaultCursor.green, GNVTDefaultCursor.blue};
    GhosttyColorRgb palette[256];
    GNVTBuildColorPalette(palette);
    // Palette, device attributes, scrollback, and option-as-alt are GhostNotch
    // policy choices around the vendored libghostty-vt boundary.
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &foreground);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &background);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &cursor);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, &palette);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_USERDATA, wrapper);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, (const void *)GNVTWritePty);
    ghostty_terminal_set(wrapper->terminal, GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES, (const void *)GNVTDeviceAttributes);
    GhosttyOptionAsAlt optionAsAlt = GHOSTTY_OPTION_AS_ALT_TRUE;
    ghostty_key_encoder_setopt(wrapper->keyEncoder,
                               GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
                               &optionAsAlt);

    return wrapper;
}

void GNVTTerminalDestroy(GNVTTerminal *terminal) {
    if (terminal == NULL) {
        return;
    }

    ghostty_mouse_encoder_free(terminal->mouseEncoder);
    ghostty_key_encoder_free(terminal->keyEncoder);
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
    terminal->columns = columns;
    terminal->rows = rows;
    terminal->cellWidth = cellWidth;
    terminal->cellHeight = cellHeight;
}

bool GNVTTerminalSnapshot(GNVTTerminal *terminal,
                          GNVTCell *cells,
                          size_t cellCount,
                          uint32_t *graphemes,
                          size_t graphemeCapacity,
                          bool *dirtyRows,
                          size_t dirtyRowCount,
                          size_t *requiredGraphemeCount,
                          GNVTSnapshotMeta *meta) {
    if (terminal == NULL || terminal->terminal == NULL || terminal->renderState == NULL || cells == NULL || requiredGraphemeCount == NULL || meta == NULL) {
        return false;
    }
    if (graphemeCapacity > 0 && graphemes == NULL) {
        return false;
    }
    if (dirtyRowCount > 0 && dirtyRows == NULL) {
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
    bool cursorBlinking = false;
    bool hasCursorPosition = false;
    bool hasMouseTracking = false;
    bool bracketedPasteMode = false;
    bool focusEventMode = false;
    size_t totalRows = 0;
    size_t scrollbackRows = 0;
    GhosttyTerminalScrollbar scrollbar = {0};
    GhosttyString title = {0};
    GhosttyString pwd = {0};
    GhosttyRenderStateCursorVisualStyle cursorStyle = GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR;
    GhosttyRenderStateDirty dirtyState = GHOSTTY_RENDER_STATE_DIRTY_FULL;
    GhosttyTerminalScreen activeScreen = GHOSTTY_TERMINAL_SCREEN_PRIMARY;

    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_COLS, &columns);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_ROWS, &rows);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_DIRTY, &dirtyState);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &cursorVisible);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_BLINKING, &cursorBlinking);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE, &cursorStyle);
    ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &hasCursorPosition);
    if (hasCursorPosition) {
        ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cursorColumn);
        ghostty_render_state_get(terminal->renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &cursorRow);
    }
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &activeScreen);
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &hasMouseTracking);
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &totalRows);
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, &scrollbackRows);
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_SCROLLBAR, &scrollbar);
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_TITLE, &title);
    ghostty_terminal_get(terminal->terminal, GHOSTTY_TERMINAL_DATA_PWD, &pwd);
    ghostty_terminal_mode_get(terminal->terminal, GHOSTTY_MODE_BRACKETED_PASTE, &bracketedPasteMode);
    ghostty_terminal_mode_get(terminal->terminal, GHOSTTY_MODE_FOCUS_EVENT, &focusEventMode);

    size_t required = (size_t)columns * (size_t)rows;
    if (cellCount < required) {
        return false;
    }
    if (dirtyRowCount < rows) {
        return false;
    }

    bool didOverflowGraphemes = false;
    size_t usedGraphemes = 0;
    *requiredGraphemeCount = 0;
    for (size_t index = 0; index < dirtyRowCount; index += 1) {
        dirtyRows[index] = dirtyState == GHOSTTY_RENDER_STATE_DIRTY_FULL;
    }

    for (size_t index = 0; index < required; index += 1) {
        GNVTResetCell(&cells[index]);
    }

    if (ghostty_render_state_get(terminal->renderState,
                                 GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                                 &terminal->rowIterator) != GHOSTTY_SUCCESS) {
        return false;
    }

    uint16_t row = 0;
    while (row < rows && ghostty_render_state_row_iterator_next(terminal->rowIterator)) {
        bool isDirtyRow = dirtyState == GHOSTTY_RENDER_STATE_DIRTY_FULL;
        if (dirtyState == GHOSTTY_RENDER_STATE_DIRTY_PARTIAL) {
            ghostty_render_state_row_get(terminal->rowIterator,
                                         GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY,
                                         &isDirtyRow);
        }
        dirtyRows[row] = isDirtyRow;

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
            GhosttyCell rawCell = 0;

            if (ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW,
                                                   &rawCell) == GHOSTTY_SUCCESS) {
                GhosttyCellWide wide = GHOSTTY_CELL_WIDE_NARROW;
                if (ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_WIDE, &wide) == GHOSTTY_SUCCESS) {
                    cell->widthRole = GNVTWidthRoleFromGhosttyWide(wide);
                }
            }

            if (ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
                                                   &graphemeLen) == GHOSTTY_SUCCESS &&
                graphemeLen > 0) {
                cell->graphemeStart = usedGraphemes;
                cell->graphemeLength = graphemeLen;
                *requiredGraphemeCount += graphemeLen;
                if (usedGraphemes + graphemeLen <= graphemeCapacity) {
                    ghostty_render_state_row_cells_get(terminal->rowCells,
                                                       GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                                                       &graphemes[usedGraphemes]);
                } else {
                    didOverflowGraphemes = true;
                }
                usedGraphemes += graphemeLen;
            }

            if (ghostty_render_state_row_cells_get(terminal->rowCells,
                                                   GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
                                                   &style) == GHOSTTY_SUCCESS) {
                cell->bold = style.bold;
                cell->italic = style.italic;
                cell->faint = style.faint;
                cell->blink = style.blink;
                cell->inverse = style.inverse;
                cell->invisible = style.invisible;
                cell->strikethrough = style.strikethrough;
                cell->overline = style.overline;
                cell->underlineStyle = style.underline;
                cell->hasUnderlineColor = GNVTColorFromStyleColor(style.underline_color, &cell->underlineColor);
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

        bool clean = false;
        ghostty_render_state_row_set(terminal->rowIterator,
                                     GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY,
                                     &clean);
        row += 1;
    }

    meta->columns = columns;
    meta->rows = rows;
    meta->cursorColumn = cursorColumn;
    meta->cursorRow = cursorRow;
    meta->cursorVisible = cursorVisible && hasCursorPosition;
    meta->cursorBlinking = cursorBlinking;
    meta->cursorStyle = (uint8_t)cursorStyle;
    meta->isAlternateScreen = activeScreen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE;
    meta->hasMouseTracking = hasMouseTracking;
    meta->bracketedPasteMode = bracketedPasteMode;
    meta->focusEventMode = focusEventMode;
    meta->totalRows = totalRows;
    meta->scrollbackRows = scrollbackRows;
    meta->viewportAtBottom = scrollbar.offset + scrollbar.len >= scrollbar.total;
    meta->title = title.ptr;
    meta->titleLen = title.len;
    meta->pwd = pwd.ptr;
    meta->pwdLen = pwd.len;
    meta->dirtyState = (uint8_t)dirtyState;

    if (didOverflowGraphemes) {
        return false;
    }

    GhosttyRenderStateDirty cleanDirtyState = GHOSTTY_RENDER_STATE_DIRTY_FALSE;
    ghostty_render_state_set(terminal->renderState,
                             GHOSTTY_RENDER_STATE_OPTION_DIRTY,
                             &cleanDirtyState);
    return true;
}

bool GNVTTerminalActiveAreaSnapshot(GNVTTerminal *terminal,
                                    GNVTCell *cells,
                                    size_t cellCount,
                                    uint32_t *graphemes,
                                    size_t graphemeCapacity,
                                    size_t *requiredGraphemeCount) {
    if (terminal == NULL || terminal->terminal == NULL || cells == NULL || requiredGraphemeCount == NULL) {
        return false;
    }
    if (graphemeCapacity > 0 && graphemes == NULL) {
        return false;
    }

    size_t requiredCells = (size_t)terminal->columns * (size_t)terminal->rows;
    if (cellCount < requiredCells) {
        return false;
    }

    bool overflow = false;
    size_t usedGraphemes = 0;
    *requiredGraphemeCount = 0;

    for (uint16_t row = 0; row < terminal->rows; row += 1) {
        for (uint16_t column = 0; column < terminal->columns; column += 1) {
            size_t index = (size_t)row * (size_t)terminal->columns + (size_t)column;
            GNVTCell *cell = &cells[index];
            GNVTResetCell(cell);

            GhosttyPoint point = {0};
            point.tag = GHOSTTY_POINT_TAG_ACTIVE;
            point.value.coordinate.x = column;
            point.value.coordinate.y = row;
            GhosttyGridRef ref = GHOSTTY_INIT_SIZED(GhosttyGridRef);
            if (ghostty_terminal_grid_ref(terminal->terminal, point, &ref) != GHOSTTY_SUCCESS) {
                continue;
            }

            GhosttyCell rawCell = 0;
            if (ghostty_grid_ref_cell(&ref, &rawCell) == GHOSTTY_SUCCESS) {
                GhosttyCellWide wide = GHOSTTY_CELL_WIDE_NARROW;
                if (ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_WIDE, &wide) == GHOSTTY_SUCCESS) {
                    cell->widthRole = GNVTWidthRoleFromGhosttyWide(wide);
                }
            }

            size_t graphemeLength = 0;
            GhosttyResult result = ghostty_grid_ref_graphemes(&ref, NULL, 0, &graphemeLength);
            if (result != GHOSTTY_SUCCESS && result != GHOSTTY_OUT_OF_SPACE) {
                continue;
            }
            if (graphemeLength > UINT32_MAX) {
                return false;
            }

            cell->graphemeStart = usedGraphemes;
            cell->graphemeLength = (uint32_t)graphemeLength;
            *requiredGraphemeCount += graphemeLength;
            if (graphemeLength == 0) {
                continue;
            }

            if (usedGraphemes + graphemeLength <= graphemeCapacity) {
                if (ghostty_grid_ref_graphemes(
                        &ref,
                        &graphemes[usedGraphemes],
                        graphemeLength,
                        &graphemeLength) != GHOSTTY_SUCCESS) {
                    return false;
                }
            } else {
                overflow = true;
            }
            usedGraphemes += graphemeLength;
        }
    }

    return !overflow;
}

void GNVTTerminalScrollViewport(GNVTTerminal *terminal, intptr_t deltaRows) {
    if (terminal == NULL || terminal->terminal == NULL || deltaRows == 0) {
        return;
    }

    GhosttyTerminalScrollViewport scroll = {
        .tag = GHOSTTY_SCROLL_VIEWPORT_DELTA,
        .value = {.delta = deltaRows},
    };
    ghostty_terminal_scroll_viewport(terminal->terminal, scroll);
}

bool GNVTTerminalEncodeKey(GNVTTerminal *terminal,
                           GNVTKey key,
                           uint16_t mods,
                           const char *utf8,
                           size_t utf8Len,
                           bool isRepeat,
                           char *output,
                           size_t outputLen,
                           size_t *written) {
    if (terminal == NULL || terminal->terminal == NULL || terminal->keyEncoder == NULL || written == NULL) {
        return false;
    }

    GhosttyKeyEvent event = NULL;
    if (ghostty_key_event_new(NULL, &event) != GHOSTTY_SUCCESS) {
        return false;
    }

    ghostty_key_event_set_action(event, isRepeat ? GHOSTTY_KEY_ACTION_REPEAT : GHOSTTY_KEY_ACTION_PRESS);
    ghostty_key_event_set_key(event, GNVTGhosttyKeyFromKey(key));
    ghostty_key_event_set_mods(event, GNVTGhosttyModsFromMods(mods));
    if (utf8 != NULL && utf8Len > 0) {
        ghostty_key_event_set_utf8(event, utf8, utf8Len);
    }

    ghostty_key_encoder_setopt_from_terminal(terminal->keyEncoder, terminal->terminal);
    GhosttyOptionAsAlt optionAsAlt = GHOSTTY_OPTION_AS_ALT_TRUE;
    ghostty_key_encoder_setopt(terminal->keyEncoder,
                               GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
                               &optionAsAlt);

    GhosttyResult result = ghostty_key_encoder_encode(terminal->keyEncoder,
                                                      event,
                                                      output,
                                                      outputLen,
                                                      written);
    ghostty_key_event_free(event);
    return result == GHOSTTY_SUCCESS;
}

bool GNVTTerminalEncodeMouseWheel(GNVTTerminal *terminal,
                                  uint16_t column,
                                  uint16_t row,
                                  intptr_t deltaRows,
                                  char *output,
                                  size_t outputLen,
                                  size_t *written) {
    if (terminal == NULL || terminal->terminal == NULL || terminal->mouseEncoder == NULL || written == NULL || deltaRows == 0) {
        return false;
    }

    GhosttyMouseEvent event = NULL;
    if (ghostty_mouse_event_new(NULL, &event) != GHOSTTY_SUCCESS) {
        return false;
    }

    GhosttyMouseEncoderSize size = GNVTMouseEncoderSize(terminal);
    GhosttyMousePosition position = GNVTMousePosition(terminal, column, row);
    GhosttyMouseButton button = deltaRows < 0 ? GHOSTTY_MOUSE_BUTTON_FOUR : GHOSTTY_MOUSE_BUTTON_FIVE;

    ghostty_mouse_encoder_setopt_from_terminal(terminal->mouseEncoder, terminal->terminal);
    ghostty_mouse_encoder_setopt(terminal->mouseEncoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size);
    ghostty_mouse_event_set_action(event, GHOSTTY_MOUSE_ACTION_PRESS);
    ghostty_mouse_event_set_button(event, button);
    ghostty_mouse_event_set_mods(event, 0);
    ghostty_mouse_event_set_position(event, position);

    GhosttyResult result = ghostty_mouse_encoder_encode(terminal->mouseEncoder,
                                                        event,
                                                        output,
                                                        outputLen,
                                                        written);
    ghostty_mouse_event_free(event);
    return result == GHOSTTY_SUCCESS;
}

bool GNVTTerminalEncodeMouseEvent(GNVTTerminal *terminal,
                                  GNVTMouseAction action,
                                  GNVTMouseButton button,
                                  uint16_t column,
                                  uint16_t row,
                                  uint16_t mods,
                                  bool anyButtonPressed,
                                  char *output,
                                  size_t outputLen,
                                  size_t *written) {
    if (terminal == NULL || terminal->terminal == NULL || terminal->mouseEncoder == NULL || written == NULL) {
        return false;
    }

    GhosttyMouseEvent event = NULL;
    if (ghostty_mouse_event_new(NULL, &event) != GHOSTTY_SUCCESS) {
        return false;
    }

    GhosttyMouseEncoderSize size = GNVTMouseEncoderSize(terminal);
    GhosttyMousePosition position = GNVTMousePosition(terminal, column, row);
    bool anyPressed = anyButtonPressed;

    ghostty_mouse_encoder_setopt_from_terminal(terminal->mouseEncoder, terminal->terminal);
    ghostty_mouse_encoder_setopt(terminal->mouseEncoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size);
    ghostty_mouse_encoder_setopt(terminal->mouseEncoder, GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, &anyPressed);
    ghostty_mouse_event_set_action(event, GNVTGhosttyMouseActionFromAction(action));
    if (button == GNVT_MOUSE_BUTTON_UNKNOWN) {
        ghostty_mouse_event_clear_button(event);
    } else {
        ghostty_mouse_event_set_button(event, GNVTGhosttyMouseButtonFromButton(button));
    }
    ghostty_mouse_event_set_mods(event, GNVTGhosttyModsFromMods(mods));
    ghostty_mouse_event_set_position(event, position);

    GhosttyResult result = ghostty_mouse_encoder_encode(terminal->mouseEncoder,
                                                        event,
                                                        output,
                                                        outputLen,
                                                        written);
    ghostty_mouse_event_free(event);
    return result == GHOSTTY_SUCCESS;
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
