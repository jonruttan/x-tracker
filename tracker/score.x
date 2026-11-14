; # x-tracker -- a music tracker on x-lang
;
; ## tracker/score.x -- a score of channels, a cell a row, made a song
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; What an import makes before it is a song: channels of cells, each a
; vector of every row of the piece, played by an instrument.  The score
; is cut into patterns of so many rows, a pattern written once and
; named again in the order wherever it comes back.  A note held over a
; pattern's end, which the tracker ends there, is started again at the
; next pattern's first row.  A channel with nothing in a pattern is left
; out of it.

(module tracker/score)

(import x/type/vector)
(import x/core/doors int/ int%)
(import tracker/song song-parse song-set-pattern song-rename)

(def %sc-min (fn (_ a b) (if (< a b) a b)))

; A note's cell without its effects: the note struck again.
(def %sc-strike (fn (_ c) (first (Str8 split "/" c))))

; The cells of channel CELLS, a vector, with each note held over a
; multiple of PROWS struck again there.
(def %sc-restrike!
  (fn (_ cells prows)
    (def total (Vector length cells))
    ((fn (self r cur)
       (when (< r total)
         ((fn (_ c)
            (match ((Str8 starts? "-" c) (self (+ r 1) ()))
                   ((not (Str8 starts? "." c)) (self (+ r 1) (%sc-strike c)))
                   (#t (do (when (if (null? cur) #f (if (< 0 r) (= 0 (int% r prows)) #f))
                             (Vector set! r (Str8 append cur (Str8 sub 1 (- (Str8 length c) 1) c)) cells))
                           (self (+ r 1) cur)))))
          (Vector ref r cells))))
     0 ())))

; The song NAME of the score: HEAD the text of its first items, its
; tempo and such, INSTRUMENTS the text of each (instrument ...) form,
; COLUMNS its channels, (INSTRUMENT HELD CELLS) each, CELLS a vector of
; every row's cell and HELD whether its notes are struck again over a
; pattern's end, cut into patterns of PROWS rows.
(def score-song
  (fn (_ name head instruments columns prows)
    (def total (List fold (fn (_ n col) (if (< n (Vector length (List ref 2 col))) (Vector length (List ref 2 col)) n)) 1 columns))
    (List for-each (fn (_ col) (when (List ref 1 col) (%sc-restrike! (List ref 2 col) prows))) columns)
    (def slices
      (List map
        (fn (_ p)
          (def from (* p prows))
          (def to (%sc-min total (+ from prows)))
          (def chs (List map (fn (_ col) (pair (first col) (List map (fn (_ r) (if (< r (Vector length (List ref 2 col))) (Vector ref r (List ref 2 col)) "."))
                                                              (List range from to))))
                     columns))
          (def heard (List filter (fn (_ ch) (List any? (fn (_ c) (not (str=? c "."))) (rest ch))) chs))
          (if (null? heard) (list (first chs)) heard))
        (List range 0 (int/ (+ total (- prows 1)) prows))))
    (def keyed (List map (fn (_ chs) (pair (Str8 join "|" (List map (fn (_ ch) (Str8 join " " ch)) chs)) chs)) slices))
    (def patterns
      (List fold (fn (_ acc kc) (if (List any? (fn (_ p) (str=? (List ref 1 p) (first kc))) acc) acc
                                  (List append acc (list (list (Str8 append "p" (Str8 str (+ 1 (List length acc)))) (first kc) (rest kc))))))
        () keyed))
    (def order (List map (fn (_ kc) (first (List find (fn (_ p) (str=? (List ref 1 p) (first kc))) patterns))) keyed))
    (def skeleton
      (song-parse
        (Str8 append "(song \"x\" " head "\n"
          (Str8 join "" (List map (fn (_ i) (Str8 append "  " i "\n")) instruments))
          "  (pattern " (first (first patterns)) " (" (first (first columns)) " \".\"))\n"
          "  (order " (Str8 join " " order) "))")))
    (song-rename (List fold (fn (_ s p) (song-set-pattern s (first p) (List ref 2 p))) skeleton patterns) name)))

(provide tracker/score score-song)
