# The keys
@weight 1

tracker/keys: the bytes a terminal sends for a key, read into the key:
Alt, Shift and Ctrl with the keys Impulse Tracker's ways use, and every
other key as x/repl/term reads it.

## keys

### Alt and a character, Shift and an arrow, Alt and a function key

```tracker
(import x/core/doors char->int str-byte-ref)
(def keys-of
  (fn (_ text)
    (def bytes (List map (fn (_ i) (char->int (str-byte-ref text i))) (List range 0 (Str8 length text))))
    (def read (fn (_) (if (null? bytes) () ((fn (_ b) (set! bytes (rest bytes)) b) (first bytes)))))
    ((fn (self acc) ((fn (_ k) (if (null? k) (List reverse acc) (self (pair k acc)))) (keys-read read))) ())))
(write (keys-of "\x1bb\x1bB\x1b0\x1b[1;2A\x1b[1;2B\x1b[1;3D\x1b[20;3~\x1b[17;2~\x1b[2~\x1b[Z\x1b[1;5H\x1b[5;5~"))
```
---
    ('alt-b 'alt-B 'alt-0 'shift-up 'shift-down 'alt-left 'alt-f9 'shift-f6 'insert 'shift-tab 'ctrl-home 'ctrl-page-up)

### the keys Term reads are read as it reads them, and ctrl-s, ctrl-q and ctrl-z are keys

```tracker
(import x/core/doors char->int str-byte-ref)
(def keys-of
  (fn (_ text)
    (def bytes (List map (fn (_ i) (char->int (str-byte-ref text i))) (List range 0 (Str8 length text))))
    (def read (fn (_) (if (null? bytes) () ((fn (_ b) (set! bytes (rest bytes)) b) (first bytes)))))
    ((fn (self acc) ((fn (_ k) (if (null? k) (List reverse acc) (self (pair k acc)))) (keys-read read))) ())))
(write (keys-of "zA\x1b[A\x1b[3~\x1bOP\x1b[15~\r\t\x7f\x03\x13\x11\x1a\x1b"))
```
---
    ("z" "A" 'up 'delete 'f1 'f5 'enter 'complete 'backspace 'interrupt 'ctrl-s 'ctrl-q 'ctrl-z 'escape)
