# A MIDI keyboard
@weight 1

Notes played on a MIDI keyboard: heard as typed ones are, a chord's
together, and put in the pattern at the cursor, the velocity the volume
column's gain, the cursor moved on by the step.

## the settings

### (midi on|off|"DEVICE") is read as the editor starts; (midi-off on|off) any time

```tracker
(def cfg (config-default))
(def a (list (config-get cfg 'midi) (config-get cfg 'midi-off)))
(def b (list (config-set! cfg (list 'midi "Keystation 49") #f) (config-get cfg 'midi)
             (config-set! cfg (list 'midi 'off) #f) (config-get cfg 'midi)
             (config-set! cfg (list 'midi 3) #f)
             (config-set! cfg (list 'midi 'on) #t)
             (config-set! cfg (list 'midi-off 'on) #t) (config-get cfg 'midi-off)))
(write (list a b))
```
---
    ((#t #f) (() "Keystation 49" () #f "midi on, off, or a device's name, \"Keystation 49\"" "midi is read as the editor starts: the config file" () #t))

## playing

### a note played goes in the cursor's cell, its velocity the gain, its effects kept, and the cursor moves by the step

```tracker
(import x/sys/midi)
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \". ./v20,4 . . . . . .\")) (order p))") () ()))
(def play! (fn (_ bytes) (List for-each (fn (_ m) (edit-key! st (pair 'midi m))) (Midi decode bytes))))
(spec-keys! st (list ":step 1" 'enter))
(play! (list 144 60 127 144 62 100 128 62 0))
(spec-keys! st (list ">"))
(play! (list 144 60 64 144 60 0))
(spec-keys! st (list ":set midi-off on" 'enter))
(play! (list 144 64 127 144 67 127 128 64 0))
(def before-off (edit-place st))
(play! (list 128 67 0))
(spec-keys! st (list 'f4))
(play! (list 144 72 127))
(write (list (rest (first (song-pattern (edit-song st) "p"))) before-off (edit-place st)))
```
---
    (("C4" "D4:79/v20,4" "C5:50" "E5" "G5" "-" "." ".") ("p" 5 0) ("p" 6 0))

### a chord's notes are heard together; a note typed cuts off the one before

```tracker
(def s (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine))\n  (pattern p (a \"C4\"))\n  (order p))"))
(def pl (player-open (spec-front) ()))
(player-preview! pl s "a" "C4" #t)
(player-preview! pl s "a" "E4" #t)
(def chord (List length (Vector ref 14 pl)))
(player-preview! pl s "a" "G4")
(def typed (List length (Vector ref 14 pl)))
(player-pump! pl)
(write (list chord typed (List length (Vector ref 14 pl))))
```
---
    (2 1 0)
