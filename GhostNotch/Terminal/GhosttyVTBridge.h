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
    uint32_t codepoint;
    GNVTColor foreground;
    GNVTColor background;
    bool bold;
    bool italic;
    bool inverse;
} GNVTCell;

typedef struct {
    uint16_t columns;
    uint16_t rows;
    uint16_t cursorColumn;
    uint16_t cursorRow;
    bool cursorVisible;
    bool isAlternateScreen;
} GNVTSnapshotMeta;

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
                          GNVTSnapshotMeta *meta);
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
