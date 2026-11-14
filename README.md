# x-tracker

A music tracker written in [x-lang](https://github.com/jonruttan/x-lang),
loaded as a lang: songs of patterns and instruments, edited on the
terminal and heard through SDL's audio.

    x -l tracker -- [OPTIONS] [edit] [FILE]
    x -l tracker -- [OPTIONS] play FILE
    x -l tracker -- list FILE
    x -l tracker -- [OPTIONS] render FILE -o OUT.wav
    x -l tracker -- help [WORD]

      -s, --song NAME    the song to edit or play (the file's first)
      -w, --waves FILE   read the (wave ...) forms of FILE too; again for another
      -l, --loop         play the song over and over, until q
      -o, --output FILE  the WAV file render writes
      -n, --no-sound     edit without opening the audio
      -V, --version      print the version and exit
      -h, --help         print the help and exit; after a word, that word's

The songs are the ones x/audio/tracker plays, and x-roguelike's music
is made of: a file is any `.xon` file of `(song ...)` forms, with the
`(wave NAME AMP ...)` forms their instruments name.  `data/demo.xon` is
one to start from:

    x -l tracker -- data/demo.xon

`data/hungarian-dance-5.xon` is a longer one: Brahms's Hungarian Dance
No. 5, its changes of tempo written into the rows.

    x -l tracker -- play data/hungarian-dance-5.xon

[docs/guide.md](docs/guide.md) is a guide to using the tracker: a first
track written key by key, then each kind of work the editor does.
[docs/writing.md](docs/writing.md) is a guide to writing songs: the
format, every effect, and how to make music with them.

`play` plays a song once through, or with `--loop` until q, the pattern
heard written to standard error; `list` prints each song of a file with
how long it lasts, its patterns and its order; `render` writes a song
played once through, ringing out, to a WAV file (16-bit stereo, 44100
frames a second).  With no operands
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
    G               play from the cursor's row: the song, or the pattern
                    when it is not in the order
    L               loop rows: L on the first row, L on the last plays
                    them over and over; Escape forgets the first
    M S             mute, solo the cursor's channel; again to undo it
    H A             mute, solo the channel's instrument
    ; '             tension down, up by 10
    _ +             pace down, up by 10 percent
    9 0             volume down, up by 10 percent
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
    ?               the help: n p turn the topic, the arrows scroll
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
    :volume N                         0-100 percent
    :mute [INSTRUMENT]                mute an instrument; alone, say what
                                      is muted and soloed
    :solo [INSTRUMENT]                solo an instrument
    :unmute                           hear every channel and instrument
    :loop [FROM TO]                   play rows FROM to TO of the pattern
                                      over and over; alone, all of it
    :render FILE                      write the song played once to a WAV
                                      file, as it is heard
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
    :set                              list the settings, the keys among them
    :set NAME VALUE ...               change a setting for this session
    :help [WORD]                      the help's topics, a topic, or every entry named WORD

A change is heard from the next pattern while the song plays; a mute
or a solo from the next row.  A muted channel's heading is dim, a
soloed one's green.  A cell's
effects are x/audio/tracker's (its module notes say what each does):
`a` arpeggio, `v` vibrato, `s` slide, `p` portamento, `t` tremolo, `f`
fade, `l` low-pass, `c` cut, `d` delay, `r` retrigger; `C4:60/v20,4`
is C4 at 60 percent with a vibrato.

Written back, a file keeps everything the editor did not change as it
was, comments and layout; a song that was changed is written from the
song, its patterns a row a line with the cells lined up.

## Help

The help is one set of tables (tracker/help.x), shown three ways: `?`
in the editor pages through its topics, `:help` lists them, and
`x -l tracker -- help` prints them.  The topics are keys, commands,
cells, effects, song, instruments, waves, order, settings and cli.

    :help effects          a topic
    :help loop             every entry named loop: here the :loop command
    :help /v  :help :mute  an effect by its slash, a command by its colon
    x -l tracker -- help gain     the same, printed
    x -l tracker -- render -h     the help on a word of the command line

The suite checks that every command the editor takes, every action a
key can be bound to and every setting has an entry.

## Settings

The settings are read from `$X_TRACKER_CONFIG`, else
`$XDG_CONFIG_HOME/x/tracker.xon`, else `~/.config/x/tracker.xon`, as
x's own theme and syntax files are found; an empty `X_TRACKER_CONFIG`
reads none.  The file is data, read and never run: each form is a
setting, and `:set` in the editor takes the same form without its
parentheses, for the session.  `:set` alone lists every setting with
its value.

    ; ~/.config/x/tracker.xon
    (octave 3)                 ; the octave notes are typed in, 0-8 (4)
    (step 1)                   ; rows the cursor moves after a note, 0-64 (1)
    (follow on)                ; follow the playing (on)
    (backup on)                ; :w first copies the file to FILE.bak, once a session (on)
    (undo 200)                 ; changes kept to undo, 1-10000 (200)
    (sound on)                 ; off edits without the audio, as -n does (on)
    (waves "sounds.xon")       ; wave files read as -w reads them, from this file's directory
    (colour beat (bold) yellow ())
    (key undo "u")
    (key play enter)

A switch is `on` or `off` (`yes`, `no`, `#t`, `#f`).  `sound` and
`waves` are read as the editor starts, so `:set` does not change them.

`(colour NAME ATTRIBUTES FOREGROUND BACKGROUND)` is the style the editor
draws NAME in, as x/tui/style's `Style make` takes it: the attributes a
list of `bold dim italic underline reverse strike`, a colour 0 to 255,
`black red green yellow blue magenta cyan white`, `bright-` any of
those, or `()` for the terminal's own.  The names and their defaults:

    title    (reverse) () ()    the line at the top
    empty    (dim) () ()        an empty cell, a row off the beat, the hint line
    heading  (bold) () ()       a channel's instrument, a heading
    beat     () 3 ()            a row on the beat
    off      () 1 ()            a let-go cell
    effect   () 6 ()            a cell with effects
    cursor   (reverse) () ()    the cursor, a song picked
    playing  (bold) 2 ()        the row heard
    block    () 0 6             the cells of the block marked

`(key ACTION KEY ...)` binds an action to other keys: each a character
in a string, `"u"`, or a key's name, as `enter up down left right
page-up page-down home end complete interrupt`.  A bound action's own key
no longer does it; `(key ACTION)` gives it back.  The actions, and their
own keys:

    command :        help ?          undo U          redo R
    play Space       play-pattern p  follow F
    previous [       next ]          octave-down <   octave-up >
    step-down {      step-up }       up down left right page-up page-down
    top Home         bottom End      next-channel Tab
    edit-cell Enter  edit-instrument E
    insert-row I     delete-row D    hold .          let-go -
    quit ctrl-c      order O         channel-left (  channel-right )
    mark V           copy Y          cut X           paste P
    play-here G      loop L
    mute-channel M   solo-channel S  mute-instrument H  solo-instrument A
    tension-down ;   tension-up '    pace-down _     pace-up +
    volume-down 9    volume-up 0

A form that is not a setting is one line on standard error, and the
first is shown in the editor; the rest of the file is still read.  A
file that does not read is one line, and the defaults.

## Install

    make install X=/path/to/x

copies the bundle to `<share>/langs/tracker`, where `x -l` looks.  The
sound needs SDL3: without it the editor runs silent and says so.

## Tests

    make test     # the spec suite
    make check    # the suite against tests/contract/known-failures.txt

## Licence

MIT No Attribution (MIT-0); see LICENSE.
