; Conway's Game of Life
; =====================
;
; This program runs Conway's Game of Life on the full 80x30 screen of the
; Apricos terminal emulator (apricosterm). It starts from a Gosper glider
; gun, which fires a new glider every 30 generations.
;
; It is a standalone program: it doesn't need Apricot OS, and it starts at
; the CPU's reset vector (address 0x0000). It needs apricosterm to show its
; output; see README.md for how to run it.
;
;
; The rules of Life
; -----------------
;
; The board is a grid of cells, each either alive or dead. Every generation,
; all cells are updated at once, based on their 8 neighbours:
;
;   - A live cell with 2 or 3 live neighbours stays alive.
;   - A dead cell with exactly 3 live neighbours comes alive.
;   - Every other cell dies, or stays dead.
;
; This program counts the live cells in the 3x3 block around a cell,
; *including the cell itself*. Call that total T. The rules above then
; become:
;
;   - T == 3: the cell is alive next generation (either a dead cell with 3
;     neighbours, or a live cell with 2).
;   - T == 4: the cell keeps its current state (a live cell with 3
;     neighbours stays alive; a dead cell with 4 stays dead).
;   - Anything else: the cell is dead next generation.
;
; Counting the whole block means we never have to subtract the centre cell.
;
;
; Counting with a sliding window
; ------------------------------
;
; Reading all 9 cells of every 3x3 block would be slow, because each cell
; would be read 9 times. Instead, the program walks along a row keeping
; three "column sums": the number of live cells in each of the 3-cell
; columns of the block (rows r-1, r and r+1):
;
;         c-1  c  c+1
;   r-1  [ . ][ # ][ . ]
;   r    [ . ][ # ][ # ]
;   r+1  [ # ][ . ][ . ]
;          L    M    R      L = 1, M = 2, R = 1, so T = L + M + R = 4
;
; Moving one column to the right, the old M becomes the new L, the old R
; becomes the new M, and only the new R has to be read from memory: 3
; cells instead of 9.
;
;
; Memory layout
; -------------
;
; There are two boards: the current generation is read from one while the
; next generation is written to the other. Then they swap roles.
;
;   Board A: pages 0x40-0x5F   (0x4000-0x5FFF)
;   Board B: pages 0x60-0x7F   (0x6000-0x7FFF)
;
; Each row of a board is a whole 256-byte page, and each cell is one byte
; (0 = dead, 1 = alive). So the address of a cell is simply:
;
;   high byte = board base page + row
;   low byte  = column
;
; This suits the Apricos CPU well. Memory is only reached through the 16-bit
; $mr register, whose two halves can be set separately (STah / STal), so
; moving down a row is just a change to the high byte, and moving one
; column right is just a change to the low byte.
;
; The boards are not part of conway.bin: they live in RAM that the
; simulator zeroes at reset, so both boards start out empty.
;
;
; Wrapping around the edges: ghost cells
; --------------------------------------
;
; The board wraps around: a glider leaving on the right comes back on the
; left, and one leaving at the bottom comes back at the top (the board is a
; torus).
;
; Only rows 1-30 and columns 1-80 are shown on screen. Around them is a
; border of "ghost" cells: rows 0 and 31, and columns 0 and 81. Before each
; generation, the edges of the board are copied into the ghost border on
; the opposite side:
;
;   column 80 -> column 0,   column 1 -> column 81   (for every row)
;   row 30    -> row 0,      row 1    -> row 31      (whole rows, which
;                                                     also fixes the corners)
;
; After that, every visible cell has all 8 of its neighbours right next to
; it in memory, and the counting loop needs no special cases for the edges.
;
; Note: the gliders travel diagonally down and to the right. Because the
; board wraps around, they eventually come back around and crash into the
; gun, and the board turns into chaos. That's part of the fun.
;
;
; Drawing on the terminal
; -----------------------
;
; Port 7 sends bytes to the terminal. Each byte is either a command or an
; argument for the command before it. The commands used here are:
;
;   03          End repeat mode (harmless if repeat mode isn't on)
;   0C c        Set the text colour (c = 0-15; 10 is green)
;   10 00       Hide the cursor
;   12 x        Clear the screen (x is ignored)
;   0E r        Move the cursor to row r (0-29)
;   0F c        Move the cursor to column c (0-79)
;   7F 01       Repeat mode for command 01: every byte that follows is
;               printed as a character, until an 03 is sent.
;
; Command 01 prints a character *without* wrapping to the next line. That
; matters: printing the last cell of the screen (row 29, column 79) with the
; normal print command (00) would move the cursor off the end and scroll
; the whole screen up by a line.
;
; Each new generation is drawn row by row, as it is computed: move the
; cursor to the start of the row, then print one character per cell ('#'
; for alive, a space for dead). The starting pattern itself is never drawn;
; the first thing on screen is generation 1.
;
;
; Register map
; ------------
;
; The CPU has 16 accumulators, but only the one selected with ASET can be
; used at a time ($ar). The program uses them like variables:
;
;   $a0  - Base page of the current board (0x40 or 0x60)
;   $a1  - Base page of the next board (0x60 or 0x40)
;   $a2  - Current row, r (1-30)
;   $a3  - Current column, c (1-80)
;   $a4  - The 3x3 total, T
;   $a5  - The cell's new state (0 or 1)
;   $a6  - Column loop counter (counts up from -80 to 0)
;   $a7  - Row loop counter (counts up from -30 to 0)
;   $a8  - L: the column sum of column c-1
;   $a9  - M: the column sum of column c
;   $a10 - Page of row r-1 in the current board
;   $a11 - Page of row r in the current board
;   $a13 - Page of row r in the next board
;   $a14 - The column that COLUMN_SUM reads next
;   $a15 - Scratch, and R: the column sum of column c+1
;
; ($a6-$a9 are also used as scratch while the program starts up.)
;
; Loops count with negative numbers because the CPU has no compare
; instruction: a counter that starts at -80 and goes up by 1 each time
; reaches 0 after 80 steps, and ADD sets the Z flag when it does.
;
;
; Code layout
; -----------
;
; An immediate branch (BRz LABEL, JMP LABEL, ...) only changes the low byte
; of the instruction pointer, so it can only reach the 256-byte page it is
; in. The program is therefore split into sections that each fit in a page,
; and each loop stays inside its section:
;
;   Page 0: Start-up (terminal set-up, placing the glider gun) and the
;           glider gun's cell table
;   Page 1: GHOSTS, which fills in the ghost border of the current board
;   Page 2: GENERATION, which computes and draws the next generation
;
; `.padseg 0` pads each section out to the end of its page. To get from one
; section to the next, the code loads the target's full 16-bit address into
; $mr and uses a bare JMP, which jumps to $mr (a "far jump").
;
; Speed: the simulator runs roughly 100,000 instructions a second, and
; there are 2400 cells, so every instruction in the cell loop costs about
; 0.025 seconds per generation. Expect a generation every second or two.
;

#segment 0


;
; COLUMN_SUM
;
; Counts the live cells of one column of a 3x3 block: rows r-1, r and r+1
; of column $a14, in the current board. Row r-1's page is in $a10.
;
; The three rows are consecutive pages, so after the first cell, $mr is
; moved down a row by adding 1 to its high byte (LDah / ADD 1 / STah).
;
; Returns the sum in $a15, and leaves $a15 selected.
;
#macro COLUMN_SUM {
    ASET 10
    STah            ; $mr = row r-1 : ...
    ASET 14
    STal            ; $mr = row r-1 : column

    ASET 15
    LD              ; Load the top cell...
    SPUSH           ; ...and keep it on the stack
    LDah
    ADD 1
    STah            ; $mr = row r : column
    LD              ; Load the middle cell...
    SPUSH           ; ...and keep it on the stack
    LDah
    ADD 1
    STah            ; $mr = row r+1 : column
    LD              ; Load the bottom cell

    SPOP ADD
    SPOP ADD        ; $a15 = top + middle + bottom
}


; =========================================================================
; Page 0: start-up
; =========================================================================

START:
    ; Select an accumulator first. ASET sets the flags, and until some
    ; instruction has set them, no branch (not even JMP) is ever taken.
    ASET 15

    ; Set up the terminal: hide the cursor, clear the screen and switch to
    ; green text. Only LAR can load a full 8-bit value; it is 2 bytes and
    ; doesn't set flags.
    LAR 0x03
    PRTout 7        ; 03: end any repeat mode
    LAR 0x10
    PRTout 7
    AND 0
    PRTout 7        ; 10 00: hide the cursor
    LAR 0x12
    PRTout 7
    PRTout 7        ; 12 12: clear the screen
    LAR 0x0C
    PRTout 7
    LAR 10
    PRTout 7        ; 0C 0A: green text

    ; Board A (page 0x40) starts as the current board, board B (0x60) as
    ; the next one.
    ASET 0
    LAR 0x40
    ASET 1
    LAR 0x60

    ; Place the glider gun on board A. GUN_TABLE is a list of (row, column)
    ; pairs, one per live cell, ending with a row of 0. $a6 holds the low
    ; byte of the address of the current pair.
    ASET 6
    LARl GUN_TABLE

STAMP_LOOP:
    LAh GUN_TABLE   ; $mr high byte = the table's page
    ASET 6
    STal            ; $mr = address of the next pair
    ASET 7
    LD              ; $a7 = row
    BRz STAMP_DONE  ; A row of 0 ends the table

    ASET 6
    ADD 1
    STal
    ASET 8
    LD              ; $a8 = column
    ASET 6
    ADD 1           ; $a6 = low byte of the following pair

    ; $mr = (board A base + row) : column
    ASET 0
    SPUSH
    ASET 7
    SPOP ADD
    STah
    ASET 8
    STal

    ; Make the cell alive
    ASET 9
    AND 0
    ADD 1
    ST
    JMP STAMP_LOOP

STAMP_DONE:
    ; Start the main loop (a far jump: GHOSTS is in another page).
    LAh GHOSTS
    LAl GHOSTS
    JMP


;
; The Gosper glider gun: (row, column) of each of its 36 live cells, using
; board coordinates (the top left visible cell is row 1, column 1). The gun
; is 36 cells wide and 9 tall, and its top left corner is at row 2,
; column 2.
;
; The table is read by stepping only the low byte of the address, so it
; must not cross a page boundary.
;
GUN_TABLE:
    .fill 2
    .fill 26
    .fill 3
    .fill 24
    .fill 3
    .fill 26
    .fill 4
    .fill 14
    .fill 4
    .fill 15
    .fill 4
    .fill 22
    .fill 4
    .fill 23
    .fill 4
    .fill 36
    .fill 4
    .fill 37
    .fill 5
    .fill 13
    .fill 5
    .fill 17
    .fill 5
    .fill 22
    .fill 5
    .fill 23
    .fill 5
    .fill 36
    .fill 5
    .fill 37
    .fill 6
    .fill 2
    .fill 6
    .fill 3
    .fill 6
    .fill 12
    .fill 6
    .fill 18
    .fill 6
    .fill 22
    .fill 6
    .fill 23
    .fill 7
    .fill 2
    .fill 7
    .fill 3
    .fill 7
    .fill 12
    .fill 7
    .fill 16
    .fill 7
    .fill 18
    .fill 7
    .fill 19
    .fill 7
    .fill 24
    .fill 7
    .fill 26
    .fill 8
    .fill 12
    .fill 8
    .fill 18
    .fill 8
    .fill 26
    .fill 9
    .fill 13
    .fill 9
    .fill 17
    .fill 10
    .fill 14
    .fill 10
    .fill 15
    .fill 0         ; End of table

.padseg 0


; =========================================================================
; Page 1: GHOSTS - fill in the ghost border of the current board
; =========================================================================

GHOSTS:
    ; Copy column 80 into column 0, and column 1 into column 81, for rows
    ; 1-30. $a2 walks over the row pages, and $a3 counts the rows.
    ASET 0
    SPUSH
    ASET 2
    SPOP
    ADD 1           ; $a2 = page of row 1
    ASET 3
    LAR 0xE2        ; $a3 = -30: counts up to 0, one step per row

GHOSTS_COLUMNS:
    ASET 2
    STah            ; $mr high byte = this row's page
    ASET 15
    LAl 80
    LD
    LAl 0
    ST              ; column 0 = column 80
    LAl 1
    LD
    LAl 81
    ST              ; column 81 = column 1

    ASET 2
    ADD 1           ; Next row's page
    ASET 3
    ADD 1
    BRnp GHOSTS_COLUMNS

    ; Copy row 30 into row 0. $a10 is the page to copy from, $a11 the page
    ; to copy to, and $a3 is the column. $a3 is 0 after the loop above, and
    ; the copy runs until it wraps around to 0 again, so it copies all 256
    ; bytes of the page.
    ASET 0
    SPUSH
    SPUSH
    ASET 11
    SPOP            ; $a11 = page of row 0
    ASET 10
    LAR 30
    SPOP ADD        ; $a10 = page of row 30

GHOSTS_TOP:
    ASET 10
    STah
    ASET 3
    STal            ; $mr = row 30 : column
    ASET 15
    LD
    ASET 11
    STah            ; $mr = row 0 : column
    ASET 15
    ST
    ASET 3
    ADD 1
    BRnp GHOSTS_TOP ; Stop when the column wraps around to 0

    ; Copy row 1 into row 31, in the same way.
    ASET 0
    SPUSH
    SPUSH
    ASET 10
    SPOP
    ADD 1           ; $a10 = page of row 1
    ASET 11
    LAR 31
    SPOP ADD        ; $a11 = page of row 31

GHOSTS_BOTTOM:
    ASET 10
    STah
    ASET 3
    STal            ; $mr = row 1 : column
    ASET 15
    LD
    ASET 11
    STah            ; $mr = row 31 : column
    ASET 15
    ST
    ASET 3
    ADD 1
    BRnp GHOSTS_BOTTOM

    ; Now compute the next generation (a far jump).
    LAh GENERATION
    LAl GENERATION
    JMP

.padseg 0


; =========================================================================
; Page 2: GENERATION - compute and draw the next generation
; =========================================================================

GENERATION:
    ; Start at row 1. $a7 counts the 30 rows, from -30 up to 0.
    ASET 2
    AND 0
    ADD 1           ; r = 1
    ASET 7
    LAR 0xE2        ; -30

ROW_LOOP:
    ; Work out the pages of the rows we need:
    ;   $a11 = current board, row r
    ;   $a10 = current board, row r-1
    ;   $a13 = next board, row r
    ASET 0
    SPUSH
    ASET 2
    SPUSH
    ASET 11
    SPOP
    SPOP ADD        ; $a11 = current base + r
    SPUSH
    ASET 10
    SPOP
    NOT             ; There's no subtract instruction, but
    ADD 1           ; ~(~x + 1) = x - 1
    NOT             ; $a10 = $a11 - 1
    ASET 1
    SPUSH
    ASET 2
    SPUSH
    ASET 13
    SPOP
    SPOP ADD        ; $a13 = next base + r

    ; Move the terminal's cursor to the start of screen row r-1, then turn
    ; on repeated printing without wrapping: 03, 0E r-1, 0F 00, 7F 01.
    ASET 15
    LAR 0x03
    PRTout 7        ; End the previous row's repeat mode
    LAR 0x0E
    PRTout 7
    ASET 2
    SPUSH
    ASET 15
    SPOP
    NOT
    ADD 1
    NOT             ; $a15 = r - 1
    PRTout 7        ; 0E r-1: cursor row
    LAR 0x0F
    PRTout 7
    AND 0
    PRTout 7        ; 0F 00: cursor column 0
    LAR 0x7F
    PRTout 7
    AND 0
    ADD 1
    PRTout 7        ; 7F 01: print characters without wrapping

    ; Fill the sliding window for the first cell (column 1): L is the sum
    ; of column 0, M of column 1. The loop reads R itself.
    ASET 14
    AND 0           ; Column 0
    COLUMN_SUM
    SPUSH
    ASET 8
    SPOP            ; L = sum of column 0
    ASET 14
    ADD 1           ; Column 1
    COLUMN_SUM
    SPUSH
    ASET 9
    SPOP            ; M = sum of column 1
    ASET 14
    ADD 1           ; Column 2: the first R

    ; Start at column 1. $a6 counts the 80 columns, from -80 up to 0.
    ASET 3
    AND 0
    ADD 1           ; c = 1
    ASET 6
    LAR 0xB0        ; -80

CELL_LOOP:
    ; R = sum of column c+1
    COLUMN_SUM

    ; T = L + M + R
    SPUSH           ; Stack: R
    ASET 9
    SPUSH           ; Stack: R, M
    ASET 8
    SPUSH           ; Stack: R, M, L
    ASET 4
    SPOP
    SPOP ADD
    SPOP ADD        ; T = L + M + R; the stack is empty again

    ; Slide the window one column right, ready for the next cell
    ASET 9
    SPUSH
    ASET 8
    SPOP            ; L = M
    ASET 15
    SPUSH
    ASET 9
    SPOP            ; M = R
    ASET 14
    ADD 1           ; The next R is one column further right

    ; Apply the rules. XOR with a constant gives 0 only if the value equals
    ; that constant. The second XOR undoes the first one (^3) and tests for
    ; 4 at the same time (^4), because 3 ^ 4 = 7.
    ASET 4
    XOR 3
    BRz CELL_LIVE   ; T == 3: alive
    XOR 7
    BRz CELL_KEEP   ; T == 4: unchanged

    ASET 5          ; Anything else: dead
    AND 0
    JMP CELL_STORE

CELL_KEEP:
    ASET 11
    STah
    ASET 3
    STal            ; $mr = current board, row r : column c
    ASET 5
    LD              ; $a5 = the cell's current state
    JMP CELL_STORE

CELL_LIVE:
    ASET 5
    AND 0
    ADD 1

CELL_STORE:
    ; Store the new state in the next board, at (r, c)
    ASET 13
    STah
    ASET 3
    STal
    ASET 5
    ST

    ; Draw it: '#' if alive, a space if dead
    ASET 15
    LAR 0x20        ; ' '
    ASET 5          ; Sets the flags from the new state
    BRz CELL_DRAW
    ASET 15
    LAR 0x23        ; '#'
CELL_DRAW:
    ASET 15
    PRTout 7

    ; Next column
    ASET 3
    ADD 1           ; c
    ASET 6
    ADD 1
    BRnp CELL_LOOP  ; Until 80 columns are done

    ; Next row
    ASET 2
    ADD 1           ; r
    ASET 7
    ADD 1
    BRnp ROW_LOOP   ; Until 30 rows are done

    ; The generation is done: swap the two boards, so the one we just wrote
    ; becomes the current board.
    ASET 0
    SPUSH
    ASET 1
    SPUSH
    ASET 0
    SPOP            ; $a0 = old $a1
    ASET 1
    SPOP            ; $a1 = old $a0

    ; Go round again (a far jump)
    LAh GHOSTS
    LAl GHOSTS
    JMP
