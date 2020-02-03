#pragma once

#include <stdint.h>
#include <stdbool.h>

extern uint8_t apu_state[];

void apu_init();
void apu_reset();
void apu_run(uint32_t numSamples, int8_t *buffer);
void apu_write(uint32_t addr, uint8_t data);
void apu_set_clock(uint32_t clockHz, uint32_t frameCycles, uint32_t oscStep, uint32_t pal);