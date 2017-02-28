; Simple ADD demonstration
;
; This program will push the values 0xA0 and 0x0A into
; the stack, then pop both values into the second accumulator
; with the ADD operation. The second accumulator will then hold 0xAA.
;
ASET 0

LAR 0xA0  ; Load value of 0xA0 into $a0...
SPUSH     ; ...and push it into the stack

LAR 0x0A  ; Load value of 0x0A into $a0...
SPUSH     ; ...and push it into the stack

ASET 1    ; Pop 0x0A from the stack into $a1...
SPOP
SPOP ADD  ; ...then pop 0xA0 from the stack and add it to $a1
