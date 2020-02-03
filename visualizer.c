/**
 * Visualizer for SwarmNSF
 * /Mic, 2020
 *
 * Everything is drawn during the initialization stage. The update functions
 * only modify palette entries to change the color of certain parts of the screen.
 */
 
#include <gba.h>
#include <stdint.h>
#include <string.h>
#include "common.h"
#include "visualizer.h"
#include "arm_apu.h"

#define PIANO_ROLL_NUM_KEYS 68
#define PIANO_ROLL_HEIGHT 24
#define PIANO_FLAT_KEY_WIDTH 5
#define PIANO_FLAT_KEY_STRIDE 6
#define PIANO_SHARP_KEY_WIDTH 3
#define PIANO_SHARP_KEY_HEIGHT 14

#define VOLUME_BAR_FIRST_COLOR 8
#define PIANO_FIRST_COLOR 104

// Octave 0 frequencies, fixed-point (shifted 8 bits)
static const uint32_t OCTAVE0[12] = {
    4186,
    4434,
    4698,
    4978,
    5274,
    5587,
    5919,
    6271,
    6644,
    7040,
    7458,
    7902
};

// The CPU usage calculation is done based on numbers of scanlines passed.
// But the audio buffer size might not match the screen refresh rate
// exactly, so we can't assume that 228 scanlines equals 100%.
static const uint32_t SCANLINES_PER_BUFFER = ((228 * 59737) / ((SAMPLE_RATE * 1000) / PCM_BUFFER_SIZE_SAMPLES));

// Palette data for the VU meters
static uint16_t volume_bar_on[16] = {992, 996, 1000, 1004, 1008, 1012, 1016, 1020, 927, 799, 671, 543, 415, 287, 159, 31};
static uint16_t volume_bar_half[16] = {672, 674, 677, 680, 683, 686, 689, 692, 661, 565, 469, 373, 277, 181, 85, 21};
static uint16_t volume_bar_off[16] = {320, 321, 322, 324, 325, 326, 328, 329, 298, 266, 202, 170, 138, 74, 42, 10};
static uint16_t cpu_bar_on[16] = {31744, 31748, 31752, 31756, 31760, 31764, 31768, 31772, 29727, 25631, 21535, 16415, 12319, 8223, 4127, 31};
static uint16_t cpu_bar_half[16] = {21504, 21506, 21509, 21512, 21515, 21517, 21520, 21523, 19477, 17429, 14357, 11285, 8213, 5141, 3093, 21};
static uint16_t cpu_bar_off[16] = {10240, 10241, 10242, 10244, 10245, 10246, 10248, 10249, 9226, 8202, 7178, 5130, 4106, 2058, 1034, 10};

// A#2..E7
static uint8_t piano_layout[68] = {0,1,0,0,1,0,1,0,0,1,0,1,0,1,0,0,1,0,1,0,0,1,0,1,0,1,0,0,1,0,1,0,0,1,0,1,0,1,0,0,1,0,1,0,0,1,0,1,0,1,0,0,1,0,1,0,0,1,0,1,0,1,0,0,1,0,1,0};
static uint8_t piano[240*24] __attribute__ ((section (".ewram"))) __attribute__ ((aligned (4)));

extern uint32_t perfcount;


static int clamp(int x, int min, int max) {
    return (x < min) ? min : ((x > max) ? max: x);
}

static void init_vu_meters() {
    uint16_t *dest = VRAM;

    for (int i = 0; i < 5; ++i) {
        for (int v = 0; v < 15; ++v) {
            BG_COLORS[VOLUME_BAR_FIRST_COLOR + i*16 + v] = volume_bar_off[v];
            for (int y = 0; y < 6; ++y) {
                for (int x = 0; x < 10; ++x) {
                    dest[((109 - v*7) + y) * 120 + 10 + i*18 + x] = (VOLUME_BAR_FIRST_COLOR + i*16 + v) | ((VOLUME_BAR_FIRST_COLOR + i*16 + v) << 8);
                }
            }
        }
    }

    // CPU usage bar
    for (int v = 0; v < 15; ++v) {
        BG_COLORS[VOLUME_BAR_FIRST_COLOR + 5*16 + v] = cpu_bar_off[v];
        for (int y = 0; y < 6; ++y) {
            for (int x = 0; x < 10; ++x) {
                dest[((109 - v*7) + y) * 120 + 10 + 5*18 + x] = (VOLUME_BAR_FIRST_COLOR + 5*16 + v) | ((VOLUME_BAR_FIRST_COLOR + 5*16 + v) << 8);
            }
        }
    }
}


static void init_piano_roll() {
    // Fill with dark gray
    memset(piano, 1, 240*PIANO_ROLL_HEIGHT);
    
    int f = 0;
    for (int i = 0; i < PIANO_ROLL_NUM_KEYS; ++i) {
        BG_COLORS[PIANO_FIRST_COLOR + i + PIANO_ROLL_NUM_KEYS] = RGB5(22,22,22);
        
        if (piano_layout[i]) {
            BG_COLORS[PIANO_FIRST_COLOR + i] = RGB5(0,0,0);
            // Draw a sharp key
            for (int y = 0; y < PIANO_SHARP_KEY_HEIGHT; ++y) {
                for (int x = 0; x < PIANO_SHARP_KEY_WIDTH; ++x) {
                    piano[(f-1)*PIANO_FLAT_KEY_STRIDE + y*240 + x + 4] = PIANO_FIRST_COLOR + i;
                }
            }
        } else {
            BG_COLORS[PIANO_FIRST_COLOR + i] = RGB5(30,30,30);
            // Draw a flat key
            for (int y = 0; y < PIANO_ROLL_HEIGHT; ++y) {
                for (int x = 0; x < 5; ++x) {
                    if (piano[f*PIANO_FLAT_KEY_STRIDE + y*240 + x] == 1) {
                        piano[f*PIANO_FLAT_KEY_STRIDE + y*240 + x] = PIANO_FIRST_COLOR + i;
                    }
                }
            }
            // Draw some shading at the bottom of the key
            for (int x = 0; x < PIANO_FLAT_KEY_WIDTH; ++x) {
                piano[f*PIANO_FLAT_KEY_STRIDE + 22*240 + x] = PIANO_FIRST_COLOR + i + PIANO_ROLL_NUM_KEYS;
                piano[f*PIANO_FLAT_KEY_STRIDE + 23*240 + x] = PIANO_FIRST_COLOR + i + PIANO_ROLL_NUM_KEYS;
            }
            f++;
        }
    }
}


static void update_vu_meters()
{
    static int levels[3][6] = {
        {0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 0, 0}
    };
    static int prev_levels[6] = {0, 0, 0, 0, 0, 0};
    static int counter = 0;

    counter++;

    for (int i = 0; i < 5; ++i) {
        levels[2][i] = levels[1][i];
        levels[1][i] = levels[0][i];
    }
    
    uint16_t *apu_state16 = (uint16_t*)apu_state;
    levels[0][0] = apu_state16[0x0C] & apu_state16[0x0D];
    levels[0][1] = apu_state16[0x1C] & apu_state16[0x1D];
    levels[0][2] = 15 & apu_state16[0x2D];
    levels[0][3] = apu_state16[0x3C] & apu_state16[0x3D];
    levels[0][4] = apu_state16[0x48] >> 3;
    levels[2][5] = clamp((16 * perfcount / SCANLINES_PER_BUFFER), 0, 15);
    
    for (int i = 0; i < 6; i++) {
        int highest = (prev_levels[i] > levels[2][i]) ? prev_levels[i] : levels[2][i];
        for (int v = 0; v < 16; ++v) {
            uint16_t c = 0;
            if (i < 5) {
                c = (v >= highest) ? volume_bar_off[v] : ((v > levels[2][i]) ? volume_bar_half[v] : volume_bar_on[v]);
            } else {
                c = (v >= highest) ? cpu_bar_off[v] : ((v > levels[2][i]) ? cpu_bar_half[v] : cpu_bar_on[v]);                
            }
            BG_COLORS[VOLUME_BAR_FIRST_COLOR + i*16 + v] = c;
        }

        if (prev_levels[i] > levels[2][i]) {
            if (counter & 1) prev_levels[i]--;
        } else {
            prev_levels[i] = levels[2][i];
        }
    }
}


/*
 * Calculate the note and octave that most closely matches each channel's current frequency, then
 * display those notes and octaves on-screen.
 */
static void update_piano_roll() {
    static uint32_t freq[8];
    static uint32_t prev_keys[5] = {0, 0, 0, 0, 0};
    static int counter = 0;

    int n, o;
    uint32_t shift, diff, minDiff, cmp;
    int closestNote, closestOct;

    counter++;
    
    if (counter & 1) {
        memset(freq, 0, 8*sizeof(uint32_t));

        uint32_t nesApuFreq = 1789773;
        uint16_t *apu_state16 = (uint16_t*)apu_state;
        uint32_t *apu_state32 = (uint32_t*)apu_state;
        
        if (apu_state16[0x0D] & apu_state16[0x0C]) {        // Pulse 1
            freq[0] = nesApuFreq * 256 / (16 * ((apu_state32[0x01] >> 8) + 1));
        }
        if (apu_state16[0x1D] & apu_state16[0x1C]) {           // Pulse 2
            freq[1] = nesApuFreq * 256 / (16 * ((apu_state32[0x09] >> 8) + 1));
        }
        if (apu_state16[0x2D]) {                            // Triangle
            freq[2] = nesApuFreq * 128 / (16 * ((apu_state32[0x11] >> 8) + 1));
        }
        if (apu_state16[0x3D] & apu_state16[0x3C]) {        // Noise
            freq[3] = 0;    // Not used
        }
        if (apu_state16[0x4D]) {                            // DMC
            freq[4] = 0;    // Not used
        }
    } else {
        for (int i = 0; i < 5; i++) {
            if (freq[i]) {
                // Find the closest matching note
                shift = 0;
                minDiff = 1000000;
                closestNote = -1;
                for (o = 0; o < 8; o++) {
                    for (n = 0; n < 12; n++) {
                        cmp = OCTAVE0[n] << shift;
                        diff = (cmp > freq[i]) ? (cmp - freq[i]) : (freq[i] - cmp);
                        if (diff < minDiff) {
                            minDiff = diff;
                            closestNote = n;
                            closestOct = o;
                        }
                    }
                    shift++;
                }

                if (prev_keys[i]) {
                    BG_COLORS[PIANO_FIRST_COLOR + prev_keys[i] - 21] = (piano_layout[prev_keys[i] - 21]) ? RGB5(0,0,0) : RGB5(30,30,30);
                    BG_COLORS[PIANO_FIRST_COLOR + PIANO_ROLL_NUM_KEYS + prev_keys[i] - 21] = RGB5(22,22,22);
                    prev_keys[i] = 0;
                }
                
                // Indicate the match if one was found
                if (closestNote != -1) {
                    int x = closestOct*12 + closestNote;
                    if (x >= 21 && x <= 88) {  // A#2..E7
                        BG_COLORS[PIANO_FIRST_COLOR + x - 21] = (piano_layout[x - 21]) ? RGB5(30,2,1) : RGB5(31,9,8);
                        BG_COLORS[PIANO_FIRST_COLOR + PIANO_ROLL_NUM_KEYS + x - 21] = RGB5(31,9,8);
                        prev_keys[i] = x;
                    }
                }
            } else if (prev_keys[i]) {
                BG_COLORS[PIANO_FIRST_COLOR + prev_keys[i] - 21] = (piano_layout[prev_keys[i] - 21]) ? RGB5(0,0,0) : RGB5(30,30,30);
                BG_COLORS[PIANO_FIRST_COLOR + PIANO_ROLL_NUM_KEYS + prev_keys[i] - 21] = RGB5(22,22,22);
                prev_keys[i] = 0;
            }
        }
    }
}


void init_visualizer() {
    init_piano_roll();
    CpuFastSet(piano, (u16*)(VRAM + 240*125),  (240*24)/4 | COPY32);
    init_vu_meters();
}


void update_visualizer() {
    update_vu_meters();
    update_piano_roll();
}