/**
 * SwarmNSF : An NSF player for the Gameboy Advance
 * /Mic, 2020
 */

#include <gba.h>
#include <stdint.h>
#include <string.h>
#include "common.h"
#include "nsfplayer.h"
#include "visualizer.h"

int8_t buffer[2 * PCM_BUFFER_SIZE_SAMPLES + 32];
uint32_t nextBuffer = 0;

uint8_t currSelection = 2;

volatile bool switchedBuffer = false;

extern nsfFileHeader fileHeader;

// From songs.s
extern uint8_t *SONG_POINTERS[];
extern uint32_t SONG_SIZES[];
extern uint32_t NUM_SONGS;

enum PendingChange {
    None = 0,
    PreviousSong,
    NextSong,
    PreviousSubSong,
    NextSubSong
};

enum State {
    Idle = 0,
    Playing,
    WaitingIrqDisableAck,
    PerformingChange,
    ResumingPlayback
};

enum PendingChange pendingChange = None;
enum State state = Idle;

uint32_t perfcount, cpuemutime;


void timer1IrqHandler() {
    if (state == Playing) {
        if (nextBuffer == 0) {
            REG_DMA1CNT = 0;
            REG_DMA1SAD = &buffer[0];
            REG_DMA1DAD = &REG_FIFO_A;
            REG_DMA1CNT = DMA_DST_FIXED | DMA_SRC_INC | DMA_REPEAT | DMA32 | DMA_SPECIAL | DMA_ENABLE;
        }
        REG_TM1CNT_L = 65536 - PCM_BUFFER_SIZE_SAMPLES;
        REG_TM1CNT_H = TIMER_COUNT | TIMER_IRQ | TIMER_START;
        nextBuffer ^= 1;
        switchedBuffer = true;
    } else if (state == WaitingIrqDisableAck) {
        REG_SOUNDCNT_H = 0;
        REG_SOUNDCNT_X = 0;
        REG_DMA1CNT = 0;
        REG_TM1CNT_H = 0;
        REG_IME = 0;
        state = PerformingChange;
    }
}


int main()
{
    uint16_t prevKeys = 0xffff;
    uint8_t currSubSong;
    
    irqInit();
    irqSet( IRQ_TIMER1, timer1IrqHandler);
    irqEnable(IRQ_TIMER1);

    REG_DISPCNT = 0x80;  // Forced blank

    // Clear BG2
    *((u32 *)VRAM) = 0;
    CpuFastSet(VRAM, VRAM, FILL | COPY32 | (240*160/4));

    // Song list colors
    BG_COLORS[0] = RGB5(0, 0, 0);
    BG_COLORS[1] = RGB5(8, 8, 8);
    BG_COLORS[2] = RGB5(20, 20, 20);
    
    BG_OFFSET[2].x = 0; BG_OFFSET[0].y = 0;
    BGCTRL[2] = BG_256_COLOR;
   
    init_visualizer();

    SetMode(MODE_4 | BG2_ON);

    nsfPlayer_init();
    nsfPlayer_prepare(SONG_POINTERS[currSelection], SONG_SIZES[currSelection]);
    nsfPlayer_run(PCM_BUFFER_SIZE_SAMPLES, &buffer[0]);
    currSubSong = fileHeader.firstSong -1;
    
    REG_SOUNDCNT_H = SNDA_VOL_100 | SNDA_R_ENABLE | SNDA_L_ENABLE | SNDA_RESET_FIFO;
    REG_SOUNDCNT_X = SNDSTAT_ENABLE;

    REG_TM0CNT_L = 65536 - 512;        // 32768 Hz
    REG_TM0CNT_H = TIMER_START;

    REG_TM1CNT_L = 65536 - PCM_BUFFER_SIZE_SAMPLES;
    REG_TM1CNT_H = TIMER_COUNT | TIMER_IRQ | TIMER_START;

    state = Playing;
    pendingChange = None;
    
    REG_IME = 1;
    while (1) {
        switch (state) {
            case PerformingChange:
                switch (pendingChange) {
                    case PreviousSong:    // fall-through
                    case NextSong:
                        currSelection += (pendingChange == NextSong) ? 1 : -1;
                        nsfPlayer_init();
                        nsfPlayer_prepare(SONG_POINTERS[currSelection], SONG_SIZES[currSelection]);
                        currSubSong = fileHeader.firstSong - 1;
                        break;
                    case PreviousSubSong: // fall-through
                    case NextSubSong:
                        currSubSong += ((pendingChange == NextSubSong) ? 1 : -1);
                        nsfPlayer_setSubSong(currSubSong);
                        break;
                    default:
                        break;
                }
                state = ResumingPlayback;
                break;
            
            case ResumingPlayback:
                REG_SOUNDCNT_H = SNDA_VOL_100 | SNDA_R_ENABLE | SNDA_L_ENABLE | SNDA_RESET_FIFO;
                REG_SOUNDCNT_X = SNDSTAT_ENABLE;
                REG_TM1CNT_H = TIMER_COUNT | TIMER_IRQ | TIMER_START;
                state = Playing;
                pendingChange = None;
                REG_IME = 1;
                break;
                
            case Playing: {
                while (!switchedBuffer) {}
                switchedBuffer = false;
                nsfPlayer_run(PCM_BUFFER_SIZE_SAMPLES, &buffer[nextBuffer * PCM_BUFFER_SIZE_SAMPLES]);

                if (pendingChange == None) {
                    uint16_t keys = REG_KEYINPUT;
                    uint16_t diff = keys ^ prevKeys;
                    prevKeys = keys;
                    if ((diff & KEY_LEFT) & keys) {
                        if (currSubSong > 0) {
                            state = WaitingIrqDisableAck;
                            pendingChange = PreviousSubSong;
                        }
                    } else if ((diff & KEY_RIGHT) & keys) {
                        if (currSubSong < fileHeader.numSongs - 1) {
                            state = WaitingIrqDisableAck;
                            pendingChange = NextSubSong;
                        }
                    } else if ((diff & KEY_UP) & keys) {
                        if (currSelection > 0) {
                            state = WaitingIrqDisableAck;
                            pendingChange = PreviousSong;
                            REG_SOUNDCNT_H = SNDA_VOL_50 | SNDA_R_ENABLE | SNDA_L_ENABLE;
                        }
                    } else if ((diff & KEY_DOWN) & keys) {
                        if (currSelection < NUM_SONGS-1) {
                            state = WaitingIrqDisableAck;
                            pendingChange = NextSong;
                            REG_SOUNDCNT_H = SNDA_VOL_50 | SNDA_R_ENABLE | SNDA_L_ENABLE;
                        }
                    }
                }    
                break;
            }
            
            default:
                break;
        }

        update_visualizer();
    }

    return 0;
}
