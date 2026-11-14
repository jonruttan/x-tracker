; # x-tracker -- a music tracker on x-lang
;
; ## tracker/song.x -- a song as the editor holds it
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A song is the (song NAME ...) form x/audio/tracker plays, held as its
; name and its items in order: (song-form) makes the form again.  A
; pattern's channels and the order are held apart so the editor can
; change a cell or a row; any other item, an instrument, a tempo, an
; effect, is held as its text and its form, and written back as that
; text.
;
; A song is (NAME ITEMS), each item one of
;
;   (text INLINE TEXT FORM HEAD)    HEAD the form's first word, a string
;   (pattern INLINE NAME CHANNELS)  CHANNELS ((INSTRUMENT CELL ...) ...)
;   (order INLINE NAME ...)
;
; names, instruments and cells all strings; INLINE whether the item sat
; on the line before it, as (bpm 60) sits on its song's first line.
;
; Every change answers a new song: an old one is never changed, so the
; editor keeps old ones to undo to.

(module tracker/song)

(import x/codec/xon)
(import x/audio/mixer)
(import x/core/doors str->sym)
(import tracker/node node-read node-form? node-text node-parts node-head node-value)

(def %sg-fail (fn (_ what) (Err raise (lit value) (Str8 append "x-tracker: " what) ())))
(def %sg-write (prim-ref (lit io) (lit write-to-str)))
(def %sg-max (fn (_ a b) (if (< a b) b a)))




(def %sg-word
  (fn (_ n what)
    (unless (if (node-form? n) #f (not (eq? (first n) (lit str)))) (%sg-fail (Str8 append what " is a word")))
    (List ref 1 n)))

(def %sg-cells
  (fn (_ s) (List filter (fn (_ c) (not (str=? c ""))) (Str8 split " " s))))

; A pattern node as (NAME CHANNELS).
(def %sg-pattern
  (fn (_ n)
    (def parts (node-parts n))
    (when (null? (rest parts)) (%sg-fail "a pattern has no name"))
    (list (%sg-word (List ref 1 parts) "a pattern's name")
          (List map
            (fn (_ ch)
              (def cp (if (node-form? ch) (node-parts ch) ()))
              (unless (if (= (List length cp) 2) (eq? (first (List ref 1 cp)) (lit str)) #f)
                (%sg-fail "a pattern's channel is (INSTRUMENT \"CELLS\")"))
              (pair (%sg-word (first cp) "an instrument") (%sg-cells (node-value (List ref 1 cp)))))
            (rest (rest parts))))))

; Items from NODES, the song's children after its name; NL whether a
; line has ended since the last item.
(def %sg-items
  (fn (self nodes nl)
    (match
      ((null? nodes) ())
      ((eq? (first (first nodes)) (lit comment)) (self (rest nodes) #t))
      ((eq? (first (first nodes)) (lit space)) (self (rest nodes) (if nl #t (Str8 includes? "\n" (List ref 1 (first nodes))))))
      ((not (node-form? (first nodes))) (%sg-fail (Str8 append "a song holds forms, not " (List ref 1 (first nodes)))))
      (#t ((fn (_ n inline)
             (pair (match ((str=? (node-head n) "pattern") (pair (lit pattern) (pair inline (%sg-pattern n))))
                          ((str=? (node-head n) "order")
                            (List append (list (lit order) inline) (List map (fn (_ w) (%sg-word w "a pattern's name")) (rest (node-parts n)))))
                          (#t (list (lit text) inline (node-text n) (node-value n) (node-head n))))
                   (self (rest nodes) #f)))
           (first nodes) (not nl))))))

; A song from a (song NAME ...) node.  Raises a label 'value for one
; that is not.
(def song-from-node
  (fn (_ n)
    (def parts (node-parts n))
    (unless (if (str=? (node-head n) "song") (if (pair? (rest parts)) (eq? (first (List ref 1 parts)) (lit str)) #f) #f)
      (%sg-fail "a song is (song \"NAME\" ...)"))
    ; The children after the name: past the second part that is no blank.
    (def after
      ((fn (self ns k)
         (match ((null? ns) ())
                ((if (eq? (first (first ns)) (lit space)) #t (eq? (first (first ns)) (lit comment))) (self (rest ns) k))
                ((= k 1) (rest ns))
                (#t (self (rest ns) (+ k 1)))))
       (List ref 1 n) 0))
    (list (node-value (List ref 1 parts)) (%sg-items after #f))))

; The song in TEXT, one (song ...) form.
(def song-parse
  (fn (_ text)
    (def forms (List filter node-form? (node-read text)))
    (unless (= (List length forms) 1) (%sg-fail "not one song"))
    (song-from-node (first forms))))

; A new song NAME: one instrument, one pattern of sixteen rows.
(def song-new
  (fn (_ name)
    (song-parse
      (Str8 append "(song " (%sg-write name) " (bpm 120) (rows 4) (ticks 6)\n"
        "  (instrument lead (wave sine) (env (0 0) (5 70) (250 35)) (release 150) (gain 50))\n"
        "  (pattern a\n    (lead \". . . . . . . . . . . . . . . .\"))\n"
        "  (order a))"))))

(def song-name (fn (_ s) (first s)))
(def song-items (fn (_ s) (List ref 1 s)))
(def %sg-make (fn (_ name items) (list name items)))
(def song-rename (fn (_ s name) (%sg-make name (song-items s))))

(def %sg-of (fn (_ s kind) (List filter (fn (_ i) (eq? (first i) kind)) (song-items s))))

; The patterns, ((NAME . CHANNELS) ...), in the song's order of them.
(def song-patterns
  (fn (_ s) (List map (fn (_ i) (pair (List ref 2 i) (List ref 3 i))) (%sg-of s (lit pattern)))))

(def song-pattern
  (fn (_ s name) ((fn (_ e) (if (null? e) () (rest e))) (List find (fn (_ e) (str=? (first e) name)) (song-patterns s)))))

(def song-order
  (fn (_ s) ((fn (_ os) (if (null? os) () (rest (rest (first os))))) (%sg-of s (lit order)))))

; The text item whose head is HEAD and, given NAME, whose second word is it.
(def %sg-text-item
  (fn (_ s head name)
    (List find (fn (_ i) (if (str=? (List ref 4 i) head)
                           (if (null? name) #t (str=? (Str8 str (List ref 1 (List ref 3 i))) name))
                           #f))
      (%sg-of s (lit text)))))

; The number (KEY N) gives, or DEFAULT.
(def song-prop
  (fn (_ s key default)
    ((fn (_ i) (if (if (null? i) #t (null? (rest (List ref 3 i)))) default (List ref 1 (List ref 3 i))))
     (%sg-text-item s key ()))))

; The instruments' names, in order.
(def song-instruments
  (fn (_ s) (List map (fn (_ i) (Str8 str (List ref 1 (List ref 3 i)))) (List filter (fn (_ i) (str=? (List ref 4 i) "instrument")) (%sg-of s (lit text))))))

(def song-instrument-text
  (fn (_ s name) ((fn (_ i) (if (null? i) () (List ref 2 i))) (%sg-text-item s "instrument" name))))

; The names of the waves S's instruments name with (wave NAME), each
; once, in the order they are first named.
(def song-waves
  (fn (_ s)
    (def wave? (fn (_ prop) (if (pair? prop) (if (eq? (first prop) (lit wave)) (if (pair? (rest prop)) (symbol? (List ref 1 prop)) #f) #f) #f)))
    (List fold
      (fn (_ acc i)
        (List fold
          (fn (_ acc prop)
            (if (wave? prop)
              ((fn (_ n) (if (List includes? n acc) acc (List append acc (list n)))) (symbol->str (List ref 1 prop)))
              acc))
          acc (rest (rest (List ref 3 i)))))
      () (List filter (fn (_ i) (str=? (List ref 4 i) "instrument")) (%sg-of s (lit text))))))

; --- changes ---------------------------------------------------------------

; S with the item FIND finds put as ITEM, or ITEM put in after the last
; item AFTER answers true for, or else after the items on the song's
; first line.
(def %sg-put
  (fn (_ s find after item)
    (def items (song-items s))
    (def at (List find-index find items))
    (if (not (null? at))
      (%sg-make (song-name s) (List update at item items))
      ((fn (_ last)
         (def lead (List length (List take-while (fn (_ i) (List ref 1 i)) items)))
         (%sg-make (song-name s) (List insert (if (null? last) lead (+ last 1)) item items)))
       (List fold (fn (_ acc k) (if (after (List ref k items)) k acc)) () (List range 0 (List length items)))))))

; S with pattern NAME's channels CHANNELS, a new pattern after the others.
(def song-set-pattern
  (fn (_ s name channels)
    (%sg-put s (fn (_ i) (if (eq? (first i) (lit pattern)) (str=? (List ref 2 i) name) #f))
               (fn (_ i) (eq? (first i) (lit pattern)))
               (list (lit pattern) #f name channels))))

(def song-set-order
  (fn (_ s names)
    (%sg-put s (fn (_ i) (eq? (first i) (lit order)))
               (fn (_ i) (not (eq? (first i) (lit order))))
               (List append (list (lit order) #f) names))))

; S without pattern NAME, and NAME out of its order.
(def song-drop-pattern
  (fn (_ s name)
    (song-set-order
      (%sg-make (song-name s) (List filter (fn (_ i) (not (if (eq? (first i) (lit pattern)) (str=? (List ref 2 i) name) #f)))
                                (song-items s)))
      (List filter (fn (_ p) (not (str=? p name))) (song-order s)))))

; S with (KEY N): in its place, or on the song's first line.
(def song-set-prop
  (fn (_ s key n)
    (def text (Str8 append "(" key " " (Str8 str n) ")"))
    (%sg-put s (fn (_ i) (if (eq? (first i) (lit text)) (str=? (List ref 4 i) key) #f))
               (fn (_ i) #f)
               (list (lit text) #t text (first (Xon parse text)) key))))

; S with TEXT, an (instrument NAME ...) form, for the instrument of its
; name, a new one after the others.  Raises a label 'value for text that
; is not one such form.
(def song-set-instrument
  (fn (_ s text)
    (def forms (guard (e ()) (Xon parse text)))
    (unless (if (= (List length forms) 1)
              (if (pair? (first forms)) (if (eq? (first (first forms)) (lit instrument)) (symbol? (List ref 1 (first forms))) #f) #f)
              #f)
      (%sg-fail "an instrument is (instrument NAME PROP ...)"))
    (def name (symbol->str (List ref 1 (first forms))))
    (%sg-put s (fn (_ i) (if (eq? (first i) (lit text)) (if (str=? (List ref 4 i) "instrument") (str=? (Str8 str (List ref 1 (List ref 3 i))) name) #f) #f))
               (fn (_ i) (if (eq? (first i) (lit text)) (str=? (List ref 4 i) "instrument") #f))
               (list (lit text) #f text (first forms) "instrument"))))

; --- a pattern's channels --------------------------------------------------

(def pattern-rows
  (fn (_ chs) (List fold (fn (_ n ch) (%sg-max n (List length (rest ch)))) 0 chs)))

(def pattern-cell
  (fn (_ chs c r)
    (def cells (rest (List ref c chs)))
    (if (< r (List length cells)) (List ref r cells) ".")))

; CELLS made N long: cut, or held to the end.
(def %sg-fit
  (fn (_ cells n)
    (def k (List length cells))
    (if (< k n) (List append cells (List repeat (- n k) ".")) (List take n cells))))

(def pattern-set-cell
  (fn (_ chs c r text)
    (def rows (%sg-max (pattern-rows chs) (+ r 1)))
    (List update c ((fn (_ ch) (pair (first ch) (List update r text (%sg-fit (rest ch) rows)))) (List ref c chs)) chs)))

; Every channel made N rows long.
(def pattern-resize
  (fn (_ chs n) (List map (fn (_ ch) (pair (first ch) (%sg-fit (rest ch) n))) chs)))

; A row held at R in every channel, the rest moved down; the length kept.
(def pattern-insert-row
  (fn (_ chs r)
    (def n (pattern-rows chs))
    (List map (fn (_ ch) (pair (first ch) (List take n (List insert r "." (%sg-fit (rest ch) n))))) chs)))

; Row R taken out of every channel, the rest moved up, a held row at the end.
(def pattern-delete-row
  (fn (_ chs r)
    (def n (pattern-rows chs))
    (List map (fn (_ ch) (pair (first ch) (List append (List remove r 1 (%sg-fit (rest ch) n)) (list ".")))) chs)))

(def pattern-add-channel
  (fn (_ chs inst) (List append chs (list (pair inst (List repeat (%sg-max 1 (pattern-rows chs)) "."))))))

(def pattern-drop-channel (fn (_ chs c) (List remove c 1 chs)))

; --- the form and the text -------------------------------------------------

(def %sg-pattern-form
  (fn (_ name chs)
    (List append (list (lit pattern) (str->sym name))
      (List map (fn (_ ch) (list (str->sym (first ch)) (Str8 join " " (rest ch)))) chs))))

; The (song NAME ...) form x/audio/tracker plays, its order ORDER when
; given, the song's own when nil.
(def song-form
  (fn (_ s order)
    (List append (list (lit song) (song-name s))
      (List map
        (fn (_ i)
          (match ((eq? (first i) (lit text)) (List ref 3 i))
                 ((eq? (first i) (lit pattern)) (%sg-pattern-form (List ref 2 i) (List ref 3 i)))
                 (#t (pair (lit order) (List map str->sym (if (null? order) (rest (rest i)) order))))))
        (song-items s)))))

; CELLS as a pattern's string, each cell but the last padded to the
; widest plain cell of the pattern, W.
(def %sg-cells-text
  (fn (_ cells w)
    ((fn (self cs acc)
       (if (null? (rest cs)) (Str8 join "" (List reverse (pair (first cs) acc)))
         (self (rest cs) (pair (Str8 append (Str8 pad-right w #\space (first cs)) " ") acc))))
     cells ())))

(def %sg-pattern-text
  (fn (_ name chs)
    (def plain (List filter (fn (_ c) (not (Str8 includes? "/" c))) (List flat-map rest chs)))
    (def w (List fold (fn (_ n c) (%sg-max n (Str8 length c))) 2 plain))
    (def iw (List fold (fn (_ n ch) (%sg-max n (Str8 length (first ch)))) 0 chs))
    (Str8 append "(pattern " name
      (Str8 join ""
        (List map (fn (_ ch) (Str8 append "\n    (" (Str8 pad-right iw #\space (first ch)) " "
                                (%sg-write (if (null? (rest ch)) "." (%sg-cells-text (rest ch) w))) ")"))
          chs))
      ")")))

; The song as .xon text, one (song ...) form.  An item stays on the line
; before it as it was read, but a pattern, a row a line, and what follows
; one start lines of their own.
(def song-text
  (fn (_ s)
    (def items (song-items s))
    (Str8 append "(song " (%sg-write (song-name s))
      (Str8 join ""
        (List map
          (fn (_ k)
            (def i (List ref k items))
            (def after-pattern (if (< 0 k) (eq? (first (List ref (- k 1) items)) (lit pattern)) #f))
            (Str8 append (if (if (List ref 1 i) (not (if after-pattern #t (eq? (first i) (lit pattern)))) #f) " " "\n  ")
              (match ((eq? (first i) (lit text)) (List ref 2 i))
                     ((eq? (first i) (lit pattern)) (%sg-pattern-text (List ref 2 i) (List ref 3 i)))
                     (#t (Str8 append "(order " (Str8 join " " (rest (rest i))) ")")))))
          (List range 0 (List length items))))
      ")")))

; Why TEXT is no cell, or nil when it is one: a note's name (NOTE or
; NOTE:PCT), "." or "-", each followed by any "/EFFECT".
(def song-cell-problem
  (fn (_ text)
    (def parts (Str8 split "/" text))
    (def head (first (Str8 split ":" (first parts))))
    (match ((str=? text "") "an empty cell")
           ((Str8 includes? " " text) "a cell has no spaces")
           ((if (str=? (first parts) ".") #t (str=? (first parts) "-")) ())
           ((null? (guard (e ()) (Mixer semitone head))) (Str8 append "no note " head))
           (#t ()))))

(provide tracker/song song-from-node song-parse song-new song-name song-items song-rename song-patterns song-pattern
  song-order song-prop song-instruments song-instrument-text song-waves song-set-pattern song-drop-pattern song-set-order
  song-set-prop song-set-instrument pattern-rows pattern-cell pattern-set-cell pattern-resize pattern-insert-row
  pattern-delete-row pattern-add-channel pattern-drop-channel song-form song-text song-cell-problem)
