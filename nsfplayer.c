#include <gba.h>
#include <string.h>
#include <stdio.h>
#include "nsfplayer.h"
#include "arm_apu.h"
#include "common.h"

#define CALLCODE_ADDR 0x3F80

#define BYTESWAP(w) w = (((w) & 0xFF00) >> 8) | (((w) & 0x00FF) << 8)

nsfFileHeader fileHeader;
static bool songIsBankswitched;
static uint32_t frameCycles, cycleCount;
uint32_t playCounter;
extern uint32_t perfcount, cpuemutime;
static uint8_t rom[48 * 1024] __attribute__ ((section (".ewram"))) __attribute__ ((aligned (4)));
uint8_t romBuffer[1024] __attribute__ ((section (".ewram"))) __attribute__ ((aligned (4)));


void nsfPlayer_init()
{
    songIsBankswitched = false;
    apu_init();
}


static void nsfPlayer_execute6502(uint16_t address, uint32_t numCycles)
{
    // JSR loadAddress
    nsfmapper_write_byte(CALLCODE_ADDR+0, 0x20);
    nsfmapper_write_byte(CALLCODE_ADDR+1, address & 0xff);
    nsfmapper_write_byte(CALLCODE_ADDR+2, address >> 8);
    // -: JMP -
    nsfmapper_write_byte(CALLCODE_ADDR+3, 0x4c);
    nsfmapper_write_byte(CALLCODE_ADDR+4, (CALLCODE_ADDR+3)&0xFF);
    nsfmapper_write_byte(CALLCODE_ADDR+5, (CALLCODE_ADDR+3)>>8);
    regPC = CALLCODE_ADDR;
    emu6502_run(numCycles);
}

void nsfPlayer_executePlayRoutine()
{
    uint32_t lstart = REG_VCOUNT;

    nsfPlayer_execute6502(fileHeader.playAddress, frameCycles);

    uint32_t lend = REG_VCOUNT;
    lend = (lend >= lstart) ? (lend - lstart) : (lend + 228 - lstart);
    cpuemutime = (lend > cpuemutime) ? lend : cpuemutime;
}

static void copy_nsf_to_vram(uint8_t *nsfData, uint32_t nsfLen, uint32_t destOffset)
{
    uint8_t *src = rom;
    uint8_t *dest = nsfmapper_get_rom_pointer();
   
    for (int kb = 0; kb < 32; ++kb) {
        if (songIsBankswitched) {
            memcpy(romBuffer, src + fileHeader.initialBanks[kb/4]*4096 + (kb&3)*1024, 1024);
        } else {
            memcpy(romBuffer, src + kb*1024, 1024);
        }
        CpuSet(romBuffer, dest, 1024/2 | COPY16);
        dest += 1024;
    }
}

void nsfPlayer_prepare(uint8_t *buffer, size_t bufLen)
{
    uint32_t  i;
    uint32_t numBanks;

    memcpy((char*)&fileHeader, buffer, sizeof(nsfFileHeader));

    if (strncmp(fileHeader.ID, "NESM", 4)) {
        return;
    }

    songIsBankswitched = false;
    for (i = 0; i < 8; i++) {
        if (fileHeader.initialBanks[i]) {
            songIsBankswitched = true;
            break;
        }
    }

    uint32_t offset = fileHeader.loadAddress & 0x0fff;
    if (!songIsBankswitched) {
        offset = fileHeader.loadAddress - 0x8000;
    }

    numBanks = ((bufLen + offset - sizeof(nsfFileHeader)) + 0xfff) >> 12;
    if (numBanks > 32) {
        return;
    }

    memcpy(rom + offset,
       buffer + sizeof(nsfFileHeader),
       bufLen - sizeof(nsfFileHeader));
           
    copy_nsf_to_vram(buffer + sizeof(nsfFileHeader), bufLen - sizeof(nsfFileHeader), offset);
    
    nsfmapper_reset();
    emu6502_reset();
    
    apu_init();
    apu_reset();
    
    if (fileHeader.region & NSFPLAYER_REGION_PAL) {
        frameCycles = ((1662607 * 256) + 128) / 200;
        apu_set_clock(1662607*256, frameCycles, ((1662607 * 256) + 128)/SAMPLE_RATE, 1);
    } else {
        frameCycles = ((1789773 * 256) + 128) / 240;
        apu_set_clock(1789773*256, frameCycles, ((1789773 * 256) + 128)/SAMPLE_RATE, 0);
    }

    cycleCount = 0;
    playCounter = 0;

    regS = 0xFF;
    nsfPlayer_setSubSong(fileHeader.firstSong - 1);
}


void nsfPlayer_setSubSong(uint32_t subSong)
{
    int i;

    nsfmapper_reset();
    apu_reset();

    if (fileHeader.region & NSFPLAYER_REGION_PAL) {
        frameCycles = ((1662607 * 256) + 128) / 200;
        apu_set_clock(1662607*256, frameCycles, ((1662607 * 256) + 128)/SAMPLE_RATE, 1);
    } else {
        frameCycles = ((1789773 * 256) + 128) / 240;
        apu_set_clock(1789773*256, frameCycles, ((1789773 * 256) + 128)/SAMPLE_RATE, 0);
    }
    
    // Initialize the APU registers
    for (i = 0x4000; i < 0x4010; i++) {
        apu_write(i, 0);
    }

    apu_write(0x4010, 0x10);
    apu_write(0x4011, 0x0);
    apu_write(0x4012, 0x0);
    apu_write(0x4013, 0x0);
    apu_write(0x4015, 0x0F);
    
    regA = subSong;
    regX = 0;  // NTSC/PAL
    regS = 0xFF;
    nsfPlayer_execute6502(fileHeader.initAddress, frameCycles*10);
}


void nsfPlayer_run(uint32_t numSamples, int8_t *buffer)
{
    uint32_t lstart = REG_VCOUNT;

    apu_run(numSamples, buffer);

    uint32_t lend = REG_VCOUNT;
    lend = (lend >= lstart) ? (lend - lstart) : (lend + 228 - lstart);
    perfcount = lend;
}
