; Simple ADD demonstration
;
; This program will push the values 0xA0 and 0x0A into
; the stack, then pop both values into the second accumulator 
; with the ADD operation. The second accumulator will then hold 0xAA.
;
ASET 0    ; select and zero $a0
AND 0x00

ADD 0x0A  ; Push 0xA0 to the stack
SHFl      ; We want 0xA0, so shift left 4 times
SHFl
SHFl
SHFl
SPUSH

AND 0x00  ; Zero $a

ADD 0x0A  ; Push 0x0A to the stack
SPUSH

ASET 1    ; Do the following to $a1
SPOP      ; Pop 0x0A from the stack, then pop/add 0xA0
SPOP ADD
