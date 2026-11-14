# The guide
@weight 2
# @timeout-scale 2

docs/guide.md: its walkthrough's keys pressed in an editor playing
through the stand-in for SDL's audio, from a new file to the song it
ends with.  Each screen the guide shows, and the file it ends with, are
in the guide as the editor draws and writes them; each command and
string of keys pressed is in the guide; and the song plays through to
its end.

## the walkthrough

### the walkthrough's keys make the screens and the file the guide shows, and the song plays

```tracker
(def guide (File read-all (Str8 append %lang-root "/docs/guide.md")))
(def pl (player-open (spec-front) ()))
(def st (edit-make () "harbour.xon" pl))
(def screen (Screen make 24 100))
(def pressed ())
(def press (fn (_ keys) (set! pressed (List append pressed (List filter str? keys))) (spec-keys! st keys)))
(def shots ())
(def shot (fn (_ rows) (spec-draw! st screen) (set! shots (List append shots (list (spec-rows screen rows))))))
(shot (List range 0 20))
(press (list ":rename harbour" 'enter ":bpm 100" 'enter))
(press (list ":instrument kick (wave sine) (note \"C2\") (env (0 0) (2 95) (140 0)) (bend (0 700) (45 0)) (release 30) (gain 60)" 'enter
             ":instrument hat (wave noise) (hz 1) (cut 85) (env (0 0) (1 30) (35 0)) (release 15) (gain 18) (pan 30)" 'enter
             ":channel kick" 'enter ":step 4" 'enter "zzzz"
             ":channel hat" 'enter ":step 2" 'enter "zzzzzzzz"))
(shot (List range 0 20))
(press (list ":wave soft 8 3 1" 'enter ":instrument bass" 'enter))
(shot (list 23))
(press (list 'escape ":instrument bass (wave soft) (cut 30) (env (0 0) (6 80) (600 50)) (release 120) (gain 50)" 'enter
             ":channel bass" 'enter ":octave 2" 'enter ":step 8" 'enter "nv"))
(press (list 'left 'left 'left 'home ":octave 4" 'enter ":step 2" 'enter "ewq.qn" 'up 'up 'enter "/v20,6" 'enter))
(shot (List range 0 20))
(press (list ":copy-pattern b" 'enter 'right 'right 'right 'home ":octave 2" 'enter ":step 8" 'enter "zb"
             'left 'left 'left 'home ":octave 4" 'enter ":step 2" 'enter "etewq.m." 'up 'up 'up 'up 'enter "/p3" 'enter))
(press (list ":order a b a b" 'enter ":pattern b" 'enter))
(press (list ":wave glass 5 0 0 2 0 0 0 1" 'enter
             ":instrument bell (layer tension) (wave glass) (env (0 0) (3 40) (1200 0)) (release 600) (gain 22) (pan -30)" 'enter
             ":channel bell" 'enter 'home ":octave 5" 'enter ":step 8" 'enter "cb"))
(shot (List range 0 20))
(press (list ":effect (reverb 90 70 22)" 'enter ":effect (echo 300 30 15)" 'enter))
(def text (file-text (edit-doc st)))
(set! shots (List append shots (list text)))
(press (list " "))
(def playing (player-playing? pl))
(press (list " " ":tension 60" 'enter))
(def bdoc (file-parse text))
(def song (first (file-songs bdoc)))
(def heard
  (guard (e (e msg))
    (def p2 (player-open (spec-front) (file-waves bdoc)))
    (player-tension! p2 50)
    (player-start! p2 song 'once 0 ())
    (def spin (fn (self n) (if (if (< 0 n) (not (player-over? p2)) #f) (do (spec-play! 1000000) (player-pump! p2) (Heap collect) (self (- n 1))) n)))
    (< 0 (spin 600))))
(def missing (fn (_ xs) (List filter (fn (_ x) (null? (Str8 index-of x guide))) xs)))
(write (list (missing shots) (missing pressed) playing (player-playing? pl) (edit-message st) heard))
```
---
    (() () #t #f "" #t)
