apricos-examples
================

Example apricos programs. The examples are in `src/`:

| Example      | What it shows                                                   | Needs the terminal? |
|--------------|-----------------------------------------------------------------|---------------------|
| `add.asm`    | Adding two numbers using the stack                              | No                  |
| `mult.asm`   | Multiplying by repeated addition, with a loop                   | No                  |
| `conway.asm` | Conway's Game of Life, drawn on the terminal, from a glider gun | Yes                 |

All three are standalone programs: they don't need Apricot OS, and run
directly in the simulator from address 0.


Requirements
------------

To assemble the examples, you will need:

- [apricosasm](http://github.com/drdanick/apricosasm-java/) 1.3+

To run the examples, you will need:

- [apricosim](http://github.com/drdanick/apricosim-curses/) 0.9+

`conway` also needs the terminal emulator, and a simulator built with TTY
emulation (`aprsim -h` should list the `-f` option):

- [apricosterm](http://github.com/drdanick/apricosterm/)


Assembling
----------

From the `src` folder, run the assembler on all the examples:

```
cd src
java -jar /path/to/apricosasm.jar *.asm
```

This writes one `.bin` file per example (`add.bin`, `mult.bin` and
`conway.bin`).


Executing the examples
----------------------

In the simulator, `m` cycles between the three modes (state, instruction
and run) and `space` steps, or starts and stops a run. `q` quits when the
simulator isn't running, and `F1` quits at any time.

### add and mult

These examples don't print anything: you watch them work by stepping
through them and looking at the accumulators in the simulator's register
display.

```
aprsim add.bin
aprsim mult.bin
```

Press `m` once to switch to instruction mode, then press `space` to run one
instruction at a time. `add` leaves `0xAA` in `$a1`, and `mult` leaves
`2 x 3 = 6` in `$a2`.

### conway

`conway` draws on the terminal emulator, so it needs two terminal windows:
one for `apricosterm`, which shows the board, and one for the simulator.
They talk to each other through a named pipe (FIFO), which both programs
must be given with `-f`.

1. In the first window, start the terminal emulator:

   ```
   apricosterm -f /tmp/apricos_fifo
   ```

2. In the second window, start the simulator with the same FIFO:

   ```
   aprsim -f /tmp/apricos_fifo conway.bin
   ```

   The simulator waits for the terminal to connect before it starts.

3. In the simulator, press `m` twice to switch to run mode, then `space` to
   start running.

The terminal shows an 80x30 board that starts with a Gosper glider gun,
which fires a glider every 30 generations. The edges of the board wrap
around, so the gliders eventually come back around and crash into the gun.
Expect about a generation every two seconds: the simulator runs roughly
100,000 instructions a second.

Press `space` in the simulator to pause, and `F1` to quit.


Licence
-------

See LICENCE for details
