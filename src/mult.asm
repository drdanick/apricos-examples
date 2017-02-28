; Multiplication demonstration
; 
; This program will multiply the
; value in $a0 by the value in $a1.
; The result will be stored in $a2.
;
; For this example, we will multiply 2 by 3.
;
; NOTE: This example assumes the second operand is non zero
;

; Load operands
ASET 0         ; Load first operand (0x02) into $a0
ADD 0x02

ASET 1         ; Load second operand (0x03) into $a1
ADD 0x03

; Since addition is faster than subtraction (as of Apricos V0.7), 
; we will take the 2s compliment negation of $a1, and use that as 
; our incrementing variable. I.e. we will negate $a1, then increment 
; it until it is equal to zero.
;
NOT            ; 2s compliment negation of $a1
ADD 0x01

; Prepare output
ASET 2
AND 0x00       ; Zero $a2

; Perform multiplication
;
; We do this by repeatedly adding $a0 to $a2, as well as 
; repeatedly incrementing $a1. As soon as $a1 is non-negative, 
; we stop. $a2 will then hold our result.
;
LOOPST:
    ASET 0     ; Place first operand on the stack
    SPUSH

    ASET 2     ; Add first operand to our result
    SPOP ADD

    ASET 1     ; Increment our counter and loop if still negative
    ADD 1
BRn LOOPST
