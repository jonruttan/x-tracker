# The screen compiled
@weight 2
# @timeout-scale 4

tracker/app compiles x/tui/screen once the editor's first screen is
drawn.  The editor draws the same with it compiled; on an engine with no
JIT it stays interpreted and draws the same too.

## drawing

### the pattern, the order and the title draw the same with x/tui/screen compiled

```tracker
(import x/tool/fn-compile compile-module!)
(def st (edit-make (file-parse "(song \"tune\" (bpm 100) (rows 2)\n  (instrument lead (wave sine))\n  (instrument bass (wave sine))\n  (pattern p (lead \"C4 . E4:50 .\") (bass \"C2 - . G2/v20,4\"))\n  (order p p))") "t.xon" ()))
(def screen (Screen make 10 90))
(def frame (fn (_) (spec-draw! st screen) (list (spec-rows screen (List range 0 10)) (Screen render screen))))
(spec-keys! st (list 'down 'right))
(def before (frame))
(spec-keys! st (list 'down "z"))
(def before2 (frame))
(def st2 (edit-make (file-parse "(song \"tune\" (bpm 100) (rows 2)\n  (instrument lead (wave sine))\n  (instrument bass (wave sine))\n  (pattern p (lead \"C4 . E4:50 .\") (bass \"C2 - . G2/v20,4\"))\n  (order p p))") "t.xon" ()))
(compile-module! 'x/tui/screen)
(Heap collect)
(set! st st2)
(Screen repaint screen)
(Screen clear screen)
(Screen render screen)
(spec-keys! st (list 'down 'right))
(def after (frame))
(spec-keys! st (list 'down "z"))
(write (list (equal? (first before) (first after)) (equal? before2 (frame))))
```
---
    (#t #t)
