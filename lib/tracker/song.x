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
(import x/sys/gc)
(import x/core/doors str->sym int/ int%)
(import tracker/node node-read node-form? node-text node-parts node-head node-value)
(import tracker/cell cell-parts cell-join cell-note?)

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

; --- effects, instruments and patterns by name ------------------------------

(def %sg-effect-heads (list "echo" "reverb" "phase" "chorus" "drive" "crush" "sweep" "limit"))
(def %sg-effect? (fn (_ i) (if (eq? (first i) (lit text)) (List includes? (List ref 4 i) %sg-effect-heads) #f)))

; The text of each of S's effects over the whole mix, in order.
(def song-effects
  (fn (_ s) (List map (fn (_ i) (List ref 2 i)) (List filter %sg-effect? (song-items s)))))

; The index among ITEMS of the Kth item PRED answers true for, or nil.
(def %sg-nth
  (fn (_ items pred k)
    ((fn (self i n)
       (match ((= i (List length items)) ())
              ((not (pred (List ref i items))) (self (+ i 1) n))
              ((= n k) i)
              (#t (self (+ i 1) (+ n 1)))))
     0 0)))

; S with TEXT, an effect's form, as its Kth effect from 0, in place of
; the one there; after its last when there is no Kth.  Raises a label
; 'value for text that is no effect.
(def song-set-effect
  (fn (_ s k text)
    (def forms (guard (e ()) (Xon parse text)))
    (unless (if (= (List length forms) 1)
              (if (pair? (first forms)) (if (symbol? (first (first forms))) (List includes? (symbol->str (first (first forms))) %sg-effect-heads) #f) #f)
              #f)
      (%sg-fail (Str8 append "an effect is (NAME N ...), NAME one of " (Str8 join " " %sg-effect-heads))))
    (def item (list (lit text) #f text (first forms) (symbol->str (first (first forms)))))
    (def at (%sg-nth (song-items s) %sg-effect? k))
    (if (null? at) (%sg-put s (fn (_ i) #f) %sg-effect? item)
      (%sg-make (song-name s) (List update at item (song-items s))))))

; S without its Kth effect.
(def song-drop-effect
  (fn (_ s k)
    (def at (%sg-nth (song-items s) %sg-effect? k))
    (if (null? at) s (%sg-make (song-name s) (List remove at 1 (song-items s))))))

(def %sg-instrument-item?
  (fn (_ i name) (if (eq? (first i) (lit text)) (if (str=? (List ref 4 i) "instrument") (str=? (Str8 str (List ref 1 (List ref 3 i))) name) #f) #f)))

; An instrument's TEXT with its name OLD made NEW.
(def %sg-renamed-text
  (fn (_ text old new)
    (def at (Str8 index-of old text))
    (Str8 append (Str8 sub 0 at text) new (Str8 sub (+ at (Str8 length old)) (- (Str8 length text) (+ at (Str8 length old))) text))))

; S with a copy of instrument OLD named NEW, after the others.
(def song-copy-instrument
  (fn (_ s old new)
    (song-set-instrument s (%sg-renamed-text (song-instrument-text s old) old new))))

; S with instrument OLD named NEW, in its form and in every channel.
(def song-rename-instrument
  (fn (_ s old new)
    (%sg-make (song-name s)
      (List map
        (fn (_ i)
          (match ((%sg-instrument-item? i old)
                   ((fn (_ text) (list (lit text) (List ref 1 i) text (first (Xon parse text)) "instrument"))
                    (%sg-renamed-text (List ref 2 i) old new)))
                 ((eq? (first i) (lit pattern))
                   (list (lit pattern) (List ref 1 i) (List ref 2 i)
                     (List map (fn (_ ch) (if (str=? (first ch) old) (pair new (rest ch)) ch)) (List ref 3 i))))
                 (#t i)))
        (song-items s)))))

; S without instrument NAME.
(def song-drop-instrument
  (fn (_ s name)
    (%sg-make (song-name s) (List filter (fn (_ i) (not (%sg-instrument-item? i name))) (song-items s)))))

; The patterns of S with a channel of instrument NAME.
(def song-instrument-uses
  (fn (_ s name)
    (List map first (List filter (fn (_ p) (List any? (fn (_ ch) (str=? (first ch) name)) (rest p))) (song-patterns s)))))

; S with pattern OLD named NEW, in the order too.
(def song-rename-pattern
  (fn (_ s old new)
    (song-set-order
      (%sg-make (song-name s)
        (List map (fn (_ i) (if (if (eq? (first i) (lit pattern)) (str=? (List ref 2 i) old) #f)
                              (list (lit pattern) (List ref 1 i) new (List ref 3 i)) i))
          (song-items s)))
      (List map (fn (_ p) (if (str=? p old) new p)) (song-order s)))))

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

; Channel C played by instrument INST.
(def pattern-set-instrument
  (fn (_ chs c inst) (List update c (pair inst (rest (List ref c chs))) chs)))

; Channel C moved to C + D, the one there moved to C; as it was when
; C + D is outside the pattern.
(def pattern-move-channel
  (fn (_ chs c d)
    (def to (+ c d))
    (if (if (< to 0) #t (not (< to (List length chs)))) chs
      (List update to (List ref c chs) (List update c (List ref to chs) chs)))))

; The cells of channels C0 to C1 and rows R0 to R1, both ends in: a list
; of columns, each a list of cells.
(def pattern-block
  (fn (_ chs c0 c1 r0 r1)
    (List map (fn (_ c) (List map (fn (_ r) (pattern-cell chs c r)) (List range r0 (+ r1 1)))) (List range c0 (+ c1 1)))))

; BLOCK, a list of columns, put in from channel C and row R; what falls
; outside the pattern is left out.
(def pattern-paste
  (fn (_ chs c r block)
    (def rows (pattern-rows chs))
    (List fold
      (fn (_ acc k)
        (def col (List ref k block))
        (if (< (+ c k) (List length acc))
          (List fold (fn (_ a j) (if (< (+ r j) rows) (pattern-set-cell a (+ c k) (+ r j) (List ref j col)) a))
            acc (List range 0 (List length col)))
          acc))
      chs (List range 0 (List length block)))))

; Channels C0 to C1 and rows R0 to R1 with F applied to each cell.
(def pattern-map-block
  (fn (_ chs c0 c1 r0 r1 f)
    (pattern-paste chs c0 r0 (List map (fn (_ col) (List map f col)) (pattern-block chs c0 c1 r0 r1)))))

(def %sg-note-names (list "C" "C#" "D" "D#" "E" "F" "F#" "G" "G#" "A" "A#" "B"))

; A note's name from its semitones above C0.
(def song-note-name
  (fn (_ semi) (Str8 append (List ref (int% semi 12) %sg-note-names) (Str8 str (int/ semi 12)))))

; CELL with its note moved N semitones, its gain and effects kept; a
; held or let-go cell, or one the move would take below C0 or above B9,
; as it was.
(def cell-transpose
  (fn (_ cell n)
    (def slash (Str8 index-of "/" cell))
    (def head (if (null? slash) cell (Str8 sub 0 slash cell)))
    (def tail (if (null? slash) "" (Str8 sub slash (- (Str8 length cell) slash) cell)))
    (def colon (Str8 index-of ":" head))
    (def note (if (null? colon) head (Str8 sub 0 colon head)))
    (def gain (if (null? colon) "" (Str8 sub colon (- (Str8 length head) colon) head)))
    (def semi (if (List includes? note (list "." "-")) () (guard (e ()) (Mixer semitone note))))
    (if (if (null? semi) #t (if (< (+ semi n) 0) #t (< 119 (+ semi n)))) cell
      (Str8 append (song-note-name (+ semi n)) gain tail))))

; CELL at PCT percent: a note's gain set, held and let-go cells as they were.
(def cell-gain
  (fn (_ cell pct)
    (def slash (Str8 index-of "/" cell))
    (def head (if (null? slash) cell (Str8 sub 0 slash cell)))
    (def tail (if (null? slash) "" (Str8 sub slash (- (Str8 length cell) slash) cell)))
    (def note (first (Str8 split ":" head)))
    (if (List includes? note (list "." "-")) cell
      (Str8 append note (if (= pct 100) "" (Str8 append ":" (Str8 str pct))) tail))))

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
; one start lines of their own.  A long song is many patterns, so the
; heap is collected before each.
(def song-text
  (fn (_ s)
    (def items (song-items s))
    (Str8 append "(song " (%sg-write (song-name s))
      (Str8 join ""
        (List map
          (fn (_ k)
            (def i (List ref k items))
            (when (eq? (first i) (lit pattern)) (Heap collect))
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


; N held rows put in at R in channels C0 to C1, the rows below moved
; down; the pattern's length kept.
(def pattern-insert-rows
  (fn (_ chs c0 c1 r n)
    (def rows (pattern-rows chs))
    (List map (fn (_ k)
                ((fn (_ ch)
                   (if (if (< k c0) #t (< c1 k)) ch
                     ((fn (_ cells) (pair (first ch) (List take rows (List append (List take r cells) (List repeat n ".") (List drop r cells)))))
                      (%sg-fit (rest ch) rows))))
                 (List ref k chs)))
      (List range 0 (List length chs)))))

; Row R taken out of channel C alone, the rows below moved up, a held row
; at its end.
(def pattern-delete-rows
  (fn (_ chs c0 c1 r n)
    (def rows (pattern-rows chs))
    (List map (fn (_ k)
                ((fn (_ ch)
                   (if (if (< k c0) #t (< c1 k)) ch
                     ((fn (_ cells) (pair (first ch) (List append (List take r cells) (List drop (+ r n) cells) (List repeat (%sg-max 0 (- rows (List length (List drop (+ r n) cells)) r)) "."))))
                      (%sg-fit (rest ch) rows))))
                 (List ref k chs)))
      (List range 0 (List length chs)))))


; A to B at I of N steps, rounded to the nearest.
(def %sg-between
  (fn (_ a b i n) (+ a (int/ (+ (* 2 (* (- b a) i)) (if (< b a) (- 0 n) n)) (* 2 n)))))

; An effect's letter and its numbers: "v20,6" as ("v" 20 6), nil for one
; whose numbers do not read.
(def %sg-effect-numbers
  (fn (_ e)
    (def ns (List map (fn (_ w) (guard (x ()) ((prim-ref (lit convert) (lit to)) w (Type named INTEGER) 10)))
              (Str8 split "," (Str8 sub 1 (- (Str8 length e) 1) e))))
    (if (List any? null? ns) () (pair (Str8 sub 0 1 e) ns))))

; Channel C from row R0 to R1 slid from its first row's to its last's:
; WHAT gain, the notes' gains; else effect, the cells' first effects,
; which must be of one letter at both ends.  Raises a label 'value with
; what is wrong otherwise.
(def pattern-slide
  (fn (_ chs c r0 r1 what)
    (def a (cell-parts (pattern-cell chs c r0)))
    (def b (cell-parts (pattern-cell chs c r1)))
    (def n (- r1 r0))
    (def put (fn (_ chs f) (List fold (fn (_ acc r) (pattern-set-cell acc c r (f r (cell-parts (pattern-cell acc c r))))) chs (List range r0 (+ r1 1)))))
    (if (eq? what (lit gain))
      (do (unless (if (cell-note? (first a)) (cell-note? (first b)) #f) (%sg-fail "a volume slide runs from a note to a note"))
          (def ga (if (null? (List ref 1 a)) 100 (List ref 1 a)))
          (def gb (if (null? (List ref 1 b)) 100 (List ref 1 b)))
          (put chs (fn (_ r p) (if (cell-note? (first p)) (cell-join (first p) (%sg-between ga gb (- r r0) n) (List ref 2 p))
                                  (cell-join (first p) (List ref 1 p) (List ref 2 p))))))
      (do (def ea (if (null? (List ref 2 a)) () (%sg-effect-numbers (first (List ref 2 a)))))
          (def eb (if (null? (List ref 2 b)) () (%sg-effect-numbers (first (List ref 2 b)))))
          (unless (if (null? ea) #f (if (null? eb) #f (if (str=? (first ea) (first eb)) (= (List length ea) (List length eb)) #f)))
            (%sg-fail "an effect slide runs from an effect to one of its letter and as many numbers"))
          (put chs (fn (_ r p)
                     (def e (Str8 append (first ea)
                              (Str8 join "," (List map (fn (_ k) (Str8 str (%sg-between (List ref k (rest ea)) (List ref k (rest eb)) (- r r0) n)))
                                               (List range 0 (List length (rest ea)))))))
                     (def others (List ref 2 p))
                     (cell-join (first p) (List ref 1 p)
                       (if (if (pair? others) (Str8 starts? (first ea) (first others)) #f) (pair e (rest others)) (pair e others)))))))))

; Channel C's rows R0 to R1 made twice as long, a hold after each, or
; half as long, every other row, from R0: what falls past the pattern's
; end is left out, and rows freed are held.
(def pattern-stretch
  (fn (_ chs c r0 r1 twice)
    (def rows (pattern-rows chs))
    (def cells (%sg-fit (rest (List ref c chs)) rows))
    (def block (List take (+ 1 (- r1 r0)) (List drop r0 cells)))
    (def made (if twice (List flat-map (fn (_ x) (list x ".")) block)
                (List map (fn (_ i) (List ref (* 2 i) block)) (List range 0 (int/ (+ 1 (List length block)) 2)))))
    (def after (if twice (List drop (+ r0 (List length made)) cells)
                 (List append (List repeat (- (List length block) (List length made)) ".") (List drop (+ r1 1) cells))))
    (List update c (pair (first (List ref c chs)) (List take rows (List append (List take r0 cells) made after))) chs)))
(provide tracker/song song-from-node song-parse song-new song-name song-items song-rename song-patterns song-pattern
  song-order song-prop song-instruments song-instrument-text song-waves song-set-pattern song-drop-pattern song-set-order
  song-set-prop song-set-instrument pattern-rows pattern-cell pattern-set-cell pattern-resize pattern-insert-row
  pattern-delete-row pattern-add-channel pattern-drop-channel song-form song-text song-cell-problem
  song-effects song-set-effect song-drop-effect song-copy-instrument song-rename-instrument song-drop-instrument
  song-instrument-uses song-rename-pattern pattern-set-instrument pattern-move-channel pattern-block pattern-paste
  pattern-map-block song-note-name cell-transpose cell-gain pattern-insert-rows pattern-delete-rows pattern-slide
  pattern-stretch)
