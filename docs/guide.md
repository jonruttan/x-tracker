# Using x-tracker

This guide is for writing music in x-tracker.  It starts with an empty
file and walks through a short track, key by key: drums, a bass, a
tune, a second pattern, the order, a layer that comes in with the
tension, effects over the mix, and saving it.  After that it goes
through each kind of work the editor does.

[writing.md](writing.md) is the companion to this guide: what each
part of a song does to the sound, every effect in detail, and how to
make music with them.  `data/demo.xon` has two finished songs to open
and take apart, `data/hungarian-dance-5.xon` a longer one, and
`data/undertow.xon` one in drum and bass.

## Starting

    x -l tracker -- harbour.xon

opens `harbour.xon` in the editor.  A file that does not exist yet
starts with one song, `untitled`, and is made when it is first written.
A file that does exist opens on its first song; `-s NAME` opens another.

    x -l tracker -- -s lighthouse data/demo.xon     open one song of a file
    x -l tracker -- -n harbour.xon                  edit without sound
    x -l tracker -- play harbour.xon                hear it once, no editor
    x -l tracker -- --loop play harbour.xon         hear it until q
    x -l tracker -- render harbour.xon -o harbour.wav   write it to a WAV file
    x -l tracker -- list data/demo.xon              each song, its length, its order

A file whose instruments name waves kept in another file is opened with
that file too, `-w sounds.xon`.  Without SDL3 the editor runs silent
and says so.

ctrl-c leaves at once.  `:q` leaves too, but refuses once while there
are changes not written: `:w` writes them, `:q!` leaves without.

## The screen

A new file looks like this:

```
 x-tracker  harbour.xon [+]   "untitled"   bpm 120  rows 4  ticks 6   octave 4  step 1
 order: [a]

     1 lead 01
  0 ... .. ... .......
  1 ... .. ... .......
  2 ... .. ... .......
  3 ... .. ... .......
  4 ... .. ... .......
  5 ... .. ... .......
  6 ... .. ... .......
  7 ... .. ... .......
  8 ... .. ... .......
  9 ... .. ... .......
 10 ... .. ... .......
 11 ... .. ... .......
 12 ... .. ... .......
 13 ... .. ... .......
 14 ... .. ... .......
 15 ... .. ... .......
```

The top line is the file, `[+]` when it has changes not yet written,
the song's name, its tempo (`bpm`, `rows` a beat, `ticks` a row), and
the octave and the step the keys type with; on a narrow screen it
leaves out `rows` and `ticks` first, then the octave and the step,
then the tempo and the name.  Below it is the order: the patterns in
the order they play, the one being edited in brackets, and while the
song plays, the one heard marked `>`.  An order wider than the screen
shows the part around the one heard while the song plays, else the
one edited, `...` for the rest.

Then the pattern: a row a line, numbered from 0, and a channel a
column, headed by its number, the instrument that plays it and the
instrument's number.  A cell is four columns, as Impulse Tracker draws
them: the note (`C-4`, `C#4`; `===` a let-go, `^^^` a cut, `...` a
hold), the instrument's number, the volume (the note's gain in
percent) and the first effect, `+` after it when there are more.  The
rows on the beat are drawn in a colour of their own.  The cursor is
the column drawn reversed.  The last line shows the keys to start with, a command being
typed (its end, after `...`, when it is longer than the screen), or a
message.  `?` shows every key and command; any key closes
it.  A list too wide for the screen, such as `:patterns` in a song of
many, pages the way `?` does.

The new song has one instrument, `lead`, a sine, and one pattern, `a`,
of sixteen rows, with the lead's channel in it.  At 4 rows a beat,
sixteen rows are a bar of four beats.

## A first track

### Name and tempo

`:` starts a command, as in vi; Enter runs it, Escape drops it.

    :rename harbour
    :bpm 100

### Drums

An instrument is made with `:instrument`, its name, and its sound as
`(PROP ...)` forms, the same as a song file writes them
([writing.md](writing.md) has every prop).  A kick drum is a sine that
drops in pitch, and a hat is a burst of noise:

    :instrument kick (wave sine) (note "C2") (env (0 0) (2 95) (140 0)) (bend (0 700) (45 0)) (release 30) (gain 60)
    :instrument hat (wave noise) (hz 1) (cut 85) (env (0 0) (1 30) (35 0)) (release 15) (gain 18) (pan 30)

`:channel kick` adds a channel to the pattern played by the kick, at
the right, and puts the cursor in it.

Notes are typed on the keyboard as on a piano: `z` is C, and the row
from `z` to `,` with the row above it from `s` to `j` are the white and
black keys of an octave.  The drums have a pitch of their own, so any
key plays them; `z` will do.

After each note the cursor moves down by the step, shown on the top
line, and goes round to the top past the bottom.  With the step at 4,
four `z`s put a kick on every beat:

    :channel kick
    :step 4
    zzzz

The hats go on every other row, eight of them at a step of 2:

    :channel hat
    :step 2
    zzzzzzzz

```
 x-tracker  harbour.xon [+]   "harbour"   bpm 100  rows 4  ticks 6   octave 4  step 2
 order: [a]

     1 lead 01          2 kick 02          3 hat 03
  0 ... .. ... ....... C-4 02 ... ....... C-4 03 ... .......
  1 ... .. ... ....... ... .. ... ....... ... .. ... .......
  2 ... .. ... ....... ... .. ... ....... C-4 03 ... .......
  3 ... .. ... ....... ... .. ... ....... ... .. ... .......
  4 ... .. ... ....... C-4 02 ... ....... C-4 03 ... .......
  5 ... .. ... ....... ... .. ... ....... ... .. ... .......
  6 ... .. ... ....... ... .. ... ....... C-4 03 ... .......
  7 ... .. ... ....... ... .. ... ....... ... .. ... .......
  8 ... .. ... ....... C-4 02 ... ....... C-4 03 ... .......
  9 ... .. ... ....... ... .. ... ....... ... .. ... .......
 10 ... .. ... ....... ... .. ... ....... C-4 03 ... .......
 11 ... .. ... ....... ... .. ... ....... ... .. ... .......
 12 ... .. ... ....... C-4 02 ... ....... C-4 03 ... .......
 13 ... .. ... ....... ... .. ... ....... ... .. ... .......
 14 ... .. ... ....... ... .. ... ....... C-4 03 ... .......
 15 ... .. ... ....... ... .. ... ....... ... .. ... .......
```

Every note is heard as it is typed.  Typing over a note puts the new
one in its place.

### A bass

A wave other than `sine` and `noise` is made of harmonics with
`:wave`, kept in the file, and named by the instruments that play it.
`soft` is a sine with a little body:

    :wave soft 8 3 1

`:instrument` with only a name puts the instrument's form on the
command line to edit: the one it has, or for a new one, a form to start
from.

    :instrument bass

shows on the last line:

    instrument: (instrument bass (wave sine) (env (0 0) (5 70) (250 35)) (release 150) (gain 50))

Edit it with the arrows and backspace, and Enter makes it.  Here it is
typed whole instead (Escape first to drop the line):

    :instrument bass (wave soft) (cut 30) (env (0 0) (6 80) (600 50)) (release 120) (gain 50)

The bass plays A for half the bar and F for the other half, an octave
down.  `:octave` sets the octave the lower row of keys plays in, and
the upper row plays the one above it; `<` and `>` move it down and up.
On the keys, A is `n` and F is `v`:

    :channel bass
    :octave 2
    :step 8
    nv

### A tune

Up and down move the cursor a row, Home and End go to the top and the
bottom of the pattern, and PgUp and PgDn go sixteen rows.  Left and
right walk the four columns of a cell, its note, instrument, volume and
effect, and on into the next channel; Alt-left and Alt-right go a whole
channel, and Tab and Shift-Tab go to the next channel's note and the
one before's, round the end.  Back to the lead's channel, three to the
left, and the top:

    Alt-left Alt-left Alt-left Home

The keys, with the octave at 4:

    z s x d c v g b h n j m ,    C4 C#4 D4 D#4 E4 F4 F#4 G4 G#4 A4 A#4 B4 C5
    q 2 w 3 e r 5 t 6 y 7 u i    C5 C#5 D5 D#5 E5 F5 F#5 G5 G#5 A5 A#5 B5 C6

`.` (or Delete) types a hold, the note before carrying on, and `-` lets
the note go.  The tune falls E D C, holds, then C and A, a note every
two rows:

    :octave 4
    :step 2
    ewq.qn

Enter edits the cell under the cursor as text, `NOTE[:GAIN][/EFFECT...]`.
Two rows up is the A; Enter, then `/v20,6` after it, and Enter again,
gives it a vibrato of 20 cents every 6 ticks.  A gain is typed the same
way: `A4:60` is the A at 60 percent.  The effects are listed at the
bottom of `?`, and [writing.md](writing.md) has each with an example.

    up up Enter /v20,6 Enter

```
 x-tracker  harbour.xon [+]   "harbour"   bpm 100  rows 4  ticks 6   octave 4  step 2
 order: [a]

     1 lead 01          2 kick 02          3 hat 03           4 bass 04
  0 E-5 01 ... ....... C-4 02 ... ....... C-4 03 ... ....... A-2 04 ... .......
  1 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  2 D-5 01 ... ....... ... .. ... ....... C-4 03 ... ....... ... .. ... .......
  3 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  4 C-5 01 ... ....... C-4 02 ... ....... C-4 03 ... ....... ... .. ... .......
  5 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  6 ... .. ... ....... ... .. ... ....... C-4 03 ... ....... ... .. ... .......
  7 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  8 C-5 01 ... ....... C-4 02 ... ....... C-4 03 ... ....... F-2 04 ... .......
  9 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
 10 A-4 01 ... v20,6   ... .. ... ....... C-4 03 ... ....... ... .. ... .......
 11 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
 12 ... .. ... ....... C-4 02 ... ....... C-4 03 ... ....... ... .. ... .......
 13 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
 14 ... .. ... ....... ... .. ... ....... C-4 03 ... ....... ... .. ... .......
 15 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
```

### Listening

Space plays the song from the pattern being edited, round and round,
and stops it.  `p` plays only the pattern being edited, over and over,
and stops it.  `G` plays from the cursor's row.  `F` follows the
playing: the pattern heard is shown, and the cursor moves down its
rows; `F` again stops following, to edit elsewhere while it plays.  A
change is heard from the next pattern.  "Hearing it" below has the
rest: looping rows, muting and soloing, tension, pace and volume.

### A second pattern

`:copy-pattern b` copies the pattern to a new one, `b`, and edits it;
`:pattern b` would make an empty one.  In `b` the bass plays C and G,
and the tune goes up and comes back down to B:

    :copy-pattern b
    Alt-right Alt-right Alt-right Home
    :octave 2
    :step 8
    zb
    Alt-left Alt-left Alt-left Home
    :octave 4
    :step 2
    etewq.m.

The last B glides from the C before it, with a portamento over 3
ticks: four rows up from the top, round the bottom, is the B.

    up up up up Enter /p3 Enter

### The order

    :order a b a b
    :pattern b

`:order` sets the patterns the song plays in turn, a pattern as often
as it is named.  `[` and `]` go to the pattern before and after in the
order, and `:pattern NAME` to any pattern by name; `:pattern b` puts
the editor back on `b` at its place in the new order.  `O` edits the
order in place (below).

### A layer for the tension

A song can play differently as tension rises, which a game sets from
what is happening.  An instrument with `(layer tension)` is heard more
as it rises, and one with `(layer calm)` less.  A bell in `b`, at E and
G in octave 5, comes in only with the tension:

    :wave glass 5 0 0 2 0 0 0 1
    :instrument bell (layer tension) (wave glass) (env (0 0) (3 40) (1200 0)) (release 600) (gain 22) (pan -30)
    :channel bell
    Home
    :octave 5
    :step 8
    cb

```
 x-tracker  harbour.xon [+]   "harbour"   bpm 100  rows 4  ticks 6   octave 5  step 8
 order: a [b] a b

     1 lead 01          2 kick 02          3 hat 03           4 bass 04          5 bell 05
  0 E-5 01 ... ....... C-4 02 ... ....... C-4 03 ... ....... C-2 04 ... ....... E-5 05 ... .......
  1 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  2 G-5 01 ... ....... ... .. ... ....... C-4 03 ... ....... ... .. ... ....... ... .. ... .......
  3 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  4 E-5 01 ... ....... C-4 02 ... ....... C-4 03 ... ....... ... .. ... ....... ... .. ... .......
  5 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  6 D-5 01 ... ....... ... .. ... ....... C-4 03 ... ....... ... .. ... ....... ... .. ... .......
  7 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
  8 C-5 01 ... ....... C-4 02 ... ....... C-4 03 ... ....... G-2 04 ... ....... G-5 05 ... .......
  9 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
 10 ... .. ... ....... ... .. ... ....... C-4 03 ... ....... ... .. ... ....... ... .. ... .......
 11 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
 12 B-4 01 ... p3      C-4 02 ... ....... C-4 03 ... ....... ... .. ... ....... ... .. ... .......
 13 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
 14 ... .. ... ....... ... .. ... ....... C-4 03 ... ....... ... .. ... ....... ... .. ... .......
 15 ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... ....... ... .. ... .......
```

To hear the bell, set the tension and play the song:

    :tension 60
    Space

The top line says what is playing, and the tension when it is not 0:

```
 x-tracker  harbour.xon [+]   "harbour"   bpm 100  rows 4  ticks 6   octave 5  step 8   > song  tension 60
```

The tension, 0 to 100, is how the song is heard, not part of the file:
`;` and `'` take it down and up by 10 while it plays.  `:tension-bpm N`
sets how much the tempo rises at full tension.

### Effects over the mix

An effect over the whole mix is added with `:effect` and its form; they
run in the order they are added:

    :effect (reverb 90 70 22)
    :effect (echo 300 30 15)

`:effects` lists them, numbered from 1; `:effect 2` puts the second on
the command line to edit, and `:effect drop 2` drops it.

### Saving

    :w

writes the file; `:w FILE` writes it to another.  The first `:w` of a
session copies the file as it was to `harbour.xon.bak`.  `:wq` writes
and leaves.  This is the whole file, the waves first:

```xon
(wave soft 8 3 1)
(wave glass 5 0 0 2 0 0 0 1)

(song "harbour" (bpm 100) (rows 4) (ticks 6)
  (reverb 90 70 22)
  (echo 300 30 15)
  (instrument lead (wave sine) (env (0 0) (5 70) (250 35)) (release 150) (gain 50))
  (instrument kick (wave sine) (note "C2") (env (0 0) (2 95) (140 0)) (bend (0 700) (45 0)) (release 30) (gain 60))
  (instrument hat (wave noise) (hz 1) (cut 85) (env (0 0) (1 30) (35 0)) (release 15) (gain 18) (pan 30))
  (instrument bass (wave soft) (cut 30) (env (0 0) (6 80) (600 50)) (release 120) (gain 50))
  (instrument bell (layer tension) (wave glass) (env (0 0) (3 40) (1200 0)) (release 600) (gain 22) (pan -30))
  (pattern a
    (lead "E5 .  D5 .  C5 .  .  .  C5 .  A4/v20,6 .  .  .  .  .")
    (kick "C4 .  .  .  C4 .  .  .  C4 .  .  .  C4 .  .  .")
    (hat  "C4 .  C4 .  C4 .  C4 .  C4 .  C4 .  C4 .  C4 .")
    (bass "A2 .  .  .  .  .  .  .  F2 .  .  .  .  .  .  ."))
  (pattern b
    (lead "E5 .  G5 .  E5 .  D5 .  C5 .  .  .  B4/p3 .  .  .")
    (kick "C4 .  .  .  C4 .  .  .  C4 .  .  .  C4 .  .  .")
    (hat  "C4 .  C4 .  C4 .  C4 .  C4 .  C4 .  C4 .  C4 .")
    (bass "C2 .  .  .  .  .  .  .  G2 .  .  .  .  .  .  .")
    (bell "E5 .  .  .  .  .  .  .  G5 .  .  .  .  .  .  ."))
  (order a b a b))
```

The editor writes a song it changed this way, its patterns a row a
line with the cells lined up; what it did not change, other songs and
comments, it writes back as it was.  The file can be edited by hand as
well, and opened again.

## Working in the editor

### The pages

The function keys go to the editor's pages, as in Impulse Tracker and
Schism Tracker; Escape on a page goes back to the pattern.

- F1 the help, F2 the pattern.
- F3 the samples: the WAV files the file keeps as waves.
  `:sample NAME FILE.wav [ROOT] [START END]` reads one, from the
  directory of the file edited, as the wave NAME; an instrument plays it
  with `(wave NAME)`.  ROOT is the note it sounds at as recorded, START
  and END the frames it loops between.  Space hears the one picked.
- F4 the instruments, numbered as the pattern shows them, with the
  props of the one picked and its envelope drawn.  Enter edits it, Space
  or the note keys hear it.  Tab goes into its envelope: left and right
  pick a point, Enter picks it up for the arrows to move (Alt ten at a
  time) and puts it down, Insert adds a point after it, Delete drops it.
- F11 the order list: up and down pick a place, left and right change
  its pattern, Insert copies it, Delete drops it, Enter edits its
  pattern.
- F12 the song's settings: up and down pick one, left and right change
  it, Enter types it.
- F5 plays the song, F6 the pattern, Shift-F6 the song from the
  pattern, F7 from the cursor's row; F8 stops.
- F9 opens another file, as `:open FILE`; F10 or ctrl-s writes, as
  `:w`; ctrl-q quits, as `:q`.

### Typing notes

- The step, `{` and `}` or `:step N`, is how far the cursor moves after
  a note, 0 to 64.  A step of 0 stays on the cell, to try notes; the
  step of a beat types a line of drums.
- `<` and `>`, or `:octave N`, set the octave, 0 to 8.
- A note typed over a cell keeps the cell's gain and effects: `g` over
  `C4:50/v20,4` makes `F#4:50/v20,4`.
- `.` or Delete types a hold, `-` or `` ` `` a let-go, `1` a cut.
- `4` hears the cell and `8` the whole row, and moves down.
- In the instrument column two digits give the channel another
  instrument, by its number on F4: x-tracker plays a channel with one
  instrument, every row.
- In the volume column two digits are the note's gain in percent; `.`
  clears it.
- In the effect column a letter starts an effect, typed after it as
  after a `/` (`:help effects`).
- Enter edits the cell as text; a cell that is not a note, a hold or a
  let-go is refused, and says why.

### Rows and patterns

- Insert pushes the channel's rows down from the cursor, Shift-Delete
  pulls them up.  `I` and `D`, or Alt-Insert and Alt-Delete, insert and
  delete a row in every channel.  `:len N` makes the pattern N rows
  long, 1 to 256.
- `:pattern NAME` edits a pattern, made empty with the same channels if
  it is new.  `:patterns` lists them.
- `:copy-pattern NEW`, `:rename-pattern NEW` and `:drop-pattern [NAME]`
  copy, rename and drop the pattern edited, or the one named.

### Blocks

The block keys are Impulse Tracker's.  Alt-B marks where a block
begins and Alt-E where it ends; Shift and the arrows mark one as the
cursor moves.  Alt-L marks the channel's column, then the whole
pattern's; Alt-D marks a beat's rows, twice as many each time again.
Alt-U unmarks.

- Alt-C copies the block, Alt-Z cuts it.
- Alt-P pastes it at the cursor with the rows below pushed down, Alt-O
  pastes over, and Alt-M pastes only into the holds.
- Alt-Q and Alt-A move the notes a semitone up and down, with Shift an
  octave.
- Alt-K slides the gains from the block's first row to its last, and
  Alt-X the first effect's numbers.
- Alt-W clears the gains, Alt-V sets them (`:gain PCT`), Alt-J takes them
  up or down (`:amplify PCT`).
- Alt-F stretches the block to twice its rows and Alt-G squeezes it to
  half.
- Alt-S has another instrument play the channel.

`V` marks a block from the cursor as well; move to its other corner.
`Y` copies it, `X` cuts it and `P` pastes it at the cursor; with
nothing marked they take the one cell.  Delete clears the block.

`:transpose N` moves the notes of the block, or the cell, N semitones,
`:transpose 12` an octave up and `:transpose -12` down.  `:gain PCT` sets
their gain.

### Channels

`:channel INSTRUMENT` adds a channel at the right; `:drop` drops the
cursor's.  `(` and `)` move the cursor's channel left and right.
`:channel-instrument NAME` has another instrument play the cursor's
channel.  An instrument can play more than one channel: two channels of
a pad are a two-note chord.

### Instruments

- `E` edits the cursor's channel's instrument on the command line.
- `:instrument NAME` alone edits an instrument's form, or starts a new
  one; `:instrument NAME PROP ...` makes or changes it whole.
- `:instruments` lists them, and the patterns each plays in.
- `:copy-instrument NAME NEW`, `:rename-instrument NAME NEW` (every
  channel it plays follows), `:drop-instrument NAME` (only one no
  channel plays).

### The order

`O` edits the order in place: left and right pick a place, up and down
change its pattern, `i` copies it, `d` drops it, `[` and `]` move it,
Enter edits its pattern, and Escape is done.  `:order NAME ...` sets
it whole.

### Songs

A file can hold any number of songs.  `:song` lists them to pick one
with up, down and Enter; `:song NAME` edits one, or makes it new.
`:rename NAME` renames the song, `:copy-song NAME` copies it, and
`:drop-song` drops it.  `:bpm`, `:rows`, `:ticks` and `:tension-bpm`
set its timing.

### Waves

`:wave NAME AMP ...` makes or changes a wave, kept in the file;
`:wave NAME` shows one.  `:waves` lists the waves the songs name and
where each comes from.  A file opened with `-w FILE` borrows the waves
of that file: `:waves keep` copies them into this one, so it needs no
other.

### Hearing it

What is heard is the player's, not the song's: none of it changes the
file.

- Space plays the song from the pattern edited and stops it; `p` plays
  the pattern edited over and over and stops it; `G` plays from the
  cursor's row, the song, or the pattern alone when it is not in the
  order.
- `L` loops rows.  `L` on the first row marks it; `L` on the last plays
  the rows between over and over.  Escape forgets a first row marked.
  `:loop FROM TO` does the same by number, and `:loop` alone loops the
  whole pattern.  With the cursor at the top of `b`:

      L

  says `Loop from row 0: L on its last row plays it, Escape forgets.`,
  and seven rows down,

      L

  says `Looping rows 0 to 7: p plays the whole pattern.`  The top line
  shows the rows looping:

```
 x-tracker  harbour.xon [+]   "harbour"   bpm 100  rows 4  ticks 6   octave 5  step 8   > rows 0-7  tension 60
```

- `M` mutes the cursor's channel and `S` solos it; again, it is heard as
  before.  The channels are counted from 0 at the left, so `M` on the
  bell's channel says `Channel 4 muted.`, and again,
  `Channel 4 heard again.`  `H` and `A` mute and solo the channel's instrument, in every
  channel it plays.  `:mute INSTRUMENT` and `:solo INSTRUMENT` do the
  same by name; `:mute` alone says what is muted and soloed, and
  `:unmute` hears everything again.  A muted channel's heading is drawn
  dim and a soloed one's green.  A mute or a solo is heard from the next
  row.
- `;` and `'` take the tension down and up by 10, `_` and `+` the pace
  by 10 percent, `9` and `0` the volume by 10 percent; `:tension N`,
  `:pace N` (10 to 400) and `:volume N` (0 to 100) set them.  They are
  heard at once, and the top line shows each that is not at its usual.
- `:render FILE` writes the song played once, ringing out, to a WAV
  file, as it is heard: with its mutes, tension, pace and volume.  From
  the command line, `render FILE -o OUT.wav` writes it as written, at
no tension and nothing muted.

### Undo

`U` undoes and `R` redoes, as far back as the session goes (200 changes
unless the settings say otherwise), a dropped song included.

### Settings

The octave, the step, following, the backup, undo, the colours and the
keys can be set in `~/.config/x/tracker.xon`, and for a session with
`:set NAME VALUE`; `:set` alone lists them.  The README has the file's
forms and every key's action name, to bind it to another key.

## Where next

- [writing.md](writing.md): the song format, every effect, and writing
  drums, bass, pads, chords, tension and structure.
- `data/demo.xon`: `lantern`, short, and `lighthouse`, with every
  effect.  Open one, press Space, and change it.
- `data/hungarian-dance-5.xon`: Brahms's Hungarian Dance No. 5, three
  minutes long, its Allegro, Vivace and ritardandos written into the
  rows.  writing.md says how.
- `data/undertow.xon`: drum and bass at 174 bpm, eighteen patterns
  from the intro through two drops to the outro, none played twice.
