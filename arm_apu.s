@ NES APU emulation for SwarmNSF
@ Mic, 2020

.cpu arm7tdmi
.arm

.global apu_init
.global apu_reset
.global apu_set_clock
.global apu_run
.global apu_write
.global apu_state

.equ ARM_SWI_DIV, 0x60000
 
.text
.section .iwram

.type apu_init, %function
.func apu_init
apu_init:
    ldr     r3,=apu_state
    add     r0,r3,#CHN_1_VOLUME
    str     r0,[r3, #EG_1_VOLUME_PTR]
    add     r0,r3,#CHN_2_VOLUME
    str     r0,[r3, #EG_2_VOLUME_PTR]
    add     r0,r3,#CHN_4_VOLUME
    str     r0,[r3, #EG_3_VOLUME_PTR]    
    bx  lr
.endfunc

   
.type apu_reset, %function
.func apu_reset
apu_reset:
    stmfd   sp!,{r4,r5}
    ldr     r4,=apu_state
    mov     r0,#0
    mov     r1,#0
    mov     r2,#0
    mov     r3,#0
    mov     r5,#384
.clear_state:
    stmia   r4!,{r0-r3}
    subs    r5,r5,#16
    bne     .clear_state

    ldr     r4,=apu_state
    ldr     r0,=SQUARE_WAVES
    str     r0,[r4, #PULSE_1_WAVEFORM_PTR]
    str     r0,[r4, #PULSE_2_WAVEFORM_PTR]
    
    mvn     r0,#0
    strb    r0,[r4, #CHN_3_OUTPUT]
    
    mov     r0,#1
    strh    r0,[r4, #CHN_4_LFSR]
    strb    r0,[r4, #CLOCK_SEQUENCER]
    
    mov     r0,#2
    str     r0,[r4, #CHN_1_SWEEP_PERIOD]
    str     r0,[r4, #CHN_2_SWEEP_PERIOD]

    mov     r0,#3
    str     r0,[r4, #MAX_FRAME]
    
    add     r0,r4,#CHN_1_VOLUME
    str     r0,[r4, #EG_1_VOLUME_PTR]
    add     r0,r4,#CHN_2_VOLUME
    str     r0,[r4, #EG_2_VOLUME_PTR]
    add     r0,r4,#CHN_4_VOLUME
    str     r0,[r4, #EG_3_VOLUME_PTR]    
    
    ldmfd   sp!,{r4,r5}
    bx      lr
.pool
.endfunc


@ r0 = CPU clock
@ r1 = cyclesPerFrame
@ r2 = oscStep
@ r3 = PAL mode
.type apu_set_clock, %function
.func apu_set_clock
apu_set_clock:
    str     r4,[sp, #-4]!
    ldr     r4,=apu_state
    and     r3,r3,#1
    str     r1,[r4, #CYCLES_PER_FRAME]
    strb    r3,[r4, #PAL_MODE]
    str     r2,[r4, #PER_SAMPLE_STEP]
    str     r0,[r4, #CPU_CLOCK]
    ldr     r4,[sp],#4
    bx      lr
.endfunc


@ r0 = numSamples
@ r1 = buffer
@-----------------
@ Register usage during the main loop:
@  r2  = numSamples
@  r3  = &apu_state
@  r4  = perSampleStep  (e.g. 1789773*4/32768 for NTSC tunes)
@  r8  = buffer
@  r10 = &PULSE_TABLE
@  r12 = dmcSample
.type apu_run, %function
.func apu_run
apu_run:
    tst     r0,r0
    bxeq    lr
    stmfd   sp!,{r4-r12,lr}
    mov     r8,r1           @ r8 = buffer
    mov     r2,r0           @ r2 = numSamples
    ldr     r3,=apu_state
    ldr     r10,=PULSE_TABLE
    ldrh    r12,[r3, #CHN_5_SAMPLE]
    ldr     r4,[r3, #PER_SAMPLE_STEP]
.run_samples:    
    ldrb    r0,[r3, #CLOCK_SEQUENCER]
    tst     r0,r0
    beq     .no_sequencer_frame
    stmfd   sp!,{r2-r3}
    strh    r12,[r3, #CHN_5_SAMPLE]
    mov     r0,#1
    bl      apu_sequencer_frame
    ldmfd   sp!,{r2-r3}
    ldrh    r12,[r3, #CHN_5_SAMPLE]
    mov     r0,#0
    strb    r0,[r3, #CLOCK_SEQUENCER]
.no_sequencer_frame:
    ldr     r0,[r3, #CYCLE_COUNT]
    ldr     r1,[r3, #CYCLES_PER_FRAME]
    add     r0,r0,r4
    subs    r5,r0,r1
    movcs   r6,#1
    movcs   r0,r5
    strcsb  r6,[r3, #CLOCK_SEQUENCER]    
    str     r0,[r3, #CYCLE_COUNT]
    
    @ Pulse #1
    ldr     r0,[r3, #CHN_1_POS]
    ldr     r1,[r3, #PULSE_1_FREQ]
    mov     r9,r0,lsr#16
    add     r0,r0,r1
    ldr     r6,[r3, #PULSE_1_WAVEFORM_PTR]
    cmp     r0,#0x800000        @ pos >= (32768 * 256) ?
    ldrb    r5,[r6, r9]
    subcs   r0,r0,#0x800000     @ pos -= (32768 * 256)
    strb    r5,[r3, #CHN_1_OUTPUT]
    str     r0,[r3, #CHN_1_POS]
    
    @ Pulse #2
    ldr     r0,[r3, #CHN_2_POS]
    ldr     r1,[r3, #PULSE_2_FREQ]
    mov     r9,r0,lsr#16
    add     r0,r0,r1
    ldr     r6,[r3, #PULSE_2_WAVEFORM_PTR]
    cmp     r0,#0x800000
    ldrb    r5,[r6, r9]
    subcs   r0,r0,#0x800000
    strb    r5,[r3, #CHN_2_OUTPUT]
    str     r0,[r3, #CHN_2_POS]

    @ Triangle
    ldr     r1,[r3, #CHN_3_PERIOD]
    cmp     r1,#3
    bls     .no_chn3_change
    ldr     r0,[r3, #CHN_3_POS]
    add     r0,r0,r4
    cmp     r0,r1
    str     r0,[r3, #CHN_3_POS]
    bcc     .no_chn3_change
    tst     r1,r1
    beq     .no_chn3_change
    mov     r9,#0
.tri_calc_steps:
    sub     r0,r0,r1
    add     r9,r9,#1
    cmp     r0,r1
    bcs     .tri_calc_steps
    ldr     r5,[r3, #CHN_3_WAVE_STEP]
    ldr     r6,=TRIANGLE_WAVE
    str     r0,[r3, #CHN_3_POS]
    add     r5,r5,r9
    and     r5,r5,#31
    ldrb    r1,[r6, r5]
    strh    r1,[r3, #CHN_3_VOLUME]
    str     r5,[r3, #CHN_3_WAVE_STEP]
.no_chn3_change:


    @ Noise
    ldr     r0,[r3, #CHN_4_POS]
    ldr     r1,[r3, #CHN_4_PERIOD]
    add     r0,r0,r4
    cmp     r0,r1
    str     r0,[r3, #CHN_4_POS]
    bcc     .no_chn4_change
    sub     r0,r0,r1
    and     r0,r0,#0xFF
    ldrh    r5,[r3, #CHN_4_LFSR]
    ldrb    r6,[r3, #APU_REGS+R_NOISE_MODE_PER]
    mov     r7,r5    
    mov     r9,#1
    str     r0,[r3, #CHN_4_POS]
    tst     r6,#0x80
    and     r5,r5,#1
    movne   r9,#6
    sub     r5,r5,#1
    mov     r6,r7,lsr r9            @ r6 = lfsr >> ((regs[R_NOISE_MODE_PER] & 0x80) ? 6 : 1)
    strb    r5,[r3, #CHN_4_OUTPUT]  @ output = (lfsr & 1) - 1
    eor     r6,r6,r7
    mov     r9,r7,lsr #1
    and     r6,r6,#1
    orr     r9,r9,r6,lsl#14
    strh    r9,[r3, #CHN_4_LFSR]
.no_chn4_change:
    
    @ DMC
    ldrb    r0,[r3, #APU_REGS+R_STATUS]
    tst     r0,#0x10
    ldrh    r6,[r3, #CHN_5_SAMPLE_POS]
    ldrh    r7,[r3, #CHN_5_SAMPLE_LEN]
    beq     .chn5_disabled
    ldr     r0,[r3, #CHN_5_POS]
    ldr     r1,[r3, #CHN_5_PERIOD]
    add     r0,r0,r4    
    str     r0,[r3, #CHN_5_POS]
.dmc_step:
    cmp     r0,r1
    bcc     .dmc_step_done
    sub     r0,r0,r1
    str     r0,[r3, #CHN_5_POS]
    cmp     r12,#1
    bhi     .dmc_have_bits_remaining
    @ Load another sample byte
    cmp     r6,r7
    bcs     .no_sample_load
    mov     r9,#0x3F00
    ldrh    r5,[r3, #CHN_5_SAMPLE_ADDR]
    orr     r9,r9,#0xFF
    add     r5,r5,r6       
    and     r5,r5,r9        @ r5 = (sampleAddr + samplePos) & 0x3FFF
    add     r5,r5,#0x06000000
    add     r5,r5,#0xE000   @ Sample addresses start at NES address 0xC000. NES address 0x8000 corresponds to GBA address 0x0600A000 
    ldrb    r12,[r5]
    add     r6,r6,#1        @ samplePos++
    orr     r12,r12,#0x100  @ 8 bits of data, plus 1 bit to indicate data remaining
    mvn     r9,#0
    strh    r9,[r3, #CHN_5_OUTPUT_MASK]
.no_sample_load:
    cmp     r6,r7
    bcc     .dmc_have_bits_remaining
    ldrb    r9,[r3, #APU_REGS+R_DMC_PER_LOOP]
    tst     r9,#0x40
    beq     .dmc_sample_ended
    @ Loop
    ldrb    r5,[r3, #APU_REGS+R_DMC_SMPADR]
    ldrb    r9,[r3, #APU_REGS+R_DMC_SMPLEN]
    mov     r5,r5,lsl#6
    mov     r9,r9,lsl#4
    orr     r5,r5,#0x8000
    add     r7,r9,#1
    strh    r5,[r3, #CHN_5_SAMPLE_ADDR]
    mov     r6,#0
    b       .dmc_have_bits_remaining
.dmc_sample_ended:
    mov     r5,#0
    strh    r5,[r3, #CHN_5_OUTPUT_MASK]
.dmc_have_bits_remaining:    
    cmp     r12,#1
    ldrb    r9,[r3, #CHN_5_OUTPUT]
    bls     .dmc_no_data
    movs    r12,r12,lsr#1
    addcs   r11,r9,#2
    subcc   r11,r9,#2       @ r11 = output + ((sample & 1) ? 2 : -2)
    tst     r11,#0x80   
    moveq   r9,r11          @ output = (r11 >= 0 && r11 <= 127) ? r11 : output     
    strb    r9,[r3, #CHN_5_OUTPUT]
.dmc_no_data:
    strb    r9,[r3, #CHN_5_TO_DAC]    
    b       .dmc_step
.chn5_disabled:
    mov     r0,#0
    strh    r0,[r3, #CHN_5_OUTPUT_MASK]
.dmc_step_done:
    strh    r6,[r3, #CHN_5_SAMPLE_POS]
    strh    r7,[r3, #CHN_5_SAMPLE_LEN]
    
    ldrb    r0,[r3, #CHN_1_OUTPUT_MASK]
    tst     r0,r0
    ldrneb  r5,[r3, #CHN_1_OUTPUT]
    ldrneh  r6,[r3, #CHN_1_VOLUME]
    mulne   r5,r6,r5
    strneh  r5,[r3, #CHN_1_TO_DAC]
    ldreqh  r5,[r3, #CHN_1_TO_DAC]
    
    ldrb    r0,[r3, #CHN_2_OUTPUT_MASK]
    tst     r0,r0
    ldrneb  r7,[r3, #CHN_2_OUTPUT]
    ldrneh  r6,[r3, #CHN_2_VOLUME]
    mulne   r7,r6,r7
    strneh  r7,[r3, #CHN_2_TO_DAC]
    ldreqh  r7,[r3, #CHN_2_TO_DAC]
    add     r5,r5,r7
  
    @ Triangle
    ldrb    r0,[r3, #CHN_3_OUTPUT_MASK]
    tst     r0,r0
    ldrneh  r9,[r3, #CHN_3_VOLUME]
    addne   r9,r9,r9,lsl#1
    strneh  r9,[r3, #CHN_3_TO_DAC]
    ldreqsh r9,[r3, #CHN_3_TO_DAC]
  
    @ Noise
    ldrb    r0,[r3, #CHN_4_OUTPUT_MASK]
    tst     r0,r0
    ldrnesb r7,[r3, #CHN_4_OUTPUT]
    ldrneh  r6,[r3, #CHN_4_VOLUME]
    andne   r7,r7,r6
    addne   r7,r7,r7,lsr#1
  ldrneh  r6,[r3, #CHN_4_TO_DAC]
  subne r7,r7,r6
  addne r7,r6,r7,asr#1  
    strneh  r7,[r3, #CHN_4_TO_DAC]
    ldreqsh r7,[r3, #CHN_4_TO_DAC]
    
    mov     r6,#256
    add     r6,#65
    mul     r5,r6,r5
    mov     r5,r5,lsr#15       @ r5 = (chn1ToDac + chn2ToDac) * 321/32768

    ldrb    r11,[r3, #CHN_5_TO_DAC]
    add     r9,r10,r9,lsl#1
    add     r9,r9,r7,lsl#1
    add     r9,r9,r11,lsl#1
    ldrh    r6,[r9, #64]        @ r6 = TND_TABLE[chn3ToDac + chn4ToDac + chn5ToDac]
    add     r5,r5,r6  
    sub     r5,r5,#128
    
    strb    r5,[r8],#1

    subs    r2,r2,#1
    bne     .run_samples
    strh    r12,[r3, #CHN_5_SAMPLE]
    ldmfd   sp!,{r4-r12,lr}
    bx      lr
.pool    
.endfunc

     
@ r0 = address
@ r1 = data
.type apu_write, %function
.func apu_write
apu_write:
    ldr     r3,=apu_state
    and     r1,r1,#0xFF   
    str     r4,[sp, #-4]!
    and     r0,r0,#0x1F
    add     r2,r0,#APU_REGS
    ldrb    r4,[r3, r2]         @ r4 = previous value
    strb    r1,[r3, r2]
    ldr     r2,[pc,r0,lsl#2]
    bx      r2
.apu_write_table:
    .word .apu_write_pulse1_duty_enve
    .word .apu_write_pulse1_sweep
    .word .apu_write_pulse1_perlo
    .word .apu_write_pulse1_perhi_len
    .word .apu_write_pulse2_duty_enve
    .word .apu_write_pulse2_sweep
    .word .apu_write_pulse2_perlo
    .word .apu_write_pulse2_perhi_len
    .word .apu_write_tri_lin
    .word .apu_write_unused     @ $4009
    .word .apu_write_tri_perlo
    .word .apu_write_tri_perhi_len
    .word .apu_write_noise_enve
    .word .apu_write_unused     @ $400D
    .word .apu_write_noise_mode_per
    .word .apu_write_noise_len
    .word .apu_write_dmc_per_loop
    .word .apu_write_dmc_dirld
    .word .apu_write_dmc_smpadr
    .word .apu_write_dmc_smplen
    .word .apu_write_unused     @ $4014
    .word .apu_write_status
    .word .apu_write_unused     @ $4016
    .word .apu_write_framecnt


.apu_write_pulse1_duty_enve:
    tst     r1,#0x10
    andne   r2,r1,#0x0F
    strneh  r2,[r3, #CHN_1_VOLUME]
    mov     r1,r1,lsr#6
    strb    r1,[r3, #CHN_1_DUTY_CYCLE]
    ldr     r2,[r3, #CHN_1_PERIOD]
    mov     r2,r2,lsr#8
    ldr     r1,=wave_table_index
    ldrb    r0,[r1,r2]
    ldrb    r1,[r3, #CHN_1_DUTY_CYCLE]
    mov     r1,r1,lsl#11
    add     r1,r1,r0,lsl#7
    ldr     r0,=wave_table
    add     r1,r1,r0
    str     r1,[r3, #PULSE_1_WAVEFORM_PTR]   
    ldr     r4,[sp],#4
    bx      lr

.apu_write_pulse1_sweep:
    mov     r0,#1
    strb    r0,[r3, #CHN_1_SWEEP_RELOAD]
    ldr     r4,[sp],#4
    bx      lr

.apu_write_pulse1_perlo:
    ldr     r2,[r3, #CHN_1_PERIOD]
    and     r2,r2,#0x70000
    orr     r2,r2,r1,lsl#8
    str     r2,[r3, #CHN_1_PERIOD]
    movs    r2,r2,lsr#8
    beq     1f
    stmfd   sp!,{r2,r3}         @ save registers that will be clobbered by SWI_DIV
    ldr     r0,[r3, #CPU_CLOCK]
    add     r1,r2,#1
    mov     r1,r1,lsl#4
    swi     ARM_SWI_DIV         @ calculate frequency based on period
    ldmfd sp!,{r2,r3}
1:
    str     r0,[r3, #PULSE_1_FREQ]
    ldr     r1,=wave_table_index
    ldrb    r0,[r1,r2]
    ldrb    r1,[r3, #CHN_1_DUTY_CYCLE]
    mov     r1,r1,lsl#11        @ r1 = dutyCycle * 0x800
    add     r1,r1,r0,lsl#7
    ldr     r0,=wave_table
    add     r1,r1,r0
    str     r1,[r3, #PULSE_1_WAVEFORM_PTR]
    ldr     r4,[sp],#4
    bx      lr

.pool
    
.apu_write_pulse1_perhi_len:
    ldr     r2,[r3, #CHN_1_PERIOD]
    and     r4,r1,#7
    and     r2,r2,#0xFF00
    orr     r2,r2,r4,lsl#16
    str     r2,[r3, #CHN_1_PERIOD]          @ period = (period & 0x3FC) | ((data & 7) << 10)    
    movs    r2,r2,lsr#8
    beq     1f
    stmfd sp!,{r1-r3}
    ldr r0,[r3, #CPU_CLOCK]
    add r1,r2,#1
    mov r1,r1,lsl#4
    swi ARM_SWI_DIV
    ldmfd sp!,{r1-r3}
1:
    str r0,[r3, #PULSE_1_FREQ]
    ldr r4,=wave_table_index
    ldrb r0,[r4,r2]
    ldrb r4,[r3, #CHN_1_DUTY_CYCLE]
    mov r4,r4,lsl#11
    add r4,r4,r0,lsl#7
    ldr r0,=wave_table
    add r4,r4,r0
    str r4,[r3, #PULSE_1_WAVEFORM_PTR]
    mov     r0,#1
    mov     r4,#0
    strb    r0,[r3, #EG_1_START]            @ eg->start = true
    ldrb    r2,[r3, #APU_REGS+R_STATUS]
@    str     r4,[r3, #CHN_1_POS]             @ pos = 0
    tst     r2,#1                           @ pulse 1 enabled?
    str     r4,[r3, #CHN_1_WAVE_STEP]
    ldreq   r4,[sp],#4
    bxeq    lr
    ldr     r0,=LENGTH_COUNTERS
    mov     r1,r1,lsr#3
    mvn     r2,#0
    ldrb    r0,[r0, r1]
    tst     r0,r0
    str     r0,[r3, #CHN_1_LENC_STEP]
    moveq   r2,#0
    strh    r2,[r3, #CHN_1_OUTPUT_MASK]
    ldr     r4,[sp],#4
    bx      lr    

.pool
.align 4

.apu_write_pulse2_duty_enve:
    tst     r1,#0x10
    andne   r2,r1,#0x0F
    strneh  r2,[r3, #CHN_2_VOLUME]
    mov     r1,r1,lsr#6
    strb    r1,[r3, #CHN_2_DUTY_CYCLE]
    ldr     r2,[r3, #CHN_2_PERIOD]
    mov     r2,r2,lsr#8
    ldr     r1,=wave_table_index
    ldrb    r0,[r1,r2]
    ldrb    r1,[r3, #CHN_2_DUTY_CYCLE]
    mov     r1,r1,lsl#11        @ r1 = dutyCycle * 0x800
    add     r1,r1,r0,lsl#7
    ldr     r0,=wave_table
    add     r1,r1,r0
    str     r1,[r3, #PULSE_2_WAVEFORM_PTR]   
    ldr     r4,[sp],#4
    bx      lr

.apu_write_pulse2_sweep:
    mov     r0,#1
    strb    r0,[r3, #CHN_2_SWEEP_RELOAD]
    ldr     r4,[sp],#4
    bx      lr

.apu_write_pulse2_perlo:
    ldr     r2,[r3, #CHN_2_PERIOD]
    and     r2,r2,#0x70000
    orr     r2,r2,r1,lsl#8
    str     r2,[r3, #CHN_2_PERIOD]
    movs    r2,r2,lsr#8
    beq     1f
    stmfd   sp!,{r2,r3}
    ldr     r0,[r3, #CPU_CLOCK]
    add     r1,r2,#1
    mov     r1,r1,lsl#4
    swi     ARM_SWI_DIV
    ldmfd   sp!,{r2,r3}
1:
    str     r0,[r3, #PULSE_2_FREQ]
    ldr     r1,=wave_table_index
    ldrb    r0,[r1,r2]
    ldrb    r1,[r3, #CHN_2_DUTY_CYCLE]
    mov     r1,r1,lsl#11            @ r1 = dutyCycle * 0x800
    add     r1,r1,r0,lsl#7
    ldr     r0,=wave_table
    add     r1,r1,r0
    str     r1,[r3, #PULSE_2_WAVEFORM_PTR]    
    ldr     r4,[sp],#4
    bx      lr

.apu_write_pulse2_perhi_len:
    ldr     r2,[r3, #CHN_2_PERIOD]
    and     r4,r1,#7
    and     r2,r2,#0xFF00
    orr     r2,r2,r4,lsl#16
    str     r2,[r3, #CHN_2_PERIOD]          @ period = (period & 0x3FC) | ((data & 7) << 10) 
    movs    r2,r2,lsr#8
    beq     1f
    stmfd   sp!,{r1-r3}
    ldr     r0,[r3, #CPU_CLOCK]
    add     r1,r2,#1
    mov     r1,r1,lsl#4
    swi     ARM_SWI_DIV
    ldmfd   sp!,{r1-r3}
1:
    str     r0,[r3, #PULSE_2_FREQ]
    ldr     r4,=wave_table_index
    ldrb    r0,[r4,r2]
    ldrb    r4,[r3, #CHN_2_DUTY_CYCLE]
    mov     r4,r4,lsl#11
    add     r4,r4,r0,lsl#7
    ldr     r0,=wave_table
    add     r4,r4,r0
    str     r4,[r3, #PULSE_2_WAVEFORM_PTR]
    mov     r0,#1
    mov     r4,#0
    strb    r0,[r3, #EG_2_START]            @ eg->start = true
    ldrb    r2,[r3, #APU_REGS+R_STATUS]
@    str     r4,[r3, #CHN_2_POS]             @ pos = 0
    tst     r2,#2                           @ pulse 2 enabled?
    str     r4,[r3, #CHN_2_WAVE_STEP]
    ldreq   r4,[sp],#4
    bxeq    lr
    ldr     r0,=LENGTH_COUNTERS
    mvn     r2,#0
    ldrb    r0,[r0, r1,lsr#3]
    tst     r0,r0
    str     r0,[r3, #CHN_2_LENC_STEP]
    moveq   r2,#0
    strh    r2,[r3, #CHN_2_OUTPUT_MASK]
    ldr     r4,[sp],#4
    bx      lr

.apu_write_tri_lin:
    @ No action
    ldr     r4,[sp],#4
    bx      lr

.apu_write_tri_perlo:
    ldr     r2,[r3, #CHN_3_PERIOD]
    and     r2,r2,#0x70000
    orr     r2,r2,r1,lsl#8
    str     r2,[r3, #CHN_3_PERIOD]
    ldr     r4,[sp],#4
    bx      lr

.apu_write_tri_perhi_len:
    ldr     r2,[r3, #CHN_3_PERIOD]
    and     r4,r1,#7
    and     r2,r2,#0xFF00
    orr     r2,r2,r4,lsl#16
    mov     r0,#1
    str     r2,[r3, #CHN_3_PERIOD]          @ period = (period & 0x3FC) | ((data & 7) << 10)
    strb    r0,[r3, #CHN_3_LINC_RELOAD]     @ lincReload = true
    ldrb    r2,[r3, #APU_REGS+R_STATUS]
    tst     r2,#4                           @ triangle enabled ?
    ldreq   r4,[sp],#4
    bxeq    lr
    ldr     r0,=LENGTH_COUNTERS
    ldrb    r0,[r0, r1,lsr#3]
    str     r0,[r3, #CHN_3_LENC_STEP]
    ldr     r4,[sp],#4
    bx      lr

.apu_write_noise_enve:
    tst     r1,#0x10
    ldreq   r4,[sp],#4
    bxeq    lr
    and     r1,r1,#0x0F
    strh    r1,[r3, #CHN_4_VOLUME]
    ldr     r4,[sp],#4
    bx      lr

.apu_write_noise_mode_per:
    ldr     r2,=NOISE_PERIODS
    and     r1,r1,#0x0F
    ldrb    r0,[r3, #PAL_MODE]
    add     r2,r2,r1,lsl#1
    add     r2,r2,r0,lsl#5
    ldrh    r1,[r2]
    mov     r1,r1,lsl#8
    str     r1,[r3, #CHN_4_PERIOD]
    ldr     r4,[sp],#4
    bx      lr

.apu_write_noise_len:
    mov     r0,#1
    mov     r2,#0
    strb    r0,[r3, #EG_3_START]            @ eg->start = true
    str     r2,[r3, #CHN_4_POS]
    ldrb    r2,[r3, #APU_REGS+R_STATUS]
    tst     r2,#8                           @ noise enabled ?
    ldreq   r4,[sp],#4
    bxeq    lr
    ldr     r0,=LENGTH_COUNTERS
    mvn     r2,#0
    ldrb    r0,[r0, r1,lsr#3]
    tst     r0,r0
    str     r0,[r3, #CHN_4_LENC_STEP]
    moveq   r2,#0
    strh    r2,[r3, #CHN_4_OUTPUT_MASK]
    ldr     r4,[sp],#4
    bx      lr
      
.apu_write_dmc_per_loop:
    ldr     r2,=DMC_PERIODS
    and     r1,r1,#0x0F
    ldrb    r0,[r3, #PAL_MODE]
    add     r2,r2,r1,lsl#1
    add     r2,r2,r0,lsl#5
    ldrh    r1,[r2]
    mov     r1,r1,lsl#8
    str     r1,[r3, #CHN_5_PERIOD]
    ldr     r4,[sp],#4
    bx      lr
    
.apu_write_dmc_dirld:
    @ Currently ignored to avoid loud pops in some songs
    ldr     r4,[sp],#4
    bx      lr

.apu_write_dmc_smpadr:
.apu_write_dmc_smplen:
.apu_write_unused:
    @ No action
    ldr     r4,[sp],#4
    bx      lr

.apu_write_status:
    mov     r2,#0
    tst     r1,#1
    streqh  r2,[r3, #CHN_1_OUTPUT_MASK]
    streq   r2,[r3, #CHN_1_LENC_STEP]
    tst     r1,#2
    streqh  r2,[r3, #CHN_2_OUTPUT_MASK]
    streq   r2,[r3, #CHN_2_LENC_STEP]
    tst     r1,#4
    streq   r2,[r3, #CHN_3_LENC_STEP]
    tst     r1,#8
    streqh  r2,[r3, #CHN_4_OUTPUT_MASK]
    streq   r2,[r3, #CHN_4_LENC_STEP]
    tst     r1,#0x10
    streqh  r2,[r3, #CHN_5_OUTPUT_MASK]
    ldreqh  r0,[r3, #CHN_5_SAMPLE_LEN]
    streqh  r0,[r3, #CHN_5_SAMPLE_POS] 
    ldreq   r4,[sp],#4
    bxeq    lr
    tst     r4,#0x10
    ldrneb  r4,[sp],#4
    bxne    lr
    @ DMC status is going from OFF to ON
    ldrb    r0,[r3, #APU_REGS+R_DMC_SMPADR]
    ldrb    r2,[r3, #APU_REGS+R_DMC_SMPLEN]
    mov     r0,r0,lsl#6
    mov     r2,r2,lsl#4
    orr     r0,r0,#0xC000
    add     r2,r2,#1
    ldrh    r1,[r3, #CHN_5_SAMPLE_LEN]
    strh    r0,[r3, #CHN_5_SAMPLE_ADDR]
    strh    r2,[r3, #CHN_5_SAMPLE_LEN]
    ldrh    r0,[r3, #CHN_5_SAMPLE_POS]
    cmp     r0,r1
    ldr     r0,[r3, #CHN_5_PERIOD]
    ldr     r2,[r3, #PER_SAMPLE_STEP]
    sub     r0,r0,r2
    str     r0,[r3, #CHN_5_POS]
    mov     r2,#0
    strh    r2,[r3, #CHN_5_SAMPLE_POS]
@    strh    r2,[r3, #CHN_5_OUTPUT]
@  strcsh    r2,[r3, #CHN_5_SAMPLE]
    ldr     r4,[sp],#4
    bx      lr
        
.apu_write_framecnt:
    mov     r0,#0
    mov     r2,#4
    tst     r1,#0x40
    moveq   r0,#1
    tst     r1,#0x80
    moveq   r2,#3
    strb    r0,[r3, #GENERATE_FRAME_IRQ]
    str     r2,[r3, #MAX_FRAME]
    ldreq   r4,[sp],#4
    bxeq    lr
    str     lr,[sp, #-4]!
    mov     r0,#1        
    bl      apu_half_frame
    ldr     lr,[sp],#4
    ldr     r4,[sp],#4
    mov     r0,#1
    b       apu_quarter_frame
            
.pool
.endfunc

@---------------------------------------------------------------------------------------
@ Private functions.
@ May not follow any standard calling convention, and should not
@ be called from the outside.
@---------------------------------------------------------------------------------------

@ r0 = envelope generator index (0 = pulse#1, 1 = pulse#2, 2 = noise)
@ r1 = channel index (0 = pulse#1, 1 = pulse#2, 3 = noise)
.type apu_step_envelope_generator, %function
.func apu_step_envelope_generator
apu_step_envelope_generator:
    stmfd   sp!,{r5,r7,lr}
    ldr     r3,=apu_state
    mov     r0,r0,lsl#5
    mov     r1,r1,lsl#2
    add     r0,r0,r3
    add     r1,r1,r3
    ldrb    r2,[r0, #EG_1_START]    @ eg->start
    ldrb    r1,[r1, #APU_REGS+R_PULSE1_DUTY_ENVE]   @ egCtrl
    tst     r2,r2
    bne     .start_envelope
    ldr     r5,[r0, #EG_1_STEP]
    ldrb    r2,[r0, #EG_1_OUTPUT]
    subs    r5,r5,#1
    str     r5,[r0, #EG_1_STEP]
    bne     .update_volume_ptr
    and     r5,r1,#0x0F
    add     r5,r5,#1 
    str     r5,[r0, #EG_1_STEP]     @ eg->step = (egCtrl & 0x0F) + 1
    ldrb    r2,[r0, #EG_1_OUTPUT]
    mov     r7,#0x20
    tst     r2,r2
    subnes  r2,r2,#1                @ if (eg->output) eg->output--
    movne   r7,#0 
    tst     r1,r7                   @ (egCtrl & ((eg->output) ? 0 : 0x20))
    movne   r2,#0x0F                @ Looping envelope
    strb    r2,[r0, #EG_1_OUTPUT]
    b       .update_volume_ptr
.start_envelope:
    and     r5,r1,#0x0F
    mov     r2,#0x0F
    add     r5,r5,#1
    mov     r3,#0
    strb    r2,[r0, #EG_1_OUTPUT]
    str     r5,[r0, #EG_1_STEP]
    strb    r3,[r0, #EG_1_START]    
.update_volume_ptr:
    tst     r1,#0x10
    ldr     r3,[r0, #EG_1_VOLUME_PTR]
    andne   r2,r1,#0x0F
    strh    r2,[r3]                 @ *(eg->channelVol) = (egCtrl & 0x10) ? (egCtrl & 0x0F) : eg->output
    ldmfd   sp!,{r5,r7,pc}
.pool   
.endfunc

    
@ r0 = force
.type apu_quarter_frame, %function
.func apu_quarter_frame
apu_quarter_frame:
    tst     r0,r0
    ldr     r3,=apu_state
    bne     .do_quarter_frame
    ldr     r1,[r3, #CURRENT_FRAME]
    cmp     r1,#3
    bxhi    lr
    
.do_quarter_frame:
    str     lr,[sp, #-4]!
    mov     r0,#0
    mov     r1,#0
    bl      apu_step_envelope_generator

    mov     r0,#1
    mov     r1,#1
    bl      apu_step_envelope_generator

    mov     r0,#2
    mov     r1,#3
    bl      apu_step_envelope_generator
    
    ldr     r3,=apu_state
    @ Step the triangle channel's linear counter
    ldrb    r1,[r3, #CHN_3_LINC_RELOAD]
    tst     r1,r1
    ldrb    r0,[r3, #APU_REGS+R_TRIANGLE_LIN]
    andne   r1,r0,#0x7F
    addne   r1,r1,#1
    ldreq   r1,[r3, #CHN_3_LINC_STEP]
    tst     r1,r1
    subne   r1,r1,#1
    str   r1,[r3, #CHN_3_LINC_STEP]
    
    tst     r0,#0x80
    moveq   r0,#0
    streqb  r0,[r3, #CHN_3_LINC_RELOAD]
    
    mvn     r2,#0
    ldr     r0,[r3, #CHN_3_LENC_STEP]
    tst     r1,r1
    moveq   r2,#0
    tstne   r0,r0
    moveq   r2,#0           @ r2 = (lincStep != 0 && lencStep != 0) ? 0xFFFFFFFF : 0
    strh    r2,[r3, #CHN_3_OUTPUT_MASK]
    ldr     pc,[sp],#4
.pool
.endfunc

    
@ r0 = force
.type apu_half_frame, %function
.func apu_half_frame
apu_half_frame:
    tst     r0,r0
    ldr     r3,=apu_state
    bne     .do_half_frame
    ldr     r1,[r3, #CURRENT_FRAME]
    cmp     r1,#3
    bxhi    lr              @ if (currentFrame >= 4) return
    ldr     r2,[r3, #MAX_FRAME]
    eor     r1,r1,r2
    ands    r1,r1,#1        
    bxne    lr              @ if ((currentFrame & 1) != (maxFrame & 1)) return
           
.do_half_frame:
    ldrb    r0,[r3, #APU_REGS+R_PULSE1_DUTY_ENVE]
    tst     r0,#0x20
    bne     .pulse2_half_frame
    ldr     r0,[r3, #CHN_1_LENC_STEP]
    tst     r0,r0
    mvn     r1,#0
    subnes  r0,r0,#1    
    str     r0,[r3, #CHN_1_LENC_STEP]
    moveq   r1,#0
    strh    r1,[r3, #CHN_1_OUTPUT_MASK]
    
.pulse2_half_frame:
    ldrb    r0,[r3, #APU_REGS+R_PULSE2_DUTY_ENVE]
    tst     r0,#0x20
    bne     .triangle_half_frame
    ldr     r0,[r3, #CHN_2_LENC_STEP]
    tst     r0,r0
    mvn     r1,#0
    subnes  r0,r0,#1    
    str     r0,[r3, #CHN_2_LENC_STEP]
    moveq   r1,#0
    strh    r1,[r3, #CHN_2_OUTPUT_MASK]

.triangle_half_frame:
    ldrb    r0,[r3, #APU_REGS+R_TRIANGLE_LIN]
    tst     r0,#0x80
    bne     .noise_half_frame
    ldr     r0,[r3, #CHN_3_LENC_STEP]
    tst     r0,r0
    subne   r0,r0,#1    
    str     r0,[r3, #CHN_3_LENC_STEP]
    @ The outputmask is updated elsewhere

.noise_half_frame:
    ldrb    r0,[r3, #APU_REGS+R_NOISE_ENVE]
    tst     r0,#0x20
    bne     .sweep1_half_frame
    ldr     r0,[r3, #CHN_4_LENC_STEP]
    tst     r0,r0
    mvn     r1,#0
    subnes  r0,r0,#1    
    str     r0,[r3, #CHN_4_LENC_STEP]
    moveq   r1,#0
    strh    r1,[r3, #CHN_4_OUTPUT_MASK]

.sweep1_half_frame:
    ldr     r0,[r3, #CHN_1_SWEEP_PERIOD]
    ldrb    r1,[r3, #CHN_1_SWEEP_RELOAD]
    tst     r0,r0
    addne   r0,r0,r1
    subne   r0,r0,#1    @ if (sweepPeriod && !sweepReload) sweepPeriod--
    bne     .sweep1_check_reload
    ldrb    r2,[r3, #APU_REGS+R_PULSE1_SWEEP]    
    mov     r1,#1
    tst     r2,#0x80
    beq     .sweep1_check_reload
    stmfd   sp!,{r4-r6}
    ldr     r4,[r3, #CHN_1_PERIOD]
    and     r5,r2,#7    @ Shift amount
    mov     r6,r4,lsr r5
    tst     r2,#0x08    @ Negate flag
    addeq   r6,r4,r6
    subne   r6,r4,r6
    tst     r6,#0x80000
    @ Todo: Write new value back to the corresponding APU regs? 
    streq   r6,[r3, #CHN_1_PERIOD]
    ldmfd   sp!,{r4-r6}
.sweep1_check_reload:
    tst     r1,r1
    movne   r1,#0
    ldrneb  r2,[r3, #APU_REGS+R_PULSE1_SWEEP] 
    movne   r2,r2,lsr#4
    andne   r2,r2,#7
    strb    r1,[r3, #CHN_1_SWEEP_RELOAD]
    addne   r2,r2,#1
    strne   r2,[r3, #CHN_1_SWEEP_PERIOD]

    ldr     r2,[r3, #CHN_1_PERIOD]
    movs    r2,r2,lsr#8
    beq     1f
    stmfd   sp!,{r2,r3}         @ save registers that will be clobbered by SWI_DIV
    ldr     r0,[r3, #CPU_CLOCK]
    add     r1,r2,#1
    mov     r1,r1,lsl#4
    swi     ARM_SWI_DIV         @ calculate frequency based on period
    ldmfd   sp!,{r2,r3}
1:
    str     r0,[r3, #PULSE_1_FREQ]
    ldr     r1,=wave_table_index
    ldrb    r0,[r1,r2]
    ldrb    r1,[r3, #CHN_1_DUTY_CYCLE]
    mov     r1,r1,lsl#11        @ r1 = dutyCycle * 0x800
    add     r1,r1,r0,lsl#7
    ldr     r0,=wave_table
    add     r1,r1,r0
    str     r1,[r3, #PULSE_1_WAVEFORM_PTR]
    
.sweep2_half_frame:
    ldr     r0,[r3, #CHN_2_SWEEP_PERIOD]
    ldrb    r1,[r3, #CHN_2_SWEEP_RELOAD]
    tst     r0,r0
    addne   r0,r0,r1
    subne   r0,r0,#1    @ if (sweepPeriod && !sweepReload) sweepPeriod--
    bne     .sweep2_check_reload
    ldrb    r2,[r3, #APU_REGS+R_PULSE2_SWEEP]    
    mov     r1,#1
    tst     r2,#0x80
    beq     .sweep2_check_reload
    stmfd   sp!,{r4-r6}
    ldr     r4,[r3, #CHN_2_PERIOD]
    and     r5,r2,#7    @ Shift amount
    mov     r6,r4,lsr r5
    tst     r2,#0x08    @ Negate flag
    addeq   r6,r4,r6
    subne   r6,r4,r6
    tst     r6,#0x80000
    @ Todo: Write new value back to the corresponding APU regs?
    streq   r6,[r3, #CHN_2_PERIOD]
    ldmfd   sp!,{r4-r6}
.sweep2_check_reload:
    tst     r1,r1
    movne   r1,#0
    ldrneb  r2,[r3, #APU_REGS+R_PULSE2_SWEEP] 
    movne   r2,r2,lsr#4
    andne   r2,r2,#7
    strb    r1,[r3, #CHN_2_SWEEP_RELOAD]
    addne   r2,r2,#1
    strne   r2,[r3, #CHN_2_SWEEP_PERIOD]    

    ldr     r2,[r3, #CHN_2_PERIOD]
    movs    r2,r2,lsr#8
    beq     1f
    stmfd   sp!,{r2,r3}         @ save registers that will be clobbered by SWI_DIV
    ldr     r0,[r3, #CPU_CLOCK]
    add     r1,r2,#1
    mov     r1,r1,lsl#4
    swi     ARM_SWI_DIV         @ calculate frequency based on period
    ldmfd   sp!,{r2,r3}
1:
    str     r0,[r3, #PULSE_2_FREQ]
    ldr     r1,=wave_table_index
    ldrb    r0,[r1,r2]
    ldrb    r1,[r3, #CHN_2_DUTY_CYCLE]
    mov     r1,r1,lsl#11        @ r1 = dutyCycle * 0x800
    add     r1,r1,r0,lsl#7
    ldr     r0,=wave_table
    add     r1,r1,r0
    str     r1,[r3, #PULSE_2_WAVEFORM_PTR]
    
    bx  lr
.pool
.endfunc


.type apu_sequencer_frame, %function
.func apu_sequencer_frame
apu_sequencer_frame:
    str     lr,[sp, #-4]!
    ldr     r0,=playCounter
    ldr     r1,[r0]
    add     r1,r1,#1
    and     r1,r1,#3
    str     r1,[r0]
    cmp     r1,#3
    bleq    call_execPlayRoutine
    
    mov     r0,#0
    bl      apu_half_frame
    
    mov     r0,#0
    bl      apu_quarter_frame
    
    ldr     r3,=apu_state
    ldr     r0,[r3, #CURRENT_FRAME]
    ldr     r1,[r3, #MAX_FRAME]
    add     r0,r0,#1
    cmp     r0,r1
    movhi   r0,#0
    str     r0,[r3, #CURRENT_FRAME]
    
    ldr     pc,[sp],#4
.pool    
.endfunc

.align 4
call_execPlayRoutine:
    ldr     r0,=nsfPlayer_executePlayRoutine
    bx      r0
.pool


.comm apu_state,384,4

SQUARE_WAVES:
    .byte 0,-1 ,0, 0, 0, 0, 0, 0
    .byte 0,-1,-1, 0, 0, 0, 0, 0
    .byte 0,-1,-1,-1,-1, 0, 0, 0
    .byte -1, 0, 0,-1,-1,-1,-1,-1

    
LENGTH_COUNTERS:
    .byte 10, 254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14
    .byte 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30

    
.align 2
NOISE_PERIODS:
    .short 4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068    @ NTSC
    .short 4, 8, 14, 30, 60, 88, 118, 148, 188, 236, 354, 472, 708,  944, 1890, 377     @ PAL

    
DMC_PERIODS:
    .short 428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54  @ NTSC
    .short 398, 354, 316, 298, 276, 236, 210, 198, 176, 148, 132, 118, 98, 78, 66, 50   @ PAL


PULSE_TABLE:
 .short 4,8,12,16,19,23,27,30,34,37,41,44,47,50,53,56
 .short 59,62,65,68,70,73,75,78,81,83,85,88,90,92,95

TND_TABLE:
.short 1,3,4,6,7,9,11,12,14,15,17,18,20,21,23,24
.short 25,27,28,30,31,32,34,35,37,38,39,40,42,43,44,46
.short 47,48,49,51,52,53,54,56,57,58,59,60,61,63,64,65
.short 66,67,68,69,71,72,73,74,75,76,77,78,79,80,81,82
.short 83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98
.short 99,100,101,101,102,103,104,105,106,107,108,108,109,110,111,112
.short 113,114,114,115,116,117,118,118,119,120,121,122,122,123,124,125
.short 125,126,127,128,128,129,130,131,131,132,133,134,134,135,136,136
.short 137,138,139,139,140,141,141,142,143,143,144,145,145,146,147,147
.short 148,148,149,150,150,151,152,152,153,153,154,155,155,156,156,157
.short 158,158,159,159,160,161,161,162,162,163,163,164,165,165,166,166
.short 167,167,168,168,169,169,170,171,171,172,172,173,173,174,174,175
.short 175,176,176,177,177,178,178,179,179,180,180

TRIANGLE_WAVE:
    .byte 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4,3,2,1,0
    .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,11,12,13,14,15


@ Lookup table which maps the 11-bit period value to the correct wavetable entry. 
.include "wave_table_index.s"

@ Table of bandlimited pulse waves.
@ The table spans 8 octaves (C1..B8), with 2 entries per octave.
@ With 4 possible duty cycles, this gives a total of 16 * 4 entries.
@ Each entry is 128 samples long, resulting in  total table size of 16*4*128 = 8192 bytes.
.include "wave_table.s"

@ NES APU register offsets (relative to 0x4000)
.equ R_PULSE1_DUTY_ENVE, 0x00
.equ R_PULSE1_SWEEP,     0x01
.equ R_PULSE1_PERLO,     0x02
.equ R_PULSE1_PERHI_LEN, 0x03
.equ R_PULSE2_DUTY_ENVE, 0x04
.equ R_PULSE2_SWEEP,     0x05
.equ R_PULSE2_PERLO,     0x06
.equ R_PULSE2_PERHI_LEN, 0x07
.equ R_TRIANGLE_LIN,     0x08
.equ R_TRIANGLE_PERLO,   0x0A
.equ R_TRIANGLE_PERHI_LEN,0x0B
.equ R_NOISE_ENVE,       0x0C
.equ R_NOISE_MODE_PER,   0x0E
.equ R_NOISE_LEN,        0x0F
.equ R_DMC_PER_LOOP,     0x10
.equ R_DMC_DIRLD,        0x11
.equ R_DMC_SMPADR,       0x12
.equ R_DMC_SMPLEN,       0x13
.equ R_STATUS,           0x15
.equ R_FRAMECNT,         0x17

@ apu_state offsets for pulse wave channel #1
.equ CHN_1_POS,         0x00    @ UINT32
.equ CHN_1_PERIOD,      0x04    @ UINT32
.equ CHN_1_LENC_STEP,   0x08    
.equ CHN_1_TO_DAC,      0x0C    @ INT16
.equ CHN_1_RESERVED1,   0x0E
.equ CHN_1_WAVE_STEP,   0x10
.equ CHN_1_SWEEP_PERIOD,0x14    @ INT32
.equ CHN_1_VOLUME,      0x18    @ UINT16
.equ CHN_1_OUTPUT_MASK, 0x1A    @ UINT16
.equ CHN_1_SWEEP_RELOAD,0x1C    @ BOOL
.equ CHN_1_DUTY_CYCLE,  0x1D    @ UINT8
.equ CHN_1_OUTPUT,      0x1E    @ INT8
.equ CHN_1_RESERVED2,   0x1F    

@ apu_state offsets for pulse wave channel #2
.equ CHN_2_POS,         0x20    @ UINT32
.equ CHN_2_PERIOD,      0x24    @ UINT32
.equ CHN_2_LENC_STEP,   0x28    
.equ CHN_2_TO_DAC,      0x2C    @ INT16
.equ CHN_2_RESERVED1,   0x2E
.equ CHN_2_WAVE_STEP,   0x30
.equ CHN_2_SWEEP_PERIOD,0x34    @ INT32
.equ CHN_2_VOLUME,      0x38    @ UINT16
.equ CHN_2_OUTPUT_MASK, 0x3A    @ UINT16
.equ CHN_2_SWEEP_RELOAD,0x3C    @ BOOL
.equ CHN_2_DUTY_CYCLE,  0x3D    @ UINT8
.equ CHN_2_OUTPUT,      0x3E    @ INT8
.equ CHN_2_RESERVED2,   0x3F    

@ apu_state offsets for the triangle channel
.equ CHN_3_POS,         0x40    @ UINT32
.equ CHN_3_PERIOD,      0x44    @ UINT32
.equ CHN_3_LENC_STEP,   0x48    
.equ CHN_3_LINC_STEP,   0x4C
.equ CHN_3_WAVE_STEP,   0x50
.equ CHN_3_TO_DAC,      0x54    @ INT16
.equ CHN_3_RESERVED1,   0x56    
.equ CHN_3_VOLUME,      0x58    @ UINT16
.equ CHN_3_OUTPUT_MASK, 0x5A    @ UINT16
.equ CHN_3_LINC_RELOAD, 0x5C    @ BOOL
.equ CHN_3_DUTY_CYCLE,  0x5D    @ UINT8
.equ CHN_3_OUTPUT,      0x5E    @ INT8
.equ CHN_3_RESERVED2,   0x5F  

@ apu_state offsets for the noise channel
.equ CHN_4_POS,         0x60    @ UINT32
.equ CHN_4_PERIOD,      0x64    @ UINT32
.equ CHN_4_LENC_STEP,   0x68    
.equ CHN_4_LFSR,        0x6C    @ UINT16
.equ CHN_4_TO_DAC,      0x6E    @ INT16
.equ CHN_4_RESERVED2,   0x70
.equ CHN_4_RESERVED3,   0x74    
.equ CHN_4_VOLUME,      0x78    @ UINT16
.equ CHN_4_OUTPUT_MASK, 0x7A    @ UINT16
.equ CHN_4_RESERVED4,   0x7C  
.equ CHN_4_RESERVED5,   0x7D  
.equ CHN_4_OUTPUT,      0x7E    @ INT8
.equ CHN_4_RESERVED5,   0x7F  

@ apu_state offsets for the DMC channel
.equ CHN_5_POS,         0x80    @ UINT32
.equ CHN_5_PERIOD,      0x84    @ UINT32
.equ CHN_5_SAMPLE_POS,  0x88    @ UINT16    
.equ CHN_5_SAMPLE_LEN,  0x8C    @ UINT16
.equ CHN_5_TO_DAC,      0x90    @ INT16
.equ CHN_5_RESERVED1,   0x92
.equ CHN_5_RESERVED2,   0x94    
.equ CHN_5_SAMPLE_ADDR, 0x98    @ UINT16
.equ CHN_5_OUTPUT_MASK, 0x9A    @ UINT16
.equ CHN_5_SAMPLE,      0x9C    @ UINT8
.equ CHN_5_BITS_REMAINING,0x9D  @ UINT8
.equ CHN_5_OUTPUT,      0x9E    @ INT16

@ apu_state offsets for the pulse wave #1 envelope generator
.equ EG_1_POS,          0xA0    @ UINT32
.equ EG_1_PERIOD,       0xA4
.equ EG_1_STEP,         0xA8
.equ EG_1_MAX_STEP,     0xAC
.equ EG_1_VOLUME_PTR,   0xB0    @ UINT16*
.equ EG_1_OUTPUT,       0xB4    @ UINT8
.equ EG_1_START,        0xB5    @ BOOL
.equ EG_1_USE,          0xB6    @ BOOL
.equ EG_1_RESERVED,     0xB7

@ apu_state offsets for the pulse wave #2 envelope generator
.equ EG_2_POS,          0xC0    @ UINT32
.equ EG_2_PERIOD,       0xC4
.equ EG_2_STEP,         0xC8
.equ EG_2_MAX_STEP,     0xCC
.equ EG_2_VOLUME_PTR,   0xD0    @ UINT16*
.equ EG_2_OUTPUT,       0xD4    @ UINT8
.equ EG_2_START,        0xD5    @ BOOL
.equ EG_2_USE,          0xD6    @ BOOL
.equ EG_2_RESERVED,     0xD7

@ apu_state offsets for the noise envelope generator
.equ EG_3_POS,          0xE0    @ UINT32
.equ EG_3_PERIOD,       0xE4
.equ EG_3_STEP,         0xE8
.equ EG_3_MAX_STEP,     0xEC
.equ EG_3_VOLUME_PTR,   0xF0    @ UINT16*
.equ EG_3_OUTPUT,       0xF4    @ UINT8
.equ EG_3_START,        0xF5    @ BOOL
.equ EG_3_USE,          0xF6    @ BOOL
.equ EG_3_RESERVED,     0xF7

.equ PULSE_1_WAVEFORM_PTR, 0x100 @ INT8*
.equ PULSE_2_WAVEFORM_PTR, 0x104 @ INT8*

.equ PER_SAMPLE_STEP,   0x108    @ UINT32
.equ HALF_PER_SAMPLE_STEP,0x10C  @ UINT32

.equ CURRENT_FRAME,     0x110    @ INT32
.equ MAX_FRAME,         0x114    @ INT32

.equ CYCLES_PER_FRAME,  0x118    @ UINT32
.equ SCALED_CYCLES_PER_FRAME,0x11C  @ UINT32

.equ APU_REGS,          0x120   @ UINT8[0x18]

.equ CYCLE_COUNT,       0x140   @ UINT32

.equ CLOCK_SEQUENCER,   0x144   @ BOOL
.equ GENERATE_FRAME_IRQ,0x145   @ BOOL
.equ PAL_MODE,          0x146   @ BOOL

.equ PULSE_1_FREQ, 0x150 @ UINT32
.equ PULSE_2_FREQ, 0x154 @ UINT32
.equ CPU_CLOCK,    0x158 @ UINT32
