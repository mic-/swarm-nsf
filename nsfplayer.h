#pragma once

#include <stdint.h>
#include "arm_6502.h"
#include "nsfmapper.h"

typedef struct __attribute__ ((__packed__))
{
    char ID[5];
    uint8_t version;
    uint8_t numSongs;
    uint8_t firstSong;		// 1-based
    uint16_t loadAddress;
    uint16_t initAddress;
    uint16_t playAddress;
    char title[32];			// ASCIIZ
    char author[32];		// ...
    char copyright[32];		// ...
    uint16_t ntscSpeedUs;
    uint8_t initialBanks[8];
    uint16_t palSpeedUs;
    uint8_t region;
    uint8_t extraChips;
    uint32_t reserved;
} nsfFileHeader;

enum {
    USES_VRC6 = 0x01,
    USES_VRC7 = 0x02,
    USES_FDS = 0x04,
    USES_MMC5 = 0x08,
    USES_N163 = 0x10,
    USES_SUNSOFT_5B = 0x20,
};

enum {
    NSFPLAYER_REGION_NTSC = 0x00,
    NSFPLAYER_REGION_PAL = 0x01,
    NSFPLAYER_REGION_DUAL = 0x02,
};

void nsfPlayer_init();
void nsfPlayer_prepare(uint8_t *buffer, size_t bufLen);
void nsfPlayer_run(uint32_t numSamples, int8_t *buffer);
void nsfPlayer_reset();
void nsfPlayer_setSubSong(uint32_t subSong);
