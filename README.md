# x-tracker

A music tracker written in [x-lang](https://github.com/jonruttan/x-lang),
loaded as a lang: songs of patterns and instruments, edited on the
terminal and heard through SDL's audio.

    x -l tracker -- [OPTIONS] [edit] [FILE]
    x -l tracker -- [OPTIONS] play FILE
    x -l tracker -- list FILE

      -s, --song NAME    the song to edit or play (the file's first)
      -w, --waves FILE   read the (wave ...) forms of FILE too; again for another
      -l, --loop         play the song over and over, until q
      -n, --no-sound     edit without opening the audio
      -V, --version      print the version and exit
      -h, --help         print the help and exit

The songs are the ones x/audio/tracker plays, and x-roguelike's music
is made of: a file is any `.xon` file of `(song ...)` forms, with the
`(wave NAME AMP ...)` forms their instruments name.  `data/demo.xon` is
one to start from:

    x -l tracker -- data/demo.xon

`play` plays a song once through, or with `--loop` until q, the pattern
heard written to standard error; `list` prints each song of a file with
how long it lasts, its patterns and its order.  With no operands
`x -l tracker` is the lang's REPL.

To edit x-roguelike's delve music, whose waves are kept in another file:

    x -l tracker -- -w data/delve/sounds.xon data/delve/music.xon

A file can hold its own waves, so it needs no other: `:waves keep`
copies each wave its songs borrow from a `-w` file into it, as
`(wave NAME AMP ...)` forms before its first song, and `:w` writes
them.  A wave's numbers are the strengths of its harmonics, the
fundamental first: `(wave hollow 6 0 2 0 1)`.

## The editor

A pattern fills the screen, a row a line and a channel a column headed
by its instrument; above it are the song's tempo, the octave notes are
typed in, and the order, the pattern edited in brackets and the one
being heard marked `>`.  Notes are typed on two rows of the keyboard as
on a piano's keys:

    z s x d c v g b h n j m ,    C to C, in the octave
    q 2 w 3 e r 5 t 6 y 7 u i    the octave above

and heard as they are typed.  The other keys:

    .  or Delete    hold                 -    let go
    < >             octave down, up      { }  the step: rows moved after a note
    arrows Tab PgUp PgDn Home End        move
    Enter           edit the cell's text: NOTE[:GAIN][/EFFECT...]
    E               edit the channel's instrument
    I D             insert, delete a row
    [ ]             the pattern before, after in the order
    Space           play the song from the pattern edited, or stop
    p               play the pattern edited over and over, or stop
    F               follow the playing, or stop: while it follows, the
                    pattern heard is shown and the cursor is on its row
    O               edit the order in place: left, right pick a place, up,
                    down change its pattern, i copy it, d drop it, [ ] move
                    it, Enter edit its pattern, Escape done
    ( )             move the channel left, right
    V               mark a block from the cursor; move to its other corner
    Y X P           copy, cut, paste the block (or the cell)
    Delete          clear the block marked
    U R             undo, redo
    ?               the keys and the commands
    ctrl-c          quit

`:` takes a command, as vi does:

    :w [FILE]   :q   :q!   :wq       write, quit
    :song [NAME]                      edit or make a song; alone, list
                                      them to pick one with up, down, Enter
    :rename NAME                      rename the song
    :bpm N  :rows N  :ticks N  :tension-bpm N
    :len N                            the pattern's rows
    :pattern NAME                     edit a pattern, made if it is new
    :order NAME ...                   the order the patterns play in
    :channel INSTRUMENT  :drop        add a channel, drop the cursor's
    :instrument NAME PROP ...         make or change an instrument
    :octave N  :step N
    :tension N  :pace N               how the song is heard: 0-100, 10-400
    :waves                            list the waves the songs name, and
                                      where each comes from
    :waves keep                       copy the waves borrowed from -w files
                                      into this file
    :wave NAME [AMP ...]              show a wave, or make or change it
    :effects                          list the effects over the whole mix
    :effect (NAME N ...)              add one: echo reverb phase chorus
                                      drive crush sweep limit
    :effect K  :effect K (NAME N ...)  edit the Kth, or put it in
    :effect drop K                    drop the Kth
    :instruments                      list the instruments, and where each
                                      plays
    :instrument NAME                  edit an instrument's form, or make it
    :copy-instrument NAME NEW  :rename-instrument NAME NEW
    :drop-instrument NAME             one no channel plays
    :channel-instrument NAME          the cursor's channel played by NAME
    :patterns                         list the patterns
    :copy-pattern NEW  :rename-pattern NEW  :drop-pattern [NAME]
    :copy-song NAME  :drop-song
    :transpose N  :gain PCT           the block marked, or the cell:
                                      semitones up or down, a gain set

A change is heard from the next pattern while the song plays.  A cell's
effects are x/audio/tracker's (its module notes say what each does):
`a` arpeggio, `v` vibrato, `s` slide, `p` portamento, `t` tremolo, `f`
fade, `l` low-pass, `c` cut, `d` delay, `r` retrigger; `C4:60/v20,4`
is C4 at 60 percent with a vibrato.

Written back, a file keeps everything the editor did not change as it
was, comments and layout; a song that was changed is written from the
song, its patterns a row a line with the cells lined up.

## Install

    make install X=/path/to/x

copies the bundle to `<share>/langs/tracker`, where `x -l` looks.  The
sound needs SDL3: without it the editor runs silent and says so.

## Tests

    make test     # the spec suite
    make check    # the suite against tests/contract/known-failures.txt

## Licence

MIT No Attribution (MIT-0); see LICENSE.
