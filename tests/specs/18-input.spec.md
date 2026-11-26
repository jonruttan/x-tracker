# The line typed
@weight 1

A command, a cell, effects or an instrument typed on the last line, as
x-lang's own lines take it (tracker/field): a cursor that shows and
moves, the lines of its kind typed before, and its text coloured.

## editing

### the cursor moves by a character, a word and to either end, and text goes in and out at it

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def line (fn (_) ((fn (_ f) (list (field-line f) (field-point f))) (rest (Vector ref 45 st)))))
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

## the history

### Up and Down walk the lines of the kind typed before, the line being typed kept; another kind has its own

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def text (fn (_) (field-text (rest (Vector ref 45 st)))))
(spec-keys! st (list ":" "bpm 100" 'enter ":" "rows 3" 'enter ":" "tic"))
(def walked (list (text) (do (spec-keys! st (list 'up)) (text)) (do (spec-keys! st (list 'up)) (text))
                  (do (spec-keys! st (list 'up)) (text)) (do (spec-keys! st (list 'down 'down)) (text))))
(spec-keys! st (list 'escape 'enter 'up))
(def cell (text))
(spec-keys! st (list 'escape))
(write (list walked cell (song-prop (edit-song st) "bpm" 0)))
```
---
    (("tic" "rows 3" "bpm 100" "bpm 100" "tic") "C4" 100)

### ctrl-r searches back as it is typed, ctrl-r again the one before; Enter takes the match, ctrl-g leaves the search

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(def f (fn (_) (rest (Vector ref 45 st))))
(spec-keys! st (list ":" "bpm 100" 'enter ":" "rows 3" 'enter ":" "bpm 120" 'enter ":" 'search-back "bp"))
(def found (list (field-text (f)) (field-point (f))))
(spec-keys! st (list 'search-back))
(def again (field-text (f)))
(spec-keys! st (list 'abort))
(def left (field-text (f)))
(spec-keys! st (list 'search-back "row" 'enter))
(write (list found again left (song-prop (edit-song st) "rows" 0)))
```
---
    (("bpm 120" 0) "bpm 100" "" 3)

### the history is kept in its file, a line a time, and read back as the editor starts

```tracker
(def path (rest (File temp "/tmp/x-tracker-history-")))
(File unlink path)
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(edit-history-open! st path)
(spec-keys! st (list ":" "bpm 90" 'enter ":" "bpm 90" 'enter 'enter "/v20" 'enter))
(def lines (File read-lines path))
(def st2 (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4\")) (order p))") () ()))
(edit-history-open! st2 path)
(spec-keys! st2 (list ":" 'up))
(def back (field-text (rest (Vector ref 45 st2))))
(def kept (history-read path))
(File unlink path)
(write (list lines back kept))
```
---
    (("command bpm 90" "command bpm 90" "cell C4/v20") "bpm 90" (('cell "C4/v20") ('command "bpm 90")))

## colour

### a command's or an instrument's text is coloured as x-lang's is, a cell's volume and effects as the pattern's

```tracker
(def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \"C4:50/v20,4\")) (order p))") () ()))
(def screen (Screen make 6 60))
(def style (fn (_ name) (config-style (config-default) name)))
(spec-keys! st (list ":" "instrument b (wave sine) ; x"))
(spec-draw! st screen)
(def at (fn (_ col) (Screen style-at screen 5 col)))
(def command (list (= (at 14) (style 'off)) (= (at 20) (style 'instrument)) (= (at 27) (style 'empty)) (= (at 1) (style 'instrument))))
(spec-keys! st (list 'escape 'enter))
(spec-draw! st screen)
(def row (Screen row-text screen 5))
(def cell (list (Str8 trim-right row) (= (at 7) 0) (= (at 9) (style 'volume)) (= (at 12) (style 'effect))))
(write (list command cell))
```
---
    ((#t #t #t #t) ("cell: C4:50/v20,4" #t #t #t))
