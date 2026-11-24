# The editor
@weight 2

tracker/edit: keys pressed in an editor with no sound, and the screen it
draws.

## notes

### the piano's keys type notes down a channel, in the octave

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \". . . . . . . .\")) (order p))") () ()))
(spec-keys! st (list "zxc" ">" "q" "<<" "m" "."))
(write (song-pattern (edit-song st) "p"))
```
---
    (("a" "C4" "D4" "E4" "C6" "B3" "." "." "."))

### a note typed over a cell keeps its gain and effects; - lets go, . holds

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4:50/v20,4 D4 E4 F4\")) (order p))") () ()))
(spec-keys! st (list "g" "-" "."))
(write (song-pattern (edit-song st) "p"))
```
---
    (("a" "F#4:50/v20,4" "-" "." "F4"))

### Enter edits a cell's text; a cell that is none is refused

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4 D4\")) (order p))") () ()))
(spec-keys! st (list 'enter 'backspace 'backspace "A3/a4,7" 'enter 'enter 'kill-bol "H9" 'enter))
(write (list (song-pattern (edit-song st) "p") (edit-message st)))
```
---
    ((("a" "A3/a4,7" "D4")) "no note H9")

### rows are inserted and deleted, undone and done again

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4 D4 E4\")) (order p))") () ()))
(spec-keys! st (list 'down "I"))
(def after-insert (song-pattern (edit-song st) "p"))
(spec-keys! st (list "D" "D"))
(def after-deletes (song-pattern (edit-song st) "p"))
(spec-keys! st (list "U" "U"))
(def undone (song-pattern (edit-song st) "p"))
(spec-keys! st (list "R"))
(write (list after-insert after-deletes undone (song-pattern (edit-song st) "p")))
```
---
    ((("a" "C4" "." "D4")) (("a" "C4" "." ".")) (("a" "C4" "." "D4")) (("a" "C4" "D4" ".")))

## commands

### a song's tempo, a pattern's length, the order and a new pattern

```tracker
(def st (edit-make (file-parse "(song \"t\" (bpm 60)\n  (instrument a (wave sine))\n  (pattern p (a \"C4 D4\"))\n  (order p))") () ()))
(spec-keys! st (list ":bpm 90" 'enter ":rows 2" 'enter ":len 4" 'enter ":pattern q" 'enter "c" ":order p q p" 'enter))
(spec-lines (spec-song st))
(write (edit-place st))
```
---
```output
(song "t" (bpm 90) (rows 2)
  (instrument a (wave sine))
  (pattern p
    (a "C4 D4 .  ."))
  (pattern q
    (a "E4 .  .  ."))
  (order p q p))
("q" 1 0)
```

### instruments are made and changed, and channels added and dropped

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(spec-keys! st (list ":instrument b (wave noise) (hz 1)" 'enter ":channel b" 'enter "z"
                     ":channel nope" 'enter))
(def msg (edit-message st))
(spec-keys! st (list 'alt-left ":drop" 'enter ":drop" 'enter))
(spec-lines (spec-song st))
(write (list msg (edit-message st)))
```
---
```output
(song "t" (instrument a (wave sine))
  (instrument b (wave noise) (hz 1))
  (pattern p
    (b "C4"))
  (order p))
("No instrument nope." "A pattern keeps one channel.")
```

### E edits the channel's instrument on one line

```tracker
(def st (edit-make (file-parse "(song \"t\"\n  (instrument a (wave sine)\n    (gain 40))\n  (pattern p (a \"C4\"))\n  (order p))") () ()))
(spec-keys! st (list "E" 'backspace 'backspace 'backspace 'backspace "50))" 'enter))
(write (song-instrument-text (edit-song st) "a"))
```
---
    "(instrument a (wave sine) (gain 50))"

### [ and ] walk the order, and :song makes or picks a song

```tracker
(def st (edit-make (file-parse "(song \"one\" (instrument a (wave sine)) (pattern p (a \"C4\")) (pattern q (a \"D4\")) (order p q p))") () ()))
(spec-keys! st (list "]"))
(def a (edit-place st))
(spec-keys! st (list "]" "]"))
(def b (edit-place st))
(spec-keys! st (list ":song two" 'enter))
(def c (list (song-name (edit-song st)) (edit-place st)))
(spec-keys! st (list ":song one" 'enter))
(write (list a b c (song-name (edit-song st)) (List map song-name (file-songs (edit-doc st)))))
```
---
    (("q" 0 0) ("p" 0 0) ("two" ("a" 0 0)) "one" ("one" "two"))

### the pattern edited keeps its place in the order as the order changes

```tracker
(def st (edit-make (file-parse "(song \"one\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def screen (Screen make 6 80))
(def order-row (fn (_) (spec-draw! st screen) (Str8 trim-right (Screen row-text screen 1))))
(spec-keys! st (list ":pattern b" 'enter))
(def before (order-row))
(spec-keys! st (list ":order p b" 'enter))
(def put-in (order-row))
(spec-keys! st (list ":order b p b" 'enter))
(def moved (order-row))
(spec-keys! st (list ":order p" 'enter))
(write (list before put-in moved (order-row)))
```
---
    (" order: p   editing b, not in the order" " order: p [b]" " order: [b] p b" " order: p   editing b, not in the order")

### :q refuses once while there are changes, and :q! leaves

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(spec-keys! st (list "z" ":q" 'enter))
(def a (list (edit-quit? st) (edit-message st)))
(spec-keys! st (list ":q!" 'enter))
(write (list a (edit-quit? st)))
```
---
    ((#f "The song has changed: :w writes it, :q! leaves without.") #t)

### :w writes the file, the other songs and the comments as they were

```tracker
(def path (Str8 append ((fn (_ d) (if (null? d) "/tmp" d)) (Sys getenv "TMPDIR")) "/x-tracker-spec-w.xon"))
(File write-all path "; a comment\n(song \"a\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))\n\n; the second\n(song \"b\" (instrument b (wave sine)) (pattern p (b \"E4\")) (order p))\n")
(def st (edit-make (file-read path) path ()))
(spec-keys! st (list "x" ":w" 'enter))
(spec-lines (File read-all path))
(File unlink path)
(File unlink (Str8 append path ".bak"))
(write (Str8 starts? "Written: " (edit-message st)))
```
---
```output
; a comment
(song "a" (instrument a (wave sine))
  (pattern p
    (a "D4"))
  (order p))

; the second
(song "b" (instrument b (wave sine)) (pattern p (b "E4")) (order p))

#t
```

### with no sound, Space says so

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(spec-keys! st (list " "))
(write (edit-message st))
```
---
    "No sound: the audio could not be opened."

## the screen

### the pattern is drawn a row a line, a channel its note, instrument, volume and effect columns, the cursor's field marked

```tracker
(def st (edit-make (file-parse "(song \"tune\" (bpm 100) (rows 2)\n  (instrument lead (wave sine))\n  (instrument bass (wave sine))\n  (pattern p (lead \"C4 . E4:50 .\") (bass \"C2 - . G2/v20,4\"))\n  (order p p))") "t.xon" ()))
(def screen (Screen make 10 90))
(spec-keys! st (list 'down 'alt-right))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 0 10)))
(write (list (Style has? (Screen style-at screen 5 23) 'reverse) (Style has? (Screen style-at screen 5 27) 'reverse)))
```
---
```output
 x-tracker  t.xon   "tune"   bpm 100  rows 2  ticks 6   octave 4  step 1   (no sound)
 order: [p] p

     1 lead 01          2 bass 02
  0 C-4 01 ... ....... C-2 02 ... .......
  1 ... .. ... ....... === .. ... .......
  2 E-4 01  50 ....... ... .. ... .......
  3 ... .. ... ....... G-2 02 ... v20,4

 ? help   Space play   p pattern   : command
(#t #f)
```

### a command being typed is shown on the last line; ? shows the help's topics

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def screen (Screen make 8 70))
(spec-keys! st (list ":bpm 7"))
(spec-draw! st screen)
(def line (Str8 trim-right (Screen row-text screen 7)))
(spec-keys! st (list 'escape "?"))
(spec-draw! st screen)
(write (list line (Str8 trim-right (Screen row-text screen 2)) (Str8 trim-right (Screen row-text screen 3))))
```
---
    (":bpm 7" "Help: :help TOPIC, or :help WORD for every command, effect, prop or se" "  keys        every key, and the action :set key binds it by")

### :song alone lists the songs to pick from, in columns when they do not fit one

```tracker
(def songs (Str8 join "\n" (List map (fn (_ n) (Str8 append "(song \"s" (Str8 str n) "\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))")) (List range 0 7))))
(def st (edit-make (file-parse songs) () ()))
(def screen (Screen make 8 90))
(spec-keys! st (list ":song" 'enter 'down 'down))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 7)))
(def lit-row (list (Style has? (Screen style-at screen 5 4) 'reverse) (Style has? (Screen style-at screen 3 4) 'reverse)))
(spec-keys! st (list 'enter))
(def picked (song-name (edit-song st)))
(spec-keys! st (list ":song" 'enter 'up 'escape))
(write (list lit-row picked (song-name (edit-song st))))
```
---
```output
Songs   up, down: pick   Enter: edit it   Escape: close   :song NAME makes one
  > s0       s4
    s1       s5
    s2       s6
    s3
((#t #f) "s2" "s2")
```

### an order wider than the screen shows the part around the place edited, picked or heard

```tracker
(def names (List map (fn (_ n) (Str8 append "p" (Str8 str n))) (List range 0 20)))
(def st (edit-make (file-parse (Str8 append "(song \"t\" (instrument a (wave sine))"
  (Str8 join "" (List map (fn (_ n) (Str8 append " (pattern " n " (a \"C4\"))")) names))
  " (order " (Str8 join " " names) "))")) () ()))
(def screen (Screen make 6 40))
(def order-row (fn (_) (spec-draw! st screen) (Str8 trim-right (Screen row-text screen 1))))
(def start (order-row))
(spec-keys! st (List repeat 12 "]"))
(def edited (order-row))
(spec-keys! st (list "O" 'left 'left 'left 'left 'left 'left 'left 'left))
(def picked (order-row))
(spec-keys! st (list 'escape "]]]]]]]"))
(write (list start edited picked (order-row)))
```
---
    (" order: [p0] p1 p2 p3 p4 p5 p6 p7 p8 ..." " order: ... p7 p8 p9 p10 p11 [p12] ..." " order: p0 p1 p2 p3 <p4> p5 p6 p7 p8 ..." " order: ... p14 p15 p16 p17 p18 [p19]")

### a command line longer than the screen shows its end, where the cursor is

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def screen (Screen make 6 40))
(def last-row (fn (_) (spec-draw! st screen) (Str8 trim-right (Screen row-text screen 5))))
(spec-keys! st (list ":instrument kick (wave sine)"))
(def short (last-row))
(spec-keys! st (list " (note \"C2\") (env (0 0) (2 95) (140 0)) (bend (0 700) (45 0)) (release 30) (gain 60)"))
(def long (last-row))
(spec-keys! st (list 'backspace 'backspace))
(write (list short long (last-row)))
```
---
    (":instrument kick (wave sine)" ":...700) (45 0)) (release 30) (gain 60)" ":...0 700) (45 0)) (release 30) (gain 6")

### a title wider than the screen leaves out rows and ticks first, then octave and step, then bpm

```tracker
(def st (edit-make (file-parse "(song \"tune\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") "t.xon" ()))
(def title (fn (_ w) (def s (Screen make 6 w)) (spec-draw! st s) (Str8 trim-right (Screen row-text s 0))))
(write (list (title 90) (title 70) (title 52) (title 40) (title 30)))
```
---
    (" x-tracker  t.xon   \"tune\"   bpm 90  rows 4  ticks 6   octave 4  step 1   (no sound)" " x-tracker  t.xon   \"tune\"   bpm 90   octave 4  step 1   (no sound)" " x-tracker  t.xon   \"tune\"   bpm 90   (no sound)" " x-tracker  t.xon   \"tune\"   (no sound)" " x-tracker  t.xon   (no sound)")

### a list too wide for the screen, with nothing to pick in it, pages as the help does

```tracker
(def names (List map (fn (_ n) (Str8 append "pat" (Str8 str n))) (List range 0 12)))
(def st (edit-make (file-parse (Str8 append "(song \"t\" (instrument a (wave sine))"
  (Str8 join "" (List map (fn (_ n) (Str8 append " (pattern " n " (a \"C4\"))")) names))
  " (order pat0))")) () ()))
(def screen (Screen make 8 60))
(spec-keys! st (list ":patterns" 'enter))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 8)))
(spec-keys! st (list 'end))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 7)))
```
---
```output
Patterns   :pattern NAME edits one   :copy-pattern NEW, :ren
  pat0           1 rows  a   played 1x
  pat1           1 rows  a   (not in the order)
  pat2           1 rows  a   (not in the order)
  pat3           1 rows  a   (not in the order)
 n p: the next topic, the one before   arrows PgUp PgDn: scr
Patterns   :pattern NAME edits one   :copy-pattern NEW, :ren
  pat8           1 rows  a   (not in the order)
  pat9           1 rows  a   (not in the order)
  pat10          1 rows  a   (not in the order)
  pat11          1 rows  a   (not in the order)
```

### a list of songs too wide for the screen starts from the column of the one picked

```tracker
(def songs (Str8 join "\n" (List map (fn (_ n) (Str8 append "(song \"song" (Str8 str n) "\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))")) (List range 0 30))))
(def st (edit-make (file-parse songs) () ()))
(def screen (Screen make 7 100))
(spec-keys! st (list ":song" 'enter 'end))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 6)))
(spec-keys! st (list 'home))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 6)))
(write (Style has? (Screen style-at screen 3 2) 'reverse))
```
---
```output
Songs   up, down: pick   Enter: edit it   Escape: close   :song NAME makes one   (9 to the left)
    song9        song12       song15       song18       song21       song24       song27
    song10       song13       song16       song19       song22       song25       song28
    song11       song14       song17       song20       song23       song26       song29
Songs   up, down: pick   Enter: edit it   Escape: close   :song NAME makes one   (9 to the right)
  > song0        song3        song6        song9        song12       song15       song18
    song1        song4        song7        song10       song13       song16       song19
    song2        song5        song8        song11       song14       song17       song20
#t
```

## editing the rest of a song

### a block is marked, copied, pasted, cut and transposed; channels move

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (instrument b (wave noise))\n  (pattern p (a \"C4 D4 E4 F4\") (b \"G4 . . .\"))\n  (order p))") () ()))
(spec-keys! st (list "V" 'down 'alt-right "Y" 'down 'down "P"))
(def pasted (spec-song st))
(spec-keys! st (list 'home 'alt-left "V" 'down ":transpose 12" 'enter ":gain 40" 'enter 'escape))
(def moved (spec-song st))
(spec-keys! st (list 'end "V" 'up "X" ")" ":channel-instrument b" 'enter))
(spec-lines pasted) (spec-lines moved) (spec-lines (spec-song st))
(write (list (edit-place st) (edit-message st)))
```
---
```output
(song "t" (instrument a (wave sine)) (instrument b (wave noise))
  (pattern p
    (a "C4 D4 E4 F4")
    (b "G4 .  .  C4"))
  (order p))
(song "t" (instrument a (wave sine)) (instrument b (wave noise))
  (pattern p
    (a "C5:40 D5:40 E4    F4")
    (b "G4    .     .     C4"))
  (order p))
(song "t" (instrument a (wave sine)) (instrument b (wave noise))
  (pattern p
    (b "G4    .     .     C4")
    (b "C5:40 D5:40 .     ."))
  (order p))
(("p" 2 1) "")
```

### O edits the order in place

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine))\n  (pattern p (a \"C4\")) (pattern q (a \"D4\"))\n  (order p q))") () ()))
(spec-keys! st (list "O" 'right "i" 'down "[" 'left 'down))
(def during (song-order (edit-song st)))
(spec-keys! st (list 'enter))
(write (list during (edit-place st) (edit-message st)))
```
---
    (("q" "p" "q") ("q" 0 0) "")

### effects, instruments, patterns and songs are listed, copied, renamed and dropped

```tracker
(def st (edit-make (file-parse "(song \"t\" (echo 300 40 20)\n  (instrument a (wave sine))\n  (pattern p (a \"C4\"))\n  (order p))\n(song \"u\" (instrument a (wave sine)) (pattern r (a \"C4\")) (order r))") () ()))
(def screen (Screen make 8 110))
(spec-keys! st (list ":effects" 'enter))
(spec-draw! st screen)
(spec-lines (spec-rows screen (List range 2 4)))
(spec-keys! st (list 'escape ":effect (reverb 120 80 30)" 'enter ":effect 1" 'enter 'kill-bol "(echo 100 20 10)" 'enter ":effect drop 2" 'enter))
(def fx (song-effects (edit-song st)))
(spec-keys! st (list ":copy-instrument a b" 'enter ":rename-instrument a lead" 'enter ":drop-instrument lead" 'enter))
(def dropped (edit-message st))
(spec-keys! st (list ":drop-instrument b" 'enter ":copy-pattern q" 'enter ":rename-pattern chorus" 'enter ":drop-pattern p" 'enter))
(def pats (list (List map first (song-patterns (edit-song st))) (song-order (edit-song st)) (song-instruments (edit-song st))))
(spec-keys! st (list ":instrument bass" 'enter))
(def typed (edit-message st))
(spec-keys! st (list 'enter ":copy-song v" 'enter))
(def copied (List map song-name (file-songs (edit-doc st))))
(spec-keys! st (list ":drop-song" 'enter))
(def after-drop (list (List map song-name (file-songs (edit-doc st))) (song-name (edit-song st)) (edit-message st)))
(spec-keys! st (list "U"))
(write (list fx dropped pats (song-instruments (edit-song st)) copied after-drop (List map song-name (file-songs (edit-doc st)))))
```
---
```output
Effects over the mix, in order   :effect (NAME N ...) adds one   :effect K edits the Kth   :effect drop K
   1  (echo 300 40 20)
(("(echo 100 20 10)") "lead plays in p: drop its channels first." (("chorus") () ("lead")) ("lead" "bass") ("t" "u" "v") (("t" "u") "u" "Dropped v: U brings it back.") ("t" "u" "v"))
```
