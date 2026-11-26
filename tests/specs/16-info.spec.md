# The info page
@weight 2

F5 as Schism Tracker has it: the song played and what plays shown,
channel by channel, with the rows about the one heard; Shift-F8 pauses
and plays on.

## playing

### F5 plays the song and shows the place, each channel's last note and the rows heard

```tracker
(def pl (player-open (spec-front) ()))
(def st (edit-make (file-parse "(song \"t\" (bpm 240) (rows 4)\n  (instrument lead (wave sine))\n  (instrument bass (wave sine))\n  (pattern p (lead \"C4 . E4:50 . G4 . . .\") (bass \"C2 . . . - . . .\"))\n  (pattern q (lead \"D4 . . . . . . .\") (bass \"D2 . . . . . . .\"))\n  (order p q))") () pl))
(spec-keys! st (list 'f5))
(def page (Vector ref 30 st))
(edit-tick! st)
(spec-play! 30000)
(edit-tick! st)
(def screen (Screen make 20 100))
(spec-draw! st screen)
(player-stop! pl)
(write (list page (List map (fn (_ i) (Str8 trim-right (Screen row-text screen i))) (List range 3 18))))
```
---
    ('info (" Info   place 1 of 2, pattern p, row 2 of 8   voices 5   tension 0   pace 100%   volume 100%" " Ch  Instrument    Note  Gain  Rows ago" "  1  lead          E-4     50         0" "  2  bass          C-2    100         2" "" " Rows" "" "" "    0 C-4 C-2" "    1 ... ..." " >  2 E-4 ..." "    3 ... ..." "    4 G-4 ===" "    5 ... ..." "    6 ... ..."))

### up, down and M mute a channel; Enter edits the pattern heard

```tracker
(def pl (player-open (spec-front) ()))
(def st (edit-make (file-parse "(song \"t\" (bpm 240) (rows 4)\n  (instrument lead (wave sine))\n  (instrument bass (wave sine))\n  (pattern p (lead \"C4 . E4 . G4 . . .\") (bass \"C2 . . . - . . .\"))\n  (pattern q (lead \"D4 . . . . . . .\") (bass \"D2 . . . . . . .\"))\n  (order p q))") () pl))
(spec-keys! st (list 'f5))
(spec-play! 200000)
(edit-tick! st)
(spec-keys! st (list 'down "m"))
(def said (edit-message st))
(spec-keys! st (list 'enter))
(player-stop! pl)
(write (list said (player-muted? pl 'channel 1) (Vector ref 30 st) (edit-place st)))
```
---
    ("Channel 1 muted." #t 'pattern ("p" 0 1))

### Shift-F8 stops where it is heard and plays on from there

```tracker
(def pl (player-open (spec-front) ()))
(def st (edit-make (file-parse "(song \"t\" (bpm 240) (rows 4)\n  (instrument lead (wave sine))\n  (pattern p (lead \"C4 . E4 . G4 . . .\"))\n  (order p))") () pl))
(spec-keys! st (list 'ctrl-f5))
(def page (Vector ref 30 st))
(spec-play! 200000)
(edit-tick! st)
(spec-keys! st (list 'shift-f8))
(def a (list (player-playing? pl) (edit-message st)))
(spec-keys! st (list 'shift-f8))
(def b (player-playing? pl))
(spec-keys! st (list 'shift-f8 'shift-f8 'f8 'shift-f8))
(player-stop! pl)
(write (list page a b (edit-message st)))
```
---
    ('pattern (#f "Paused at row 0: Shift-F8 plays on.") #t "Nothing is paused.")
