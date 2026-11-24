# The editor's loop
@weight 2

tracker/app's loop, fed keys from a stand-in for the terminal: keys
already waiting are taken before the screen is drawn, and the heap is
not collected between keys typed one after another.

The stand-in's bytes are the keys; asked whether a key waits now, it
answers whether bytes are left, or #f when the typist is slow; asked
whether one comes within a while, always #t, so that with the bytes gone
the key read is nil and the loop ends.  Its terminal counts what it is
asked to do.

## keys

### keys already waiting are drawn once for them all, eight at most

```tracker
(import x/core/doors char->int str-byte-ref)
(def loop-run
  (fn (_ text quick)
    (def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \". . . . . . . . . . . . . . . . . . . . . .\")) (order p))") () ()))
    (def bytes (List map (fn (_ i) (char->int (str-byte-ref text i))) (List range 0 (Str8 length text))))
    (def reader (fn (_ . ask)
                  (if (null? ask) (if (null? bytes) () ((fn (_ b) (set! bytes (rest bytes)) b) (first bytes)))
                    (if (= 0 (List ref 1 ask)) (if quick (not (null? bytes)) #f) #t))))
    (def counts (list 0 0))
    (def term (fn (_ what)
                (when (eq? what 'draw) (set! counts (list (+ 1 (first counts)) (List ref 1 counts))))
                (when (eq? what 'collect) (set! counts (list (first counts) (+ 1 (List ref 1 counts)))))))
    (app-loop st reader term 0 0 0)
    (list counts (List length (List filter (fn (_ c) (str=? c "C4")) (rest (first (song-pattern (edit-song st) "p"))))))))
(write (list (loop-run "zzz" #t) (loop-run "zzzzzzzzzzzzzzzzzz" #t)))
```
---
    (((1 0) 3) ((2 1) 18))

### keys typed one at a time are each drawn, and collected for after sixteen

```tracker
(import x/core/doors char->int str-byte-ref)
(def loop-run
  (fn (_ text quick)
    (def st (edit-make (file-parse "(song \"t\" (instrument a (wave sine)) (pattern p (a \". . . . . . . . . . . . . . . . . . . . . .\")) (order p))") () ()))
    (def bytes (List map (fn (_ i) (char->int (str-byte-ref text i))) (List range 0 (Str8 length text))))
    (def reader (fn (_ . ask)
                  (if (null? ask) (if (null? bytes) () ((fn (_ b) (set! bytes (rest bytes)) b) (first bytes)))
                    (if (= 0 (List ref 1 ask)) (if quick (not (null? bytes)) #f) #t))))
    (def counts (list 0 0))
    (def term (fn (_ what)
                (when (eq? what 'draw) (set! counts (list (+ 1 (first counts)) (List ref 1 counts))))
                (when (eq? what 'collect) (set! counts (list (first counts) (+ 1 (List ref 1 counts)))))))
    (app-loop st reader term 0 0 0)
    counts))
(write (list (loop-run "zzz" #f) (loop-run "zzzzzzzzzzzzzzzzzzzz" #f)))
```
---
    ((3 0) (20 1))
