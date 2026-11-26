# The player's features
@weight 2

Muting and soloing, playing from a row, looping rows, the volume, and a
song rendered to a WAV file: tracker/player through the stand-in for
SDL's audio (spec-front), and the editor's keys and commands for them.

## who is heard

### a channel or an instrument muted is not heard; a solo hears only itself

```tracker
(def pl (player-open (spec-front) ()))
(def hears (fn (_) (list (player-hears? pl 0 "a") (player-hears? pl 1 "b") (player-hears? pl 2 "a"))))
(def all (hears))
(player-mute! pl 'channel 0)
(def ch-muted (hears))
(player-mute! pl 'channel 0)
(player-mute! pl 'instrument "a")
(def in-muted (hears))
(player-unmute! pl)
(player-solo! pl 'channel 1)
(def ch-solo (hears))
(player-solo! pl 'instrument "a")
(def both-solo (hears))
(write (list all ch-muted in-muted ch-solo both-solo (player-soloed? pl 'channel 1) (player-muted? pl 'channel 1)))
```
---
    ((#t #t #t) (#f #t #t) (#f #t #f) (#f #t #f) (#t #t #t) #t #f)

### a mute while a song plays starts it again from the row after the one heard

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'song 0 ())
(player-pump! pl)
(spec-play! 12000)
(def before (player-place pl))
(player-mute! pl 'channel 0)
(player-pump! pl)
(write (list before (player-place pl) (player-playing? pl)))
```
---
    ((0 . 0) (0 . 1) #t)

## from a row, and looping rows

### a song started at a row is heard there, and goes on into the next pattern

```tracker
(def pl (player-open (spec-front) ()))
(player-start-at! pl spec-tune 'song 0 () 2)
(player-pump! pl)
(def started (player-place pl))
(spec-play! 30000)
(def later (player-place pl))
(write (list started (first later)))
```
---
    ((0 . 2) 1)

### a pattern looped over a range of its rows keeps to them

```tracker
(def s (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine))\n  (pattern p (a \"C4 D4 E4 F4 G4 A4 B4 C5\"))\n  (order p))"))
(def pl (player-open (spec-front) ()))
(player-loop! pl (pair 2 4))
(player-start! pl s 'pattern 0 "p")
(def spin (fn (self n seen)
            (if (< 0 n)
              (do (spec-play! 4096) (player-pump! pl)
                  (self (- n 1) (if (List includes? (rest (player-place pl)) seen) seen (pair (rest (player-place pl)) seen))))
              seen)))
(def seen (spin 80 ()))
(write (list (player-loop pl) (List sort < seen)))
```
---
    ((2 . 4) (2 3 4))

### a pattern started at a row inside a loop plays to its end, then the loop

```tracker
(def s (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine))\n  (pattern p (a \"C4 D4 E4 F4 G4 A4 B4 C5\"))\n  (order p))"))
(def pl (player-open (spec-front) ()))
(player-loop! pl (pair 1 5))
(player-start-at! pl s 'pattern 0 "p" 4)
(player-pump! pl)
(def started (player-place pl))
(spec-play! 30000)
(write (list started (player-place pl)))
```
---
    ((0 . 4) (0 . 1))

## tension, pace and volume

### each is kept, and heard by the song playing

```tracker
(def pl (player-open (spec-front) ()))
(player-start! pl spec-tune 'song 0 ())
(player-tension! pl 40)
(player-pace! pl 80)
(player-volume! pl 50)
(write (list (player-tension pl) (player-pace pl) (player-volume pl)))
```
---
    (40 80 50)

## rendering

### a song rendered is a WAV file of its frames, ringing out

```tracker
(import x/core/doors str-make str-byte-sub)
(def path (rest (File temp "/tmp/x-tracker-spec-")))
(def pl (player-open () ()))
(def frames (player-render! pl spec-tune path))
(def fd (File open path 'rdonly))
(def size (File seek fd 0 'end))
(File seek fd 0)
(def head (str-make 44))
(File read fd head 44)
(File close fd)
(File unlink path)
(write (list (= size (+ 44 (* 4 frames))) (str-byte-sub head 0 4) (str-byte-sub head 8 8) (< 44100 frames) (< frames 176400)))
```
---
    (#t "RIFF" "WAVEfmt " #t #t)

### a channel muted is silent in the file

```tracker
(import x/core/doors str-make char->int str-byte-ref)
(def nonzero
  (fn (_ muted)
    (def path (rest (File temp "/tmp/x-tracker-spec-")))
    (def pl (player-open () ()))
    (when muted (player-mute! pl 'channel 0))
    (player-render! pl spec-tune path)
    (def fd (File open path 'rdonly))
    (File seek fd 4000)
    (def buf (str-make 8000))
    (File read fd buf 8000)
    (File close fd)
    (File unlink path)
    (List fold (fn (_ n i) (if (= 0 (char->int (str-byte-ref buf i))) n (+ n 1))) 0 (List range 0 8000))))
(write (list (< 0 (nonzero #f)) (nonzero #t)))
```
---
    (#t 0)

## the editor's keys

### M and S mute and solo the cursor's channel, H and A its instrument; :unmute hears all

```tracker
(def parsed (file-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine))\n  (instrument b (wave sine))\n  (pattern p (a \"C4 . E4 .\") (b \"C3 . . .\"))\n  (order p))"))
(def st (edit-make parsed () (player-open (spec-front) ())))
(def screen (Screen make 8 60))
(def said (fn (_ keys) (spec-keys! st keys) (edit-message st)))
(def m1 (said (list "M")))
(spec-draw! st screen)
(def dim-a (Style has? (Screen style-at screen 3 5) 'dim))
(def m2 (said (list 'alt-right "S")))
(def m3 (said (list ":mute")))
(def m3 (said (list 'enter)))
(def m4 (said (list "H" "A")))
(def m5 (said (list ":unmute" 'enter)))
(def m6 (said (list ":mute" 'enter)))
(def m7 (said (list ":solo c" 'enter)))
(write (list m1 dim-a m2 m3 m4 m5 m6 m7))
```
---
    ("Channel 0 muted." #t "Channel 1 soloed." "Muted: channel 0.  Soloed: channel 1." "Instrument b soloed." "Every channel and instrument heard." "Nothing is muted or soloed." "No instrument c.")

### G plays from the cursor's row; L marks a row and L again loops to the cursor

```tracker
(def parsed (file-parse (song-text spec-tune)))
(def st (edit-make parsed () (player-open (spec-front) ())))
(def screen (Screen make 8 120))
(spec-keys! st (list 'down 'down "G"))
(edit-tick! st)
(def from (list (edit-message st) (player-mode (edit-player st)) (edit-place st)))
(spec-keys! st (list 'up "L"))
(def marked (edit-message st))
(spec-keys! st (list 'down 'down "L"))
(def looped (list (edit-message st) (player-loop (edit-player st)) (player-mode (edit-player st))))
(spec-draw! st screen)
(def title (Str8 includes? "> rows 1-3" (Screen row-text screen 0)))
(spec-keys! st (list "L" 'escape))
(def forgot (edit-message st))
(write (list from marked looped title forgot))
```
---
    (("Playing from row 2." 'song ("p" 2 0)) "Loop from row 1: L on its last row plays it, Escape forgets." ("Looping rows 1 to 3: p plays the whole pattern." (1 . 3) 'pattern) #t "")

### tension, pace and volume move by ten, kept in their bounds, and are shown

```tracker
(def parsed (file-parse (song-text spec-tune)))
(def st (edit-make parsed () (player-open (spec-front) ())))
(def screen (Screen make 8 140))
(spec-keys! st (list "'" "'" ";" "+" "_" "_" "0" "9" "9"))
(def said (edit-message st))
(spec-keys! st (list ";" ";" ";"))
(def floor (edit-message st))
(spec-keys! st (list "'" "'" ":volume 75" 'enter))
(spec-draw! st screen)
(write (list said floor (Str8 includes? "  tension 20  pace 90%  volume 75%" (Screen row-text screen 0))))
```
---
    ("Volume 80%." "Tension 0." #t)

### :render writes the song to a WAV file, with sound or without

```tracker
(def path (rest (File temp "/tmp/x-tracker-spec-")))
(def parsed (file-parse (song-text spec-tune)))
(def st (edit-make parsed () (player-open (spec-front) ())))
(spec-keys! st (list " " (Str8 append ":render " path) 'enter))
(def with (list (Str8 starts? "Rendered " (edit-message st)) (player-playing? (edit-player st)) (File exists? path)))
(File unlink path)
(def quiet (edit-make parsed () ()))
(spec-keys! quiet (list (Str8 append ":render " path) 'enter))
(def without (list (Str8 starts? "Rendered " (edit-message quiet)) (File exists? path)))
(File unlink path)
(spec-keys! quiet (list ":render" 'enter))
(write (list with without (edit-message quiet)))
```
---
    ((#t #f #t) (#t #t) ":render FILE   the song played once, to a WAV file")

## the command line

### render writes a song of a file to the WAV file -o names

```tracker
(def path "/tmp/x-tracker-spec-render.wav")
(def status (tracker-main (list "render" (Str8 append (Bundle root "tracker") "/data/demo.xon") "-o" path)))
(def wrote (File exists? path))
(File unlink path)
(write (list status wrote (tracker-main (list "render" (Str8 append (Bundle root "tracker") "/data/demo.xon"))) (tracker-main (list "-s" "nope" "render" (Str8 append (Bundle root "tracker") "/data/demo.xon") "-o" path))))
```
---
```output
Rendered /tmp/x-tracker-spec-render.wav: 0:14
(0 #t 2 1)
```

### a loop over places of the order plays only those, round and round

```tracker
(def s (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine))\n  (pattern p (a \"C4 . . .\"))\n  (pattern q (a \"E4 . . .\"))\n  (pattern r (a \"G4 . . .\"))\n  (order p q r p))"))
(def pl (player-open (spec-front) ()))
(player-order-loop! pl (pair 1 2))
(player-start! pl s 'song 0 ())
(def first-heard (player-place pl))
(def places ())
(def spin (fn (self n) (when (< 0 n) (do (spec-play! 4096) (player-pump! pl) (set! places (pair (first (player-place pl)) places)) (self (- n 1))))))
(spin 200)
(player-order-loop! pl (pair 2 9))
(player-start! pl s 'song 0 ())
(def held (player-place pl))
(write (list first-heard (List includes? 0 places) (List includes? 1 places) (List includes? 2 places) (List includes? 3 places) held))
```
---
    ((1 . 0) #f #t #t #f (2 . 0))

### on F11, L marks a place and L again loops to the one picked; L once more plays the whole order

```tracker
(def s (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine))\n  (pattern aa (a \"C4 . . .\"))\n  (pattern bb (a \"E4 . . .\"))\n  (pattern cc (a \"G4 . . .\"))\n  (order aa bb cc aa))"))
(def st (edit-make (file-parse (song-text s)) () (player-open (spec-front) ())))
(def screen (Screen make 12 120))
(def heard (fn (_) (first (player-place (edit-player st)))))
(spec-keys! st (list 'f11 'down "L"))
(def marked (edit-message st))
(spec-keys! st (list 'down "L"))
(def looped (list (edit-message st) (player-mode (edit-player st)) (heard)))
(spec-draw! st screen)
(def title (Str8 includes? "> loop 1-2" (Screen row-text screen 0)))
(def line (Screen row-text screen 1))
(def style (fn (_ name) (Screen style-at screen 1 (Str8 index-of name line))))
(def block (list (= (style "bb") (style "cc")) (= (style "bb") (style "aa"))))
(spec-keys! st (list " " " "))
(def again (heard))
(spec-keys! st (list "L"))
(def off (list (edit-message st) (player-mode (edit-player st))))
(spec-keys! st (list "L" 'escape))
(def forgot (edit-message st))
(spec-keys! st (list ":loop order 3 0" 'enter))
(def typed (edit-message st))
(spec-keys! st (list ":loop order" 'enter))
(write (list marked looped title block again off forgot typed (edit-message st)))
```
---
    ("Loop from place 1: L on its last place plays it, Escape forgets." ("Looping places 1 to 2 of the order: L on F11 or :loop order stops it." 'song 1) #t (#t #f) 1 ("The whole order is played." 'song) "" "Looping places 0 to 3 of the order: L on F11 or :loop order stops it." "The whole order is played.")
