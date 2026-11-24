; # x-tracker -- a music tracker on x-lang
;
; ## tracker/cell.x -- a cell as Impulse Tracker's columns show it
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A cell is text, NOTE[:GAIN][/EFFECT...] (x/audio/tracker), and the song
; keeps it so.  The pattern editor shows it in the columns of Impulse
; Tracker's: the note, the instrument, the volume and the effect.
;
;   C4:60/v20,6/f30   C-4 01  60 v20,6+
;   .                 ... ..  .. .......
;   -                 === ..  .. .......
;   ./c0              ^^^ ..  .. .......
;
; The note is its letter, # or -, and octave: C-4, C#4, a flat as the
; sharp below it.  A let-go is IT's note off, ===; a hold with the
; effect c0 first, a cut there and then, IT's note cut, ^^^.  The
; instrument is the channel's: x-tracker plays a channel with one
; instrument.  The volume is the gain, in percent of the instrument's,
; nothing at 100.  The effect is the first, its letter and numbers, +
; when there are more.

(module tracker/cell)

(import x/audio/mixer)
(import x/core/doors int/ int% int< str-byte-len str-byte-ref str-byte-sub)

(def %cl-names (list "C-" "C#" "D-" "D#" "E-" "F-" "F#" "G-" "G#" "A-" "A#" "B-"))

; CELL as (NOTE GAIN EFFECTS): NOTE its note, "." or "-"; GAIN its
; percent, nil for none; EFFECTS each effect's text after its /.
(def cell-parts
  (fn (_ cell)
    (def parts (Str8 split "/" cell))
    (def head (Str8 split ":" (first parts)))
    (list (first head)
          (if (null? (rest head)) () ((prim-ref (lit convert) (lit to)) (List ref 1 head) (Type named INTEGER) 10))
          (List filter (fn (_ e) (not (str=? e ""))) (rest parts)))))

; The cell of NOTE, GAIN and EFFECTS, as cell-parts answers them.
(def cell-join
  (fn (_ note gain effects)
    (Str8 append note
      (if (if (null? gain) #t (= gain 100)) "" (Str8 append ":" (Str8 str gain)))
      (Str8 join "" (List map (fn (_ e) (Str8 append "/" e)) effects)))))

; Whether NOTE, as cell-parts answers it, is a note: not a hold or a let-go.
(def cell-note? (fn (_ note) (not (if (str=? note ".") #t (str=? note "-")))))

; Whether the cell of NOTE and EFFECTS is IT's note cut: a hold cut at once.
(def %cl-cut?
  (fn (_ note effects)
    (if (str=? note ".") (if (pair? effects) (str=? (first effects) "c0") #f) #f)))

; NOTE as the note column shows it, three characters.
(def %cl-note
  (fn (_ note effects)
    (match ((%cl-cut? note effects) "^^^")
           ((str=? note ".") "...")
           ((str=? note "-") "===")
           (#t ((fn (_ semi)
                  (if (null? semi) (Str8 sub 0 3 (Str8 append note "???"))
                    (Str8 append (List ref (int% semi 12) %cl-names) (Str8 str (int/ semi 12)))))
                (guard (e ()) (Mixer semitone note)))))))

; S right-aligned in W, or cut to its last W.
(def %cl-right
  (fn (_ w s)
    (def n (str-byte-len s))
    (if (int< n w) (Str8 append (Str8 sub 0 (- w n) "          ") s) (str-byte-sub s (- n w) w))))

; The effect column, W wide: the first effect cut to fit, + after it when
; it is cut or there are more.
(def %cl-effect
  (fn (_ effects w)
    (match ((null? effects) (Str8 sub 0 w "................"))
           (#t ((fn (_ e more)
                  (if (if more #t (int< w (str-byte-len e)))
                    (Str8 pad-right w #\space (Str8 append (str-byte-sub e 0 (%cl-min (- w 1) (str-byte-len e))) "+"))
                    (Str8 pad-right w #\space e)))
                (first effects) (pair? (rest effects)))))))

(def %cl-min (fn (_ a b) (if (< a b) a b)))

; CELL's columns as text: (NOTE INSTRUMENT VOLUME EFFECT), the
; instrument column INST, two characters, shown on a note's row; the
; volume three characters, the effect W.
(def cell-columns
  (fn (_ cell inst w)
    (def p (cell-parts cell))
    (def note (first p))
    (def cut (%cl-cut? note (List ref 2 p)))
    (def effects (if cut (rest (List ref 2 p)) (List ref 2 p)))
    (list (%cl-note note (List ref 2 p))
          (if (cell-note? note) inst "..")
          (if (null? (List ref 1 p)) "..." (%cl-right 3 (Str8 str (List ref 1 p))))
          (%cl-effect effects w))))

(provide tracker/cell cell-parts cell-join cell-note? cell-columns)
