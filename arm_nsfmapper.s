@ NSF memory mapping routines for SwarmNSF
@ /Mic, 2020

.cpu arm7tdmi
.arm

.global nsfmapper_reset
.global nsfmapper_set_num_rom_banks
.global nsfmapper_read_byte
.global nsfmapper_read_byte_pc
.global nsfmapper_read_instruction
.global nsfmapper_write_byte
.global nsfmapper_get_rom_pointer
.global callCode

.text
.section .iwram

.type nsfmapper_reset, %function
.func nsfmapper_reset
nsfmapper_reset:
    stmfd   sp!,{r4,r5}
    mov     r0,#0
    mov     r1,#0
    mov     r2,#0
    mov     r3,#0
    ldr     r4,=mRam
    mov     r5,#0x800
.clear_ram:
    stmia   r4!,{r0-r3}
    subs    r5,r5,#16
    bne     .clear_ram
    ldmfd   sp!,{r4,r5}
    bx      lr
.endfunc

.type nsfmapper_get_rom_pointer, %function
.func nsfmapper_get_rom_pointer
nsfmapper_get_rom_pointer:
    ldr     r0,=NSFROM
    bx  lr
.endfunc

@ In:  r0 = address
@ Out: r0 = value
@ Needs to preserve r2
.type nsfmapper_read_byte, %function
.func nsfmapper_read_byte
nsfmapper_read_byte:
    mov     r9,r0,lsr#12
    ldr     r9,[pc,r9,lsl#2]
    bx      r9
.page_lut:
    .word	nsfmapper_read_0000
    .word	nsfmapper_read_0000
    .word	nsfmapper_read_2000
    .word	nsfmapper_read_2000
    .word	nsfmapper_read_4000
    .word	nsfmapper_read_4000
    .word	nsfmapper_read_6000
    .word	nsfmapper_read_6000
    .word   nsfmapper_read_8000
    .word   nsfmapper_read_8000
    .word   nsfmapper_read_8000
    .word   nsfmapper_read_8000
    .word   nsfmapper_read_8000
    .word   nsfmapper_read_8000
    .word   nsfmapper_read_8000
    .word   nsfmapper_read_8000    
.endfunc

@ Same as nsfmapper_read_byte, but the address is given by the 6502 PC register.
.type nsfmapper_read_byte_pc, %function
.func nsfmapper_read_byte_pc
nsfmapper_read_byte_pc:
    mov     r9,r10,lsr#12
    ldr     r9,[pc,r9,lsl#2]
    bx      r9
    .word	nsfmapper_read_pc_0000
    .word	nsfmapper_read_pc_0000
    .word	nsfmapper_read_pc_2000
    .word	nsfmapper_read_pc_2000
    .word	nsfmapper_read_4000
    .word	nsfmapper_read_4000
    .word	nsfmapper_read_pc_6000
    .word	nsfmapper_read_pc_6000
    .word   nsfmapper_read_pc_8000
    .word   nsfmapper_read_pc_8000
    .word   nsfmapper_read_pc_8000
    .word   nsfmapper_read_pc_8000
    .word   nsfmapper_read_pc_8000
    .word   nsfmapper_read_pc_8000
    .word   nsfmapper_read_pc_8000
    .word   nsfmapper_read_pc_8000    
.endfunc

@ Same as nsfmapper_read_byte_pc, but reads two bytes: the first is returned in r0 and the second in r1.
@ Since many 6502 instruction have at least one operand byte, it's typically faster sometimes read an
@ extra byte that won't be used than to frequently have to make an extra read_byte call.
.type nsfmapper_read_instruction, %function
.func nsfmapper_read_instruction
nsfmapper_read_instruction:
    mov     r9,r10,lsr#12
    ldr     r9,[pc,r9,lsl#2]
    bx      r9
    .word	nsfmapper_read_instruction_0000
    .word	nsfmapper_read_instruction_0000
    .word	nsfmapper_read_instruction_2000
    .word	nsfmapper_read_instruction_2000
    .word	nsfmapper_read_instruction_4000
    .word	nsfmapper_read_instruction_4000
    .word	nsfmapper_read_instruction_6000
    .word	nsfmapper_read_instruction_6000
    .word   nsfmapper_read_instruction_8000
    .word   nsfmapper_read_instruction_8000
    .word   nsfmapper_read_instruction_8000
    .word   nsfmapper_read_instruction_8000
    .word   nsfmapper_read_instruction_8000
    .word   nsfmapper_read_instruction_8000
    .word   nsfmapper_read_instruction_8000
    .word   nsfmapper_read_instruction_8000    
.endfunc

nsfmapper_read_0000:
    ldr r9,=mRam
    ldrb r0,[r9, r0]
    bx lr

nsfmapper_read_2000:
    ldr     r9,=0x3F8F
    cmp     r0,r9
    bxhi    lr              @ if (address > 0x3F8F) return
    sub     r9,r9,#0x0F
    cmp     r0,r9
    bxcc    lr              @ if (address < 3F80) return
    ldr     r9,=callCode-0x3F80
    ldrb    r0,[r9, r0]
    bx      lr

    
nsfmapper_read_4000:
    bx      lr

nsfmapper_read_6000:
    ldr     r9,=mExRam-0x6000
    ldrb    r0,[r9, r0]
    bx      lr
    
nsfmapper_read_8000:
    ldr     r9,=NSFROM-0x8000
    ldrb    r0,[r9, r0]
    bx      lr

@--------------------
    
nsfmapper_read_pc_0000:
    ldr     r9,=mRam
    ldrb    r0,[r9, r10]
    bx      lr

nsfmapper_read_pc_2000:
    ldr     r9,=0x3F8F
    cmp     r10,r9
    bxhi    lr              @ if (address > 0x3F8F) return
    sub     r9,r9,#0x0F
    cmp     r10,r9
    bxcc    lr              @ if (address < 3F80) return
    ldr     r9,=callCode-0x3F80
    ldrb    r0,[r9, r10]
    bx      lr

nsfmapper_read_pc_6000:
    ldr     r9,=mExRam-0x6000
    ldrb    r0,[r9, r10]
    bx      lr
    
nsfmapper_read_pc_8000:
    @ NSF data is placed in VRAM at 0x600A000. We want that address offset by -0x8000.
    mov     r9,#0x06000000
    orr     r9,r9,#0x2000
    ldrb    r0,[r9, r10]
    bx      lr

@--------------------

nsfmapper_read_instruction_0000:
    ldr     r9,=mRam
    ldrb    r0,[r9, r10]
    add     r10,r10,#1
    ldrb    r1,[r9, r10]
    bx      lr

nsfmapper_read_instruction_2000:
    ldr     r9,=0x3F8F
    cmp     r10,r9
    bxhi    lr              @ if (address > 0x3F8F) return
    sub     r9,r9,#0x0F
    cmp     r10,r9
    bxcc    lr              @ if (address < 3F80) return
    ldr     r9,=callCode-0x3F80
    ldrb    r0,[r9, r10]
    add     r10,r10,#1
    ldrb    r1,[r9, r10]
    bx      lr

nsfmapper_read_instruction_4000:
    add     r0,r0,#1
    bx      lr

nsfmapper_read_instruction_6000:
    ldr     r9,=mExRam-0x6000
    ldrb    r0,[r9, r10]
    add     r10,r10,#1
    ldrb    r1,[r9, r10]
    bx      lr
    
nsfmapper_read_instruction_8000:
    mov     r9,#0x06000000
    orr     r9,r9,#0x2000
    ldrb    r0,[r9, r10]
    add     r10,r10,#1
    ldrb    r1,[r9, r10]
    bx      lr

@--------------------
    
@ In: r0 = address
@     r1 = value
@ Needs to preserve r0, r2
.type nsfmapper_write_byte, %function
.func nsfmapper_write_byte
nsfmapper_write_byte:
    mov     r9,r0,lsr#12
    ldr     r9,[pc,r9,lsl#2]
    bx      r9
.wrpage_lut:
    .word   nsfmapper_write_0000
    .word   nsfmapper_write_0000
    .word   nsfmapper_write_2000
    .word   nsfmapper_write_2000
    .word   nsfmapper_write_4000
    .word   nsfmapper_write_4000
    .word   nsfmapper_write_6000
    .word   nsfmapper_write_6000
    .word   nsfmapper_write_null
    .word   nsfmapper_write_null
    .word   nsfmapper_write_null
    .word   nsfmapper_write_null
    .word   nsfmapper_write_null
    .word   nsfmapper_write_null
    .word   nsfmapper_write_null
    .word   nsfmapper_write_null 
.endfunc

nsfmapper_write_0000:
    ldr     r9,=mRam
    strb    r1,[r9, r0]
    bx      lr

nsfmapper_write_2000:
    ldr     r9,=0x3F8F
    cmp     r0,r9
    bxhi    lr                  @ if (address > 0x3F8F) return
    sub     r9,r9,#0x0F
    cmp     r0,r9
    bxcc    lr                  @ if (address < 3F80) return
    ldr     r9,=callCode-0x3F80
    strb    r1,[r9, r0]
    bx      lr
    
nsfmapper_write_4000:
    ldr     r9,=0x4017
    cmp     r0,r9
    bxhi    lr                  @ if (address > 0x4017) return
    stmfd   sp!,{r3,r9,r12,lr}  @ {r0,r2-r10,r11,r12,lr}
    bl      call_apu_write
    ldmfd   sp!,{r3,r9,r12,pc}  @ {r0,r2-r10,r11,r12,pc}

nsfmapper_write_6000:
    ldr     r9,=mExRam-0x6000
    strb    r1,[r9, r0]
    bx      lr
    
nsfmapper_write_null:
    bx      lr

call_apu_write:
    ldr     r2,=apu_write
    bx      r2

.comm mRam,0x800,256
    
.section .ewram
callCode: .space 0x10
mExRam: .space 0x2000
@ The currently loaded NSF will be located in VRAM at address 0x600A000
.equ NSFROM, 0x0600A000
