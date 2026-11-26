# The line typed
@weight 1

A command, a cell, effects or an instrument typed on the last line, as
a text field takes it: a cursor that shows and moves, and edits at it.

## editing

### the cursor moves by a character, a word and to either end, and text goes in and out at it

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def line (fn (_) (list (rest (Vector ref 12 st)) (rest (Vector ref 46 st)))))
(spec-keys! st (list ":" "bpm 12"))
(def a (line))
(spec-keys! st (list 'home 'right 'right 'right "x"))
(def b (line))
(spec-keys! st (list 'backspace 'delete 'end "0"))
(def c (line))
(spec-keys! st (list 'word-left))
(def d (line))
(spec-keys! st (list 'ctrl-left 'word-right))
(def e (line))
(spec-keys! st (list 'kill-word))
(def f (line))
(spec-keys! st (list "rows" 'kill-eol))
(def g (line))
(spec-keys! st (list 'end " 3" 'home 'kill-bol))
(def h (line))
(spec-keys! st (list 'escape ":" "x" 'left 'escape ":" "y"))
(write (list a b c d e f g h (line)))
```
---
    (("bpm 12" 6) ("bpmx 12" 4) ("bpm120" 6) ("bpm120" 0) ("bpm120" 6) ("" 0) ("rows" 4) ("rows 3" 0) ("y" 1))

### the prompt is drawn in the heading's colour, the character at the cursor in the cursor's, and a long line shows the part about the cursor

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def screen (Screen make 6 30))
(spec-keys! st (list ":" "bpm 120" 'left 'left))
(spec-draw! st screen)
(def a (list (Str8 trim-right (Screen row-text screen 5)) (= (Screen style-at screen 5 0) (config-style (config-default) 'heading))
             (= (Screen style-at screen 5 6) (config-style (config-default) 'cursor))))
(spec-keys! st (list 'end "abcdefghijklmnopqrstuvwxyz0123456789"))
(spec-draw! st screen)
(def b (Str8 trim-right (Screen row-text screen 5)))
(spec-keys! st (list 'home))
(spec-draw! st screen)
(write (list a b (Str8 trim-right (Screen row-text screen 5))))
```
---
    ((":bpm 120" #t #t) ":...mnopqrstuvwxyz0123456789" ":bpm 120abcdefghijklmnopqrstu")
