# x-tracker card

## Run

```sh
x -l tracker -- [OPTIONS] [edit] [FILE]       # the editor; ? in it is the help
x -l tracker -- [OPTIONS] play FILE           # play a song; q stops
x -l tracker -- list FILE                     # the songs of a file
x -l tracker -- render FILE -o OUT.wav        # a song played once, to a WAV
x -l tracker -- import FILE -o OUT.xon        # a MIDI or SID file into a song
x -l tracker -- help [WORD]                   # the topics, a topic, or a word
x -l tracker -- list data/demo.xon | sed 1q | cut -d' ' -f1 -> lantern
x -l tracker -- render data/demo.xon -o /dev/null -> Rendered /dev/null: 0:14
x -l tracker -- help /v | head -1 -> cell effect  /vD,P
```

```tracker
(song "hum" (bpm 100) (rows 4)             ; -> hum  0:01  1 patterns  order a
  (instrument tone (wave sine) (env (0 0) (10 60) (300 30)) (release 150))
  (pattern a
    (tone "C4 . E4 . G4 . E4 ."))
  (order a))
```

| Option               | Does                                               |
|----------------------|----------------------------------------------------|
| `-s`, `--song NAME`  | the song to edit, play or render; import's name    |
| `-w`, `--waves SONGS.xon` | another song file's waves; may repeat     |
| `-l`, `--loop`       | play the song over and over, until q               |
| `-o`, `--output FILE` | the WAV file render writes; the file import adds to |
| `-r`, `--rows N`     | rows a beat for an imported MIDI file, 1-64 (4)    |
| `-u`, `--tune N`     | the tune of a SID file to import (its own first)   |
| `-t`, `--time SECS`  | seconds of a SID tune to import (HVSC's, or 60)    |
| `-n`, `--no-sound`   | edit without opening the audio                     |
| `-V` `-h`            | the version; the help, or after a word that word's |
| a program on this page | a song file; run, it is `list FILE`              |

## Songs

```tracker
(wave hollow 6 0 2 0 1)
(song "two" (bpm 120) (rows 4) (ticks 6) ; -> two  0:05  2 patterns  order a a b
  (echo 250 30 20)
  (instrument lead (wave hollow) (env (0 0) (5 60) (400 30)) (gain 40))
  (instrument kick (wave sine) (note "C2") (env (0 0) (2 95) (120 0)))
  (pattern a
    (lead "C4 . E4:60 . G4/v20,4 . - .  A4/s-200 . . . G4/c3 . . .")
    (kick "C2 . . . C2 . . . C2 . . . C2 . . ."))
  (pattern b
    (lead "C5/a4,7 . . . . . . -")
    (kick "C2 . . . . . . ."))
  (order a a b))
(song "threes" (bpm 60) (rows 3)  ; -> threes  0:07  1 patterns  order a a
  (instrument t)
  (pattern a (t "C4 . . D4 . . E4 . . F4 . ."))
  (order a a))
```

| In a file                          | Is                                    |
|------------------------------------|---------------------------------------|
| `(song "NAME" ITEM ...)`           | a song; a file holds any number       |
| `(wave NAME AMP ...)`              | a wave an instrument can name         |
| `; TEXT`                           | a comment, to the line's end          |
| `(bpm N)`                          | beats a minute (90)                   |
| `(rows N)`                         | rows a beat (4)                       |
| `(ticks N)`                        | ticks a row, the effects' clock (6)   |
| `(tension-bpm N)`                  | beats a minute more at full tension (0) |
| `(instrument NAME PROP ...)`       | an instrument                         |
| `(pattern NAME (INSTRUMENT "CELLS") ...)` | a channel each, a cell a row  |
| `(order NAME ...)`                 | the patterns in the order they play   |
| a row's length                     | 60000 / (bpm x rows) milliseconds     |

```tracker
(song "none" (instrument t)  ; -> none  Tracker: the song has no order
  (pattern a (t "C4 .")))
(song "lost" (instrument t)  ; -> lost  Tracker: no pattern named b
  (pattern a (t "C4 ."))
  (order a b))
(song "whom"  ; -> whom  Tracker: no instrument named t
  (pattern a (t "C4 ."))
  (order a))
(song "typo" (reverbb 90 70 22)            ; -> typo  0:00  1 patterns  order a
  (instrument t)
  (pattern a (t "C4 ."))
  (order a))
```

| A song                             | Is                                    |
|------------------------------------|---------------------------------------|
| with no order                      | refused                               |
| naming a pattern it has not        | refused                               |
| naming an instrument it has not    | refused                               |
| with a form the tracker does not know | played, the form passed over       |

## Cells

| Cell                 | Is                                                 |
|----------------------|----------------------------------------------------|
| `C4` `F#3` `Bb2`     | a note: it starts, the channel's last one ending   |
| `C4:60`              | the note at 60 percent                             |
| `.`                  | hold: what sounds carries on                       |
| `-`                  | let go: what sounds fades over its release         |
| `C4/v20,4`           | a note with an effect: `/`, a letter, its numbers  |
| `./s-200`            | an effect from this row, the note held             |
| `C4:60/v20,4/c3`     | a gain and two effects                             |
| an effect            | holds to the next of its letter, or the note's end |
| a time               | ticks: a row over the song's `(ticks N)`           |

| Effect     | Does                                                         |
|------------|--------------------------------------------------------------|
| `/aX,Y,...` | arpeggio: the note, then X, then Y semitones up, a tick each |
| `/vD,P`    | vibrato: D cents either way, a cycle every P ticks           |
| `/sC`      | slide: C cents, below 0 down, then held                      |
| `/pN`      | portamento: from the channel's last note over N ticks        |
| `/tD,P`    | tremolo: D percent down and back every P ticks               |
| `/fP`      | fade: to P percent                                           |
| `/lP`      | low-pass: to P percent of the instrument's cut               |
| `/wP`      | width: a pulse's to P percent of its cycle                   |
| `/oH`      | cut-off: the resonant filter's to H hertz                    |
| `/xC`      | ring: rung by a modulator C cents from the pitch             |
| `/yC`      | sync: hard-synced to a modulator C cents from the pitch      |
| `/cN`      | cut: let go N ticks into the row                             |
| `/dN`      | delay: start N ticks into the row                            |
| `/rN`      | retrigger: start again every N ticks                         |
| `/eMS,P,N` | echo: again MS ms later at P percent (50), N times (1)       |

## Instruments

| Prop                   | Is                                               |
|------------------------|--------------------------------------------------|
| `(wave NAME [AMP ...])` | the wave a voice reads (`sine`), or makes there  |
| `(env (MS PCT) ...)`   | the level over time, straight between points     |
| `(release MS)`         | how long a note fades once let go (200)          |
| `(gain PCT)`           | the voice's level                                |
| `(pan N)`              | left to right, -100 to 100                       |
| `(cut PCT)`            | a low-pass, a percentage of the pitch's range    |
| `(filter (MS PCT) ...)` | the low-pass moving over time                   |
| `(width (MS PCT) ...)` | a pulse's width over time: 50 is a square        |
| `(cutoff (MS HZ) ...)` | a resonant filter's cut-off over time            |
| `(res PCT)`            | that filter's resonance, 0-100 (0)               |
| `(pass MODE ...)`      | what it lets through: `low` `band` `high` (low)  |
| `(ring CENTS)`         | rung by a modulator CENTS from the pitch         |
| `(sync CENTS)`         | hard-synced to a modulator CENTS from the pitch  |
| `(detune CENTS)`       | the voice moved off its pitch                    |
| `(note "C4")` `(hz N)` | a pitch of its own, as a drum's                  |
| `(slide PITCH)`        | the pitch slid to PITCH over the envelope        |
| `(bend (MS CENTS) ...)` | the pitch moved over time                       |
| `(at MS)`              | the voice starts MS after the note               |
| `(layer calm)` `(layer tension)` | heard as the tension falls; as it rises |
| `(voice PROP ...)`     | a voice of its own over the other props          |

| Wave                           | Is                                       |
|--------------------------------|------------------------------------------|
| `sine` `square` `triangle`     | the mixer's own                          |
| `saw` `inverse-saw` `pulse`    | the mixer's own; `pulse` takes a width   |
| `noise` `metal`                | noise; a short run of it, ringing        |
| `(wave NAME AMP ...)`          | harmonics' strengths, the fundamental first |
| `(wave NAME (POSITION LEVEL) ...)` | the points it is drawn through       |
| `(wave NAME (sample FILE [ROOT] [START END]))` | a WAV file, looped        |

## Mix

| Song effect                    | Does                                     |
|--------------------------------|------------------------------------------|
| `(echo MS FB WET)`             | the mix delayed MS, FB percent fed back  |
| `(reverb SIZE DECAY WET)`      | a room, DECAY percent fed back           |
| `(phase LEAST-MS MOST-MS PERIOD-MS FB WET)` | a short delay swept: a phaser |
| `(chorus VOICES MS DEPTH-MS PERIOD-MS WET)` | 1-4 copies, delayed and swept |
| `(drive GAIN WET)`             | taken up GAIN percent and rounded off    |
| `(crush BITS HZ)`              | BITS of 16 kept, held HZ times a second  |
| `(sweep LOW-HZ HIGH-HZ PERIOD-MS RES)` | a resonant low-pass swept        |
| `(limit CEILING RELEASE-MS)`   | held under CEILING percent of full scale |

## Editor keys

| Key                        | Does                                         |
|----------------------------|----------------------------------------------|
| `F1` `F2` `F3` `F4`        | help; the pattern; samples; instruments      |
| `F11` `F12`                | the order list; the song's settings          |
| `F9`, `F10` or `ctrl-s`    | open a file; write it                        |
| `F5`                       | play, and show what plays                    |
| `F6` `F7` `F8`             | play the pattern; from the row; stop         |
| `Ctrl-F5` `Shift-F8`       | play, staying on the page; pause, or play on |
| `z s x d c v g b h n j m ,` | a note, C to C, in the octave               |
| `q 2 w 3 e r 5 t 6 y 7 u i` | a note, the octave above                    |
| `.` or Delete, `-`, `1`    | hold; let go; cut                            |
| `<` `>`, `{` `}`           | the octave down, up; the step down, up       |
| `4` `8`                    | hear the cell; the row                       |
| the arrows                 | a row; a column of the cell, then a channel  |
| Tab, Shift-Tab             | the next channel; the one before             |
| PgUp PgDn, Home End        | sixteen rows; the first row, the last        |
| `[` `]`                    | the pattern before, after in the order       |
| digits                     | the channel's instrument, or the note's gain |
| a letter, in the effect column | an effect typed after it                 |
| Enter                      | edit the cell's text                         |
| `E`                        | edit the channel's instrument                |
| `I` `D`                    | insert a row, delete one, in every channel   |
| `(` `)`                    | move the channel left, right                 |
| `O`                        | edit the order in place                      |
| `U` `R`, `ctrl-z`          | undo, redo; undo                             |
| Space, `p`, `G`            | play or stop; the pattern looped; from the row |
| `L`                        | loop rows: on the first, then on the last    |
| `M` `S`, `H` `A`           | mute, solo the channel; its instrument       |
| `;` `'`, `_` `+`, `9` `0`  | tension; pace; volume: down, up              |
| `F`                        | follow the playing, or stop                  |
| `:`, `?`                   | a command; the help                          |
| `ctrl-c`, `ctrl-q`         | quit                                         |

| Block key                  | Does                                         |
|----------------------------|----------------------------------------------|
| `Alt-B` `Alt-E`, Shift and the arrows | mark where the block begins, ends |
| `Alt-L` `Alt-D`, `Alt-U`   | mark the channel; a beat's rows; unmark      |
| `V`, `Y` `X` `P`           | mark from the cursor; copy, cut, paste       |
| `Alt-C` `Alt-Z`            | copy; cut                                    |
| `Alt-P` `Alt-O` `Alt-M`    | paste pushing down; over; into the holds     |
| `Alt-Q` `Alt-A`            | a semitone up, down; with Shift an octave    |
| `Alt-K` `Alt-X`            | slide the gains; the first effect's numbers  |
| `Alt-W` `Alt-V` `Alt-J`    | clear the gains; set them; take them up or down |
| `Alt-F` `Alt-G`            | stretch to twice the rows; squeeze to half   |
| Delete                     | clear the block                              |

## Commands

| Command                        | Does                                     |
|--------------------------------|------------------------------------------|
| `:w [FILE]` `:q` `:q!` `:wq`   | write; quit; quit, changes lost; both    |
| `:open FILE`                   | edit another file                        |
| `:song [NAME]`                 | edit or make a song; alone, pick one     |
| `:rename NAME` `:copy-song NAME` `:drop-song` | rename, copy, drop the song |
| `:bpm N` `:rows N` `:ticks N` `:tension-bpm N` | the song's timing        |
| `:order NAME ...`              | the order the patterns play in           |
| `:pattern NAME`                | edit a pattern, made if it is new        |
| `:patterns`                    | list the patterns                        |
| `:copy-pattern NEW` `:rename-pattern NEW` | copy, rename the pattern      |
| `:drop-pattern [NAME]`         | drop the pattern, or NAME                |
| `:len N`                       | the pattern's rows, 1-256                |
| `:channel INSTRUMENT` `:drop`  | add a channel; drop the cursor's         |
| `:channel-instrument NAME`     | the cursor's channel played by NAME      |
| `:transpose N` `:gain PCT` `:amplify PCT` | the block marked, or the cell |
| `:instrument NAME [PROP ...]`  | make, change or edit an instrument       |
| `:instruments`                 | list them, and where each plays          |
| `:copy-instrument NAME NEW`    | copy an instrument                       |
| `:rename-instrument NAME NEW`  | rename one, in every channel             |
| `:drop-instrument NAME`        | drop one no channel plays                |
| `:effects`                     | list the effects over the mix            |
| `:effect (NAME N ...)`         | add one                                  |
| `:effect K [(NAME N ...)]` `:effect drop K` | edit or replace one; drop it |
| `:waves` `:waves keep`         | list the waves; copy the borrowed in     |
| `:wave NAME [AMP ...]`         | show a wave, or make or change it        |
| `:sample NAME FILE [ROOT] [START END]` | keep a WAV file as the wave NAME |
| `:sound OP [N] [FROM TO]`      | edit the sound of the sample picked on F3 |
| `:tension N` `:pace N` `:volume N` | 0-100; 10-400 percent; 0-100         |
| `:mute [INSTRUMENT]` `:solo [INSTRUMENT]` | mute, solo; alone, say which  |
| `:unmute`                      | hear everything again                    |
| `:loop [FROM TO]`              | loop rows of the pattern; alone, all     |
| `:render FILE`                 | the song played once, to a WAV file      |
| `:octave N` `:step N`          | 0-8; rows moved after a note, 0-64       |
| `:set [NAME VALUE ...]`        | change a setting; alone, list them       |
| `:help [WORD]`                 | the topics, a topic, or a word           |

## Settings

| In `~/.config/x/tracker.xon`   | Is                                       |
|--------------------------------|------------------------------------------|
| `(octave N)`                   | the octave notes are typed in, 0-8 (4)   |
| `(step N)`                     | rows moved after a note, 0-64 (1)        |
| `(follow on)`                  | follow the playing (on)                  |
| `(backup on)`                  | `:w` first keeps FILE.bak (on)           |
| `(undo N)`                     | changes kept to undo (200)               |
| `(sound on)`                   | open the audio (on)                      |
| `(waves FILE ...)`             | wave files read, as `-w`                 |
| `(colour NAME ATTRIBUTES FG BG)` | how NAME is drawn                      |
| `(key ACTION KEY ...)`         | bind an action to other keys             |
| `$X_TRACKER_CONFIG`            | another file; empty, none                |
| `:set NAME VALUE ...`          | the same form, for the session           |

## Differs

| Here                                        | In Impulse or Schism Tracker  |
|---------------------------------------------|-------------------------------|
| a song is text, `(song ...)` forms in `.xon` | a module file: `.it` `.mod`  |
| `import` reads MIDI and SID files only      | modules are loaded            |
| an instrument is waves and envelopes        | samples                       |
| an effect is `/`, a letter, numbers: `/v20,4` | a letter, two hex digits   |

## More

| Where                          | What                                     |
|--------------------------------|------------------------------------------|
| `x -l tracker -- help`         | the help's topics                        |
| `README.md`                    | every key, command and setting           |
| `docs/guide.md`                | a first track, key by key                |
| `docs/writing.md`              | the format, every effect, making music   |
| `data/demo.xon`                | two songs to start from                  |
| `tests/card-run.sh`            | runs a program of this page              |
