#pragma once

#include <stdint.h>

enum {
    EMU6502_FLAG_C = 0x01,
    EMU6502_FLAG_Z = 0x02,
    EMU6502_FLAG_I = 0x04,
    EMU6502_FLAG_D = 0x08,
    EMU6502_FLAG_B = 0x10,
    EMU6502_FLAG_V = 0x40,
    EMU6502_FLAG_N = 0x80,
};

void emu6502_reset();
void emu6502_run(uint32_t maxCycles);
void emu6502_setBrkVector(uint32_t vector);
void emu6502_irq(uint32_t vector);
extern uint32_t regA, regX, regY, regS, regF, regPC, cpuCycles;
extern uint32_t savePC;
