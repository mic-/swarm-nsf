ROOTDIR = /c/devkitPro/devkitARM
DEVKITARMDIR = /c/devkitPro/devkitARM

LDSCRIPTSDIR = $(DEVKITARMDIR)/$(TARGET)/lib

# gba_cart.ld and gba_crt0.s refer to the ones from devkitPro

TARGET = arm-none-eabi
LIBPATH = -L$(ROOTDIR)/$(TARGET)/lib -L$(DEVKITARMDIR)/../libgba/lib
INCPATH = -I. -I$(ROOTDIR)/$(TARGET)/include -I$(DEVKITARMDIR)/../libgba/include

CCFLAGS = -std=c99 -O1 -nostartfiles -mlittle-endian -mthumb -mthumb-interwork -mtune=arm7tdmi -mcpu=arm7tdmi -Wall -c -fomit-frame-pointer
ARMCCFLAGS = -std=c99 -O2 -nostartfiles -mlittle-endian -marm -mthumb-interwork -mtune=arm7tdmi -mcpu=arm7tdmi -Wall -c -fomit-frame-pointer
LDFLAGS = -T gba_cart.ld -mthumb -mthumb-interwork -Wl,-Map=output.map -nostdlib -nostartfiles
ASFLAGS = -mcpu=arm7tdmi -EL

PREFIX = $(ROOTDIR)/bin/$(TARGET)-
CC = $(PREFIX)gcc
AS = $(PREFIX)as
LD = $(PREFIX)ld
OBJC = $(PREFIX)objcopy

DD = dd
RM = rm -f

OUTPUT = swarmnsf
LIBS = $(LIBPATH) -lgba -lc -lgcc -lnosys
OBJS = \
    gba_crt0.o \
    main.o \
    arm_nsfmapper.o \
    arm_6502.o \
    arm_apu.o \
    nsfplayer.o \
    visualizer.o \
    songs/songs.o


all: $(OUTPUT).gba

$(OUTPUT).gba: $(OUTPUT).elf
	$(OBJC) -O binary $< $(OUTPUT).gba
	$(DEVKITARMDIR)/bin/gbafix $@

$(OUTPUT).elf: $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $(OUTPUT).elf

%.arm.o: %.arm.c
	$(CC) $(ARMCCFLAGS) $(INCPATH) $< -o $@
    
%.o: %.c
	$(CC) $(CCFLAGS) $(INCPATH) $< -o $@

%.o: %.s
	$(AS) $(ASFLAGS) $(INCPATH) $< -o $@

clean:
	$(RM) music/*.o *.o *.gba *.elf output.map
