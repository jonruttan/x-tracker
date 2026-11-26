# Impulse Tracker's ways
@weight 2

tracker/edit and tracker/draw as Schism Tracker has them: the pattern
editor's four columns, its Alt keys for blocks, and the pages on the
function keys, over x-tracker's own song.

## the pattern editor's columns

### right and left walk a channel's note, instrument, volume and effect

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (instrument b (wave sine)) (pattern p (a \"C4 D4\") (b \". .\")) (order p))") () ()))
(def at (fn (_) (list (List ref 2 (edit-place st)) (List ref 1 (edit-place st)))))
(def walk (List map (fn (_ k) (spec-keys! st (list k)) (at)) (list 'right 'right 'right 'right 'left 'shift-tab 'alt-right 'complete)))
(write walk)
```
---
    ((0 0) (0 0) (0 0) (1 0) (0 0) (1 0) (1 0) (0 0))

### digits in the volume column make a note's gain; . clears it; a hold has none

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4 D4 . F4\")) (order p))") () ()))
(spec-keys! st (list 'right 'right "6" "0" "0" "5" "4" "2" 'up "."))
(write (list (song-pattern (edit-song st) "p") (edit-message st)))
```
---
    ((("a" "C4:60" "D4" "." "F4")) "A volume is a note's: type a note first.")

### an effect is typed in its column; 1 cuts, ` lets go

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4:50 D4 E4 F4\")) (order p))") () ()))
(spec-keys! st (list 'right 'right 'right "v" "20,6" 'enter 'enter "/f30" 'enter 'left 'left 'left "1" "`"))
(write (song-pattern (edit-song st) "p"))
```
---
    (("a" "C4:50/v20,6" "D4/f30" "./c0" "-"))

### the screen shows a cut as ^^^, a let-go as ===, the effects cut to fit with +

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"Db4:50/v20,6/f30 ./c0 - .\")) (order p))") () ()))
(def screen (Screen make 10 40))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 3 8)))
```
---
```output
     1 a 01
  0 C#4 01  50 v20,6+
  1 ^^^ .. ... .......
  2 === .. ... .......
  3 ... .. ... .......
```

### a digit in the instrument column gives the channel another instrument

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (instrument b (wave noise)) (pattern p (a \"C4\")) (order p))") () ()))
(spec-keys! st (list 'right "0" "2"))
(write (list (song-pattern (edit-song st) "p") (edit-message st)))
(spec-keys! st (list "0" "7"))
(write (edit-message st))
```
---
    ((("b" "C4")) "Channel 1 plays b, every row: x-tracker plays a channel with one instrument.")"No instrument 7: F4 lists them."

## blocks

### Alt-B and Alt-E mark it; Alt-C copies, Alt-O pastes over, Alt-P pushes the rows down, Alt-M fills only the holds

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4 D4 . . . . . .\") (b \". E4 F4 . . . . .\")) (order p))") () ()))
(spec-keys! st (list 'alt-b 'down 'alt-e 'alt-c 'down 'down 'alt-o))
(def over (song-pattern (edit-song st) "p"))
(spec-keys! st (list 'home 'alt-p))
(def pushed (song-pattern (edit-song st) "p"))
(spec-keys! st (list 'alt-right 'alt-b 'down 'alt-e 'alt-c 'down 'down 'down 'down 'down 'alt-left 'alt-m))
(write (list over pushed (song-pattern (edit-song st) "p")))
```
---
    ((("a" "C4" "D4" "." "C4" "D4" "." "." ".") ("b" "." "E4" "F4" "." "." "." "." ".")) (("a" "C4" "D4" "C4" "D4" "." "C4" "D4" ".") ("b" "." "E4" "F4" "." "." "." "." ".")) (("a" "C4" "D4" "C4" "D4" "." "C4" "D4" "E4") ("b" "." "E4" "F4" "." "." "." "." ".")))

### Shift and the arrows mark a block; Alt-Q and Alt-A move it a semitone, with Shift an octave

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4 D4 E4\")) (order p))") () ()))
(spec-keys! st (list 'shift-down 'alt-q 'alt-q 'alt-Q 'alt-a))
(write (song-pattern (edit-song st) "p"))
```
---
    (("a" "C#5" "D#5" "E4"))

### Alt-K slides the volume and Alt-X an effect from the block's first row to its last

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4:20/v10,4 D4 ./v0,4 E4 F4:80/v40,8\")) (order p))") () ()))
(spec-keys! st (list 'alt-b 'end 'alt-e 'alt-k 'alt-x))
(write (song-pattern (edit-song st) "p"))
```
---
    (("a" "C4:20/v10,4" "D4:35/v18,5" "./v25,6" "E4:65/v33,7" "F4:80/v40,8"))

### Alt-F doubles the block, Alt-G halves it; Insert pushes one channel's rows down

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4 D4 E4 . . . . .\") (b \"G4 . . . . . . .\")) (order p))") () ()))
(spec-keys! st (list 'alt-b 'down 'down 'alt-e 'alt-f))
(def doubled (song-pattern (edit-song st) "p"))
(spec-keys! st (list 'alt-g))
(def halved (song-pattern (edit-song st) "p"))
(spec-keys! st (list 'alt-u 'home 'alt-right 'insert))
(write (list doubled halved (song-pattern (edit-song st) "p")))
```
---
    ((("a" "C4" "." "D4" "." "E4" "." "." ".") ("b" "G4" "." "." "." "." "." "." ".")) (("a" "C4" "D4" "E4" "." "." "." "." ".") ("b" "G4" "." "." "." "." "." "." ".")) (("a" "C4" "D4" "E4" "." "." "." "." ".") ("b" "." "G4" "." "." "." "." "." ".")))

## the pages

### F11 is the order list: up and down a place, left and right its pattern, Insert copies

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (pattern q (a \"D4\")) (order p q))") () ()))
(def screen (Screen make 12 50))
(spec-keys! st (list 'f11 'down 'right 'insert))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 3 8)))
(spec-keys! st (list 'enter))
(write (list (song-order (edit-song st)) (List ref 0 (edit-place st))))
```
---
```output
 Order list

  000  p                1 rows
  001  p                1 rows
  002  p                1 rows
(("p" "p" "p") "p")
```

### F12 is the song's settings: left and right change them, Enter types one

```tracker
(def st (edit-make (file-parse "(song \"t\" (bpm 120) (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(spec-keys! st (list 'f12 'down 'right 'right 'down 'down 'down 'down 'down 'left))
(def screen (Screen make 16 80))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 3 16)))
```
---
```output
 Song variables

  Name                           t
  Tempo, beats a minute          122
  Rows a beat                    4
  Ticks a row                    6
  Tempo added at full tension    0
  Octave typed in                4
  Step after a note              0
  Follow the playing             on
  A new effect

 Song   up down pick   left right change   Enter type it   F2 the pattern
```

### every page is Alt and its place in the row too, shown beside its F-key where the row fits; :page NAME by name or the start of it; its key can be bound

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def page (fn (_ k) (spec-keys! st (list k)) (Vector ref 30 st)))
(def alts (List map page (list 'alt-6 'alt-7 'alt-4 'alt-3 'alt-2)))
(def typed (List map (fn (_ line) (spec-keys! st (list line 'enter)) (Vector ref 30 st)) (list ":page o" ":page ins" ":page song" ":page pat")))
(spec-keys! st (list ":page zz" 'enter))
(def unknown (edit-message st))
(spec-keys! st (list ":set key page-order \"o\"" 'enter "o"))
(def bound (Vector ref 30 st))
(def row-at (fn (_ cols) ((fn (_ s) (spec-draw! st s) (Str8 trim-right (Screen row-text s 2))) (Screen make 8 cols))))
(write (list alts typed unknown bound (row-at 124) (row-at 90)))
```
---
    (('orders 'song 'instruments 'samples 'pattern) ('orders 'instruments 'song 'pattern) ":page help pattern samples instruments info order song" 'orders " F1/Alt-1 Help  F2/Alt-2 Pattern  F3/Alt-3 Samples  F4/Alt-4 Instruments  F5/Alt-5 Info  F11/Alt-6 Order  F12/Alt-7 Song" " F1 Help  F2 Pattern  F3 Samples  F4 Instruments  F5 Info  F11 Order  F12 Song")

### F4 lists the instruments; Tab and down pick their envelope, left and right its points, Enter picks one up for the arrows

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (instrument b (wave noise) (env (0 0) (10 80) (200 0))) (pattern p (a \"C4\")) (order p))") () ()))
(spec-keys! st (list 'f4 'down 'complete 'down 'right 'enter 'up 'up 'alt-right 'enter 'insert 'left 'left 'delete))
(write (song-instrument-text (edit-song st) "b"))
(def screen (Screen make 30 100))
(spec-draw! st screen)
(write (list (Str8 trim-right (Screen row-text screen 5)) (Str8 trim-right (Screen row-text screen 6))))
```
---
    "(instrument b (wave noise) (env (20 82) (110 41) (200 0)))"("  01 a                     (wave noise)" "  02 b                     (env (20 82) (110 41) (200 0))")

### On F4 Tab gives the keys to the props: left and right change one, Space turns a layer, Enter types its value, Delete drops it and Insert adds one it lacks

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (instrument b (wave noise) (gain 80) (pan 0) (layer calm) (env (0 100) (100 0))) (pattern p (a \"C4\")) (order p))") () ()))
(def text (fn (_) (song-instrument-text (edit-song st) "b")))
(spec-keys! st (list 'f4 'down 'complete 'right 'down 'right 'alt-right 'down))
(spec-keys! st (List repeat 11 'alt-left))
(spec-keys! st (list 'down " "))
(def stepped (text))
(spec-keys! st (list 'up 'delete 'insert 'down))
(def screen (Screen make 24 100))
(spec-draw! st screen)
(def adding (List map (fn (_ r) (Str8 trim-right (Str8 sub 26 40 (Screen row-text screen r)))) (list 3 5 6 9)))
(spec-keys! st (list 'enter))
(def added (list (text) (Vector ref 51 st)))
(spec-keys! st (list 'enter 'backspace "25" 'enter))
(def typed (text))
(spec-keys! st (list 'ctrl-z))
(def undone (text))
(spec-keys! st (list 'insert 'escape))
(def back (list (Vector ref 51 st) (Vector ref 30 st)))
(spec-keys! st (list 'complete))
(write (list stepped adding added typed undone back (Vector ref 51 st)))
```
---
    ("(instrument b (wave metal) (gain 91) (pan -100) (layer tension) (env (0 100) (100 0)))" ("Add to b" " (release 200)" " (pan 0)" " (width (0 50))") ("(instrument b (wave metal) (gain 91) (layer tension) (pan 0) (env (0 100) (100 0)))" 3) "(instrument b (wave metal) (gain 91) (layer tension) (pan 25) (env (0 100) (100 0)))" "(instrument b (wave metal) (gain 91) (layer tension) (pan 0) (env (0 100) (100 0)))" (3 'instruments) ())

### F3 lists the samples; :sample keeps a WAV file as a wave an instrument can play

```tracker
(def dir (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-sample"))
(unless (File exists? dir) (File mkdir dir))
(def pl (player-open () ()))
(player-render! pl (song-parse "(song \"click\" (bpm 600) (instrument a (wave sine) (env (0 90) (40 0))) (pattern p (a \"C4\")) (order p))") (Str8 append dir "/click.wav"))
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") (Str8 append dir "/song.xon") ()))
(spec-keys! st (list 'f3 ":sample click click.wav C4" 'enter))
(def said (edit-message st))
(def screen (Screen make 8 80))
(spec-draw! st screen)
(write (list said (Str8 trim-right (Screen row-text screen 5)) (file-wave (edit-doc st) "click") (player-wave? "click")))
```
---
    ("Sample click: click.wav. An instrument plays it with (wave click)." "  click          click.wav                  Default volume  64" ('wave 'click ('sample "click.wav" "C4")) #t)
