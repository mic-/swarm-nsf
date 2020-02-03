#pragma once

#include <stdint.h>

typedef uint8_t (*readByteFunc)(uint32_t);
typedef void (*writeByteFunc)(uint32_t, uint8_t);

extern readByteFunc readByteFuncTbl[0x10];
extern writeByteFunc writeByteFuncTbl[0x10];
extern uint8_t mRam[0x800];

#define nsfMapper_readZp(addr) mRam[(addr)]
#define nsfMapper_writeZp(addr, data) mRam[(addr)] = data

void nsfmapper_set_num_rom_banks(uint32_t numBanks);
void nsfmapper_reset();
void nsfmapper_write_byte(uint32_t addr, uint8_t data);
uint8_t nsfmapper_read_byte(uint32_t addr);
uint8_t *nsfmapper_get_rom_pointer();
