.global SONG_POINTERS
.global SONG_SIZES
.global NUM_SONGS

.section .text

.align 4

SONG1:  .incbin "songs/za909 - Bubble Crab in Sunsoft style.nsf"
SONG2:  .incbin "songs/Shadow_of_the_Ninja.nsf"
SONG3:  .incbin "songs/Journey_to_Silius.nsf"
SONG4:  .incbin "songs/Silver_Surfer.nsf"
SONG5:  .incbin "songs/Legend_of_Zelda.nsf"
SONG6:  .incbin "songs/Ninja_Gaiden_3.nsf"
SONG7:  .incbin "songs/Duck_Tales.nsf"
SONG8:  .incbin "songs/T_M_N_T_1.nsf"
SONG9:  .incbin "songs/Mega_Man_2.nsf"
SONG10:  .incbin "songs/Smurfs.nsf"
SONG11:  .incbin "songs/Super_Mario_Bros_3.nsf"
SONG12:  .incbin "songs/Castlevania.nsf"

SONG_END:

.align 4
SONG_POINTERS:
.word SONG1
.word SONG2
.word SONG3
.word SONG4
.word SONG5
.word SONG6
.word SONG7
.word SONG8
.word SONG9
.word SONG10
.word SONG11
.word SONG12

SONG_SIZES:
.word SONG2  - SONG1
.word SONG3  - SONG2
.word SONG4  - SONG3
.word SONG5  - SONG4
.word SONG6  - SONG5
.word SONG7  - SONG6
.word SONG8  - SONG7
.word SONG9  - SONG8
.word SONG10  - SONG9
.word SONG11  - SONG10
.word SONG12  - SONG11
.word SONG_END - SONG12

NUM_SONGS:
.word (SONG_SIZES - SONG_POINTERS) / 4
