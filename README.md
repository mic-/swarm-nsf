# swarm-nsf
An NSF player for the Gameboy Advance

![Screenshot](swarmnsf.png)

Instead of relying on the DMG/CGB-compatible channels to try to mimic the NES sound processor, this is an all-software implementation running on the ARM CPU.
The output of the emulation code is a stream of 8-bit unsigned mono PCM data at 32768 Hz, which is played back using one of the GBA's DMA sound channels.
