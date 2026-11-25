; # x-tracker -- a music tracker on x-lang
;
; ## tracker/draw.x -- the editor drawn on a screen
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; What the editor's state (tracker/state) looks like on an x/tui/screen
; screen: the title, the order, the page shown, and the line at the
; foot.  Drawing changes nothing but the rows and channels shown.

(module tracker/draw)

(import x/type/vector)
(import x/tui/screen)
(import x/core/doors int/ int% int+ int- int< int= str-byte-len str-byte-ref str-byte-sub)
(import tracker/song song-name song-order song-prop song-pattern pattern-rows song-instruments)
(import tracker/cell cell-columns)
(import tracker/edit %page-hints %song-settings %samples %envelope %instrument-form %picked-instrument %write-form %wave-name
  %picked-sample %sample-args %sound %sample-fields %field-value)
(import tracker/sample sample-peaks sample-setting sample-loop)
(import tracker/player player-edited)
(import tracker/file file-songs file-changed?)
(import tracker/player player-playing? player-mode player-loop player-tension player-pace player-volume
  player-hears? player-soloed?)
(import tracker/state %blanks %pad %doc %path %song %pattern %at %row %chan %top %left %octave %step %msg %input %undo %redo %player %quit %help %warned %heard %follow %pick %stale %borrowed %config %order-at %mark %clip %loop-at %browse %page %field %digit %mark-end %inst-at %env-at %env-held %setting-at %sample-at %sample-field %sample-undo %sample-cache %sample-peaks %slots %get %put! %max %min %same? %num edit-song edit-doc edit-quit? edit-message edit-message! edit-player edit-place %channels %rows %block %style %browse-hint )

; TEXT put on SCREEN, COLS wide, at ROW and COL; nothing when COL is
; past its right edge.  x/tui/screen's put keeps to the rows but not to
; the columns: one past the edge is written past the row's end, and past
; the last row's, into whatever the heap holds there.
(def %put-text!
  (fn (_ screen cols row col text style)
    (when (int< col cols) (Screen put screen row col text style))))

; A panel's lines to a column, in HIGH rows; its columns' width, of LINES.
(def %panel-high (fn (_ high) (%max 1 (- high 1))))
(def %panel-width (fn (_ lines) (+ 2 (List fold (fn (_ m l) (%max m (Str8 length l))) 0 (rest lines)))))

; Whether LINES as a panel of HIGH rows are wider than COLS.
(def %panel-cut?
  (fn (_ lines high cols)
    (< (* (%max 1 (int/ cols (%panel-width lines))) (%panel-high high)) (List length (rest lines)))))

; LINES put on SCREEN from row TOP, HIGH rows: the first a heading on a
; row of its own, the rest beneath it, a column of HIGH less one, the
; columns side by side as wide as the widest line, as many as the screen
; is wide for.  A line not starting with a blank is a heading, in bold;
; the line HI of the rest, when it is not nil, is highlighted.  More
; columns than fit start from the one HI is in, and the heading counts
; the lines left out to either side.
(def %draw-panel!
  (fn (_ st screen lines top high hi)
    (def h (%panel-high high))
    (def body (rest lines))
    (def n (List length body))
    (def cols (Screen cols screen))
    (def w (%panel-width lines))
    (def shown (%max 1 (int/ cols w)))
    (def first-col (if (null? hi) 0 (%max 0 (+ (- (int/ hi h) shown) 1))))
    (def from (* first-col h))
    (def to (%min n (* (+ first-col shown) h)))
    (def heading (%style st (lit heading)))
    (def cursor (%style st (lit cursor)))
    (def style (fn (_ l) (if (< 0 (Str8 length l)) (if (Str8 starts? " " l) 0 heading) 0)))
    (Screen put screen top 0
      (Str8 append (first lines)
        (if (< 0 from) (Str8 append "   (" (Str8 str from) " to the left)") "")
        (if (< to n) (Str8 append "   (" (Str8 str (- n to)) " to the right)") ""))
      (style (first lines)))
    (List fold
      (fn (_ i l)
        (when (if (<= from i) (< i to) #f)
          (%put-text! screen cols (+ (+ top 1) (int% i h)) (* w (- (int/ i h) first-col)) l (if (%same? i hi) cursor (style l))))
        (+ i 1))
      0 body)))

; The help's LINES put on SCREEN from row TOP, HIGH rows: the first a
; heading, the rest from the line ROW down, one column, the lines left
; above and below it counted on the heading.  ROW is kept to where the
; last line shows on the last row, as the help's place.
(def %draw-page!
  (fn (_ st screen lines at top high)
    (def h (%max 1 (- high 1)))
    (def row (%max 0 (%min at (- (- (List length lines) 1) h))))
    (%put! st %browse (pair (first (%get st %browse)) row))
    (def body (List drop row (rest lines)))
    (def cols (Screen cols screen))
    (def heading (%style st (lit heading)))
    (def below (%max 0 (- (List length body) h)))
    (%put-text! screen cols top 0
      (Str8 append (first lines)
        (if (< 0 row) (Str8 append "   (" (Str8 str row) " above)") "")
        (if (< 0 below) (Str8 append "   (" (Str8 str below) " below)") ""))
      heading)
    (List fold
      (fn (_ i l)
        (when (< i h) (%put-text! screen cols (+ (+ top 1) i) 0 l (if (if (< 0 (Str8 length l)) (not (Str8 starts? " " l)) #f) heading 0)))
        (+ i 1))
      0 body)))

; PARTS, each (RANK . TEXT), in WIDTH columns: while they are wider, the
; last of the highest RANK left out.  Rank 0 is never left out.
(def %fit-parts
  (fn (self parts width)
    (def worst (List fold (fn (_ m p) (%max m (first p))) 0 parts))
    (if (if (< 0 worst) (< width (List fold (fn (_ m p) (+ m (Str8 length (rest p)))) 0 parts)) #f)
      (self (List reverse ((fn (go l) (if (= worst (first (first l))) (rest l) (pair (first l) (go (rest l)))))
                           (List reverse parts)))
            width)
      parts)))

; The title bar, COLS wide: the file, the song, its settings, the
; editor's, and what plays.  On a narrow screen the least needed go
; first: rows and ticks, octave and step, bpm and the player's
; settings, the song's name; what plays and the file stay.
(def %title
  (fn (_ st cols)
    (def s (edit-song st))
    (def p (%get st %player))
    (Str8 join ""
      (List map rest
        (%fit-parts
          (list
            (pair 0 (Str8 append " x-tracker  " (if (null? (%get st %path)) "(no file)" (%get st %path))
                      (if (file-changed? (%get st %doc)) " [+]" "")))
            (pair 2 (Str8 append "   \"" (song-name s) "\""))
            (pair 3 (Str8 append "   bpm " (Str8 str (song-prop s "bpm" 90))))
            (pair 5 (Str8 append "  rows " (Str8 str (song-prop s "rows" 4))))
            (pair 5 (Str8 append "  ticks " (Str8 str (song-prop s "ticks" 6))))
            (pair 4 (Str8 append "   octave " (Str8 str (%get st %octave))))
            (pair 4 (Str8 append "  step " (Str8 str (%get st %step))))
            (pair 0 (match ((null? p) "   (no sound)")
                           ((not (player-playing? p)) "")
                           ((eq? (player-mode p) (lit song)) "   > song")
                           ((null? (player-loop p)) "   > pattern")
                           (#t (Str8 append "   > rows " (Str8 str (first (player-loop p))) "-" (Str8 str (rest (player-loop p)))))))
            (pair 3 (if (if (null? p) #t (= 0 (player-tension p))) "" (Str8 append "  tension " (Str8 str (player-tension p)))))
            (pair 3 (if (if (null? p) #t (= 100 (player-pace p))) "" (Str8 append "  pace " (Str8 str (player-pace p)) "%")))
            (pair 3 (if (if (null? p) #t (= 100 (player-volume p))) "" (Str8 append "  volume " (Str8 str (player-volume p)) "%"))))
          cols)))))

; The width of ITEMS joined by blanks.
(def %joined-length (fn (_ items) (List fold (fn (_ m s) (+ m (+ 1 (Str8 length s)))) -1 items)))

; ITEMS from S to E, E not included.
(def %slice (fn (_ items s e) (List take (- e s) (List drop s items))))

; ITEMS joined by blanks in WIDTH columns, item F among them: from the
; first item that leaves room for F, as many as fit after it.  "..."
; stands for the items left out at either end.
(def %window
  (fn (_ items f width)
    (def n (List length items))
    (def fits? (fn (_ s e) (<= (+ (+ (if (< 0 s) 4 0) (%joined-length (%slice items s e))) (if (< e n) 4 0)) width)))
    (def s ((fn (self s) (if (if (< s f) (not (fits? s (+ f 1))) #f) (self (+ s 1)) s)) 0))
    (def e ((fn (self e) (if (if (< e n) (fits? s (+ e 1)) #f) (self (+ e 1)) e)) (%min n (+ f 1))))
    (Str8 append (if (< 0 s) "... " "") (Str8 join " " (%slice items s e)) (if (< e n) " ..." ""))))

; The order, COLS wide: the place edited marked [NAME], the place picked
; while O edits it <NAME>, the place heard >NAME.  An order wider than
; the screen shows the part around the place picked, else the place
; heard while the song plays, else the place edited.
(def %order-line
  (fn (_ st cols)
    (def order (song-order (edit-song st)))
    (def heard (if (null? (%get st %heard)) () (first (%get st %heard))))
    (def playing-song (if (null? (%get st %player)) #f (if (player-playing? (%get st %player)) (eq? (player-mode (%get st %player)) (lit song)) #f)))
    (def tail (if (if (null? (%get st %at)) (not (null? (%get st %pattern))) #f)
                (Str8 append "   editing " (%get st %pattern) ", not in the order") ""))
    (def focus (match ((not (null? (%get st %order-at))) (%get st %order-at))
                      ((if playing-song (not (null? heard)) #f) heard)
                      ((not (null? (%get st %at))) (%get st %at))
                      (#t 0)))
    (Str8 append " order: "
      (if (null? order) "(none)"
        (%window
          (List map (fn (_ i)
                      (def name (List ref i order))
                      (def mark (if (if playing-song (%same? i heard) #f) (Str8 append ">" name) name))
                      (match ((%same? i (%get st %order-at)) (Str8 append "<" mark ">"))
                             ((if (null? (%get st %order-at)) (%same? i (%get st %at)) #f) (Str8 append "[" mark "]"))
                             (#t mark)))
            (List range 0 (List length order)))
          (%min focus (- (List length order) 1))
          (- (- cols 8) (Str8 length tail))))
      tail)))


; Channel I's heading, of instrument INST: in the empty cell's colour
; when it is not heard, the row playing's when it or its instrument is
; soloed.
(def %heading-style
  (fn (_ st i inst)
    (def p (%get st %player))
    (match ((null? p) (%style st (lit heading)))
           ((not (player-hears? p i inst)) (%style st (lit empty)))
           ((if (player-soloed? p (lit channel) i) #t (player-soloed? p (lit instrument) inst)) (%style st (lit playing)))
           (#t (%style st (lit heading))))))

; The row being heard, in the pattern edited, or nil.
(def %heard-row
  (fn (_ st)
    (def p (%get st %player))
    (def h (%get st %heard))
    (match ((null? h) ())
           ((null? p) ())
           ((eq? (player-mode p) (lit pattern)) (rest h))
           ((%same? (first h) (%get st %at)) (rest h))
           (#t ()))))

; A channel's columns on screen, Impulse Tracker's: the note, the
; instrument, the volume and the effect, a blank between, and a blank
; after the channel.
(def %effect-width 7)
(def %field-at (list 0 4 7 11))
(def %field-width (list 3 2 3 %effect-width))
(def %chan-width (+ 12 %effect-width))
(def %empty-cell (Str8 append "... .. ... " (Str8 sub 0 %effect-width ".........")))

; The row a channel of the empty cell is put in: its columns in their
; styles, the field FIELD (nil for none) in CURSOR, the whole in BLOCK
; when it is in the block.
(def %draw-cell!
  (fn (_ screen cols y x cols4 styles field cursor block)
    ((fn (self k)
       (when (int< k 4)
         (do (%put-text! screen cols y (int+ x (List ref k %field-at)) (List ref k cols4)
               (match ((%same? k field) cursor) ((null? block) (List ref k styles)) (#t block)))
             (self (int+ k 1)))))
     0)))

; The instruments' numbers, two digits from 01, by name.
(def %inst-numbers
  (fn (_ s)
    ((fn (_ names)
       (List map (fn (_ i) (pair (List ref i names) (Str8 pad-left 2 #\0 (Str8 str (+ i 1))))) (List range 0 (List length names))))
     (song-instruments s))))

(def %draw-grid!
  (fn (_ st screen top bottom)
    (def chs (%channels st))
    (def rows (%rows st))
    (def beat (%max 1 (song-prop (edit-song st) "rows" 4)))
    (def cols (Screen cols screen))
    (def fit (%max 1 (int/ (- cols 4) %chan-width)))
    (when (< (%get st %chan) (%get st %left)) (%put! st %left (%get st %chan)))
    (when (not (< (%get st %chan) (+ (%get st %left) fit))) (%put! st %left (+ (- (%get st %chan) fit) 1)))
    (def shown (- (- bottom top) 1))
    (when (< (%get st %row) (%get st %top)) (%put! st %top (%get st %row)))
    (when (not (< (%get st %row) (+ (%get st %top) shown))) (%put! st %top (+ (- (%get st %row) shown) 1)))
    (def left (%get st %left))
    (def shown-chs (List take (%min (List length chs) fit) (List drop left chs)))
    (def numbers (%inst-numbers (edit-song st)))
    (def insts (List map (fn (_ ch) ((fn (_ e) (if (null? e) "??" (rest e))) (List find (fn (_ e) (str=? (first e) (first ch))) numbers))) shown-chs))
    (def heard (%heard-row st))
    (def first-row (%get st %top))
    (def cur-row (%get st %row))
    (def cur-chan (int- (%get st %chan) left))
    (def field (%get st %field))
    (def empty (%style st (lit empty)))
    (def off (%style st (lit off)))
    (def styles (list 0 (%style st (lit instrument)) (%style st (lit volume)) (%style st (lit effect))))
    (def cursor (%style st (lit cursor)))
    (def playing (%style st (lit playing)))
    (def on-beat (%style st (lit beat)))
    (def marked (%style st (lit block)))
    ; The block marked, its rows and its channels as shown, or nil.
    (def blk (if (null? (%get st %mark)) () ((fn (_ b) (list (first b) (List ref 1 b) (int- (List ref 2 b) left) (int- (List ref 3 b) left))) (%block st))))
    (def in-blk? (fn (_ r k) (if (null? blk) #f (if (int< r (first blk)) #f (if (int< (List ref 1 blk) r) #f (if (int< k (List ref 2 blk)) #f (not (int< (List ref 3 blk) k))))))))
    ; The headings: the channel's number from 1 and its instrument.
    ((fn (self cs k)
       (unless (null? cs)
         (do (%put-text! screen cols top (int+ 4 (* %chan-width k))
               (%pad (int- %chan-width 1) (Str8 append " " (Str8 str (int+ (int+ left k) 1)) " " (first (first cs)) " " (List ref k insts)))
               (%heading-style st (int+ left k) (first (first cs))))
             (self (rest cs) (int+ k 1)))))
     shown-chs 0)
    ; Each channel's cells from the first row shown, walked a row at a
    ; time: a row's cells put, the lists of the rows after it answered.
    (def put-row!
      (fn (self y r cs k acc)
        (if (null? cs) acc
          ((fn (_ cells)
             (def cell (if (null? cells) "." (first cells)))
             (def x (int+ 4 (* %chan-width k)))
             (def at (if (int= r cur-row) (if (int= k cur-chan) field ()) ()))
             (def blocked (if (in-blk? r k) marked ()))
             (if (if (str=? cell ".") (if (null? at) (null? blocked) #f) #f)
               (%put-text! screen cols y x %empty-cell empty)
               ((fn (_ c4)
                  (%draw-cell! screen cols y x c4
                    (list (if (str=? (first c4) "...") empty (if (Str8 starts? "=" (first c4)) off (if (Str8 starts? "^" (first c4)) off 0)))
                          (if (str=? (List ref 1 c4) "..") empty (List ref 1 styles))
                          (if (str=? (List ref 2 c4) "...") empty (List ref 2 styles))
                          (if (Str8 starts? "." (List ref 3 c4)) empty (List ref 3 styles)))
                    at cursor blocked))
                (cell-columns cell (List ref k insts) %effect-width)))
             (self y r (rest cs) (int+ k 1) (pair (if (null? cells) () (rest cells)) acc)))
           (first cs)))))
    (def rev (fn (self xs acc) (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))
    ((fn (self y cs)
       (def r (int+ first-row y))
       (when (if (int< y shown) (int< r rows) #f)
         (do (%put-text! screen cols (int+ (int+ top 1) y) 0 (Str8 pad-left 3 #\space (Str8 str r))
               (if (%same? r heard) playing (if (int= 0 (int% r beat)) on-beat empty)))
             (when (%same? r heard) (%put-text! screen cols (int+ (int+ top 1) y) 3 ">" playing))
             (self (int+ y 1) (rev (put-row! (int+ (int+ top 1) y) r cs 0 ()) ())))))
     0 (List map (fn (_ ch) (List drop first-row (rest ch))) shown-chs))))

; --- the pages ------------------------------------------------------------------

; LINES put from row TOP to BOTTOM at column X, the line AT in CURSOR,
; scrolled so it shows; each line a string, or (TEXT . STYLE).
(def %draw-list!
  (fn (_ screen top bottom x lines at cursor)
    (def cols (Screen cols screen))
    (def high (%max 1 (- bottom top)))
    (def from (if (null? at) 0 (%max 0 (+ (- at high) 1))))
    (List fold
      (fn (_ i l)
        (when (if (<= from i) (< (- i from) high) #f)
          (%put-text! screen cols (+ top (- i from)) x (if (str? l) l (first l))
            (if (%same? i at) cursor (if (str? l) 0 (rest l)))))
        (+ i 1))
      0 lines)))

; F11: the order, a place a line: its number, its pattern and the
; pattern's rows; the place picked in the cursor's colour, the place
; heard marked >.
(def %draw-orders!
  (fn (_ st screen top bottom)
    (def s (edit-song st))
    (def order (song-order s))
    (def heard (if (null? (%get st %heard)) () (first (%get st %heard))))
    (def playing (if (null? (%get st %player)) #f (player-playing? (%get st %player))))
    (Screen put screen top 1 "Order list" (%style st (lit heading)))
    (if (null? order) (Screen put screen (+ top 2) 2 "No order yet: Insert puts the first pattern in it." 0)
      (%draw-list! screen (+ top 2) bottom 1
        (List map (fn (_ i)
                    (Str8 append (if (if playing (%same? i heard) #f) ">" " ") (Str8 pad-left 3 #\0 (Str8 str i)) "  "
                      (%pad 16 (List ref i order)) " " (Str8 str (pattern-rows (song-pattern s (List ref i order)))) " rows"))
          (List range 0 (List length order)))
        (%get st %order-at) (%style st (lit cursor))))))

; F12: the song's settings and the effects over its mix, one a line.
(def %draw-song-page!
  (fn (_ st screen top bottom)
    (Screen put screen top 1 "Song variables" (%style st (lit heading)))
    (%draw-list! screen (+ top 2) bottom 1
      (List map (fn (_ l) (Str8 append " " (%pad 30 (first l)) " " (List ref 1 l))) (%song-settings st))
      (%get st %setting-at) (%style st (lit cursor)))))

; Instrument FORM's envelope drawn in the box from row TOP and column X,
; HIGH rows and WIDE columns: the level over time, a point o, the one
; picked in the cursor's colour, # while it is picked up.
(def %draw-envelope!
  (fn (_ st screen top x high wide points at held)
    (def cols (Screen cols screen))
    (def last-ms (%max 100 (List fold (fn (_ m p) (%max m (first p))) 0 points)))
    (def w (%max 8 (- wide 6)))
    (def h (%max 3 (- high 2)))
    (def col-of (fn (_ ms) (int/ (* ms (- w 1)) last-ms)))
    (def row-of (fn (_ pct) (- (- h 1) (int/ (* (%max 0 (%min 100 pct)) (- h 1)) 100))))
    ; The level at column C: straight between the points about it.
    (def level-at
      (fn (_ c)
        (def ms (int/ (* c last-ms) (%max 1 (- w 1))))
        ((fn (self ps)
           (match ((null? ps) 0)
                  ((null? (rest ps)) (if (<= (first (first ps)) ms) (List ref 1 (first ps)) 0))
                  ((< ms (first (first ps))) (List ref 1 (first ps)))
                  ((<= ms (first (List ref 1 ps)))
                    ((fn (_ a b)
                       (if (= (first a) (first b)) (List ref 1 b)
                         (+ (List ref 1 a) (int/ (* (- (List ref 1 b) (List ref 1 a)) (- ms (first a))) (- (first b) (first a))))))
                     (first ps) (List ref 1 ps)))
                  (#t (self (rest ps)))))
         points)))
    (def dim (%style st (lit empty)))
    (%put-text! screen cols top x "100" dim)
    (%put-text! screen cols (+ top (- h 1)) x "  0" dim)
    (List for-each (fn (_ c) (%put-text! screen cols (+ top (row-of (level-at c))) (+ (+ x 4) c) "." (%style st (lit volume))))
      (List range 0 w))
    (List fold
      (fn (_ i p)
        (%put-text! screen cols (+ top (row-of (List ref 1 p))) (+ (+ x 4) (col-of (first p)))
          (if (if held (%same? i at) #f) "#" "o")
          (if (%same? i at) (%style st (lit cursor)) (%style st (lit heading))))
        (+ i 1))
      0 points)
    (%put-text! screen cols (+ top h) (+ x 4) (Str8 append "0 ms" (Str8 pad-left (%max 1 (- w 4)) #\space (Str8 append (Str8 str last-ms) " ms"))) dim)
    (unless (null? at)
      ((fn (_ p)
         (%put-text! screen cols (+ (+ top h) 1) (+ x 4)
           (Str8 append "point " (Str8 str (+ at 1)) " of " (Str8 str (List length points)) ": " (Str8 str (first p)) " ms, "
             (Str8 str (List ref 1 p)) "%" (if held "   picked up: arrows move it, Alt ten at a time, Enter drops it"
                                              "   left right pick   Enter pick up   Insert add   Delete drop   Tab the list"))
           0))
       (List ref (%min at (- (List length points) 1)) points)))))

; F4: the instruments, numbered as the pattern shows them; the one
; picked's props, and its envelope drawn.
(def %draw-instruments!
  (fn (_ st screen top bottom)
    (def names (song-instruments (edit-song st)))
    (def name (%picked-instrument st))
    (def env-at (%get st %env-at))
    (Screen put screen top 1 "Instrument list" (%style st (lit heading)))
    (%draw-list! screen (+ top 2) bottom 1
      (List map (fn (_ i) (Str8 append " " (Str8 pad-left 2 #\0 (Str8 str (+ i 1))) " " (%pad 18 (List ref i names)))) (List range 0 (List length names)))
      (if (null? names) () (%min (%get st %inst-at) (- (List length names) 1)))
      (if (null? env-at) (%style st (lit cursor)) (%style st (lit block))))
    (unless (null? name)
      (do (def form (%instrument-form st name))
          (def x 26)
          (def props (List map %write-form (rest (rest form))))
          (Screen put screen top x name (%style st (lit heading)))
          (List fold (fn (_ y p) (when (< y (- bottom 1)) (%put-text! screen (Screen cols screen) y (+ x 1) p 0)) (+ y 1)) (+ top 2) props)
          (def points (%envelope form))
          (def env-top (+ (+ top 3) (List length props)))
          (def high (%min 14 (- (- bottom env-top) 2)))
          (if (null? points) (%put-text! screen (Screen cols screen) env-top (+ x 1) "No envelope: Enter edits the instrument, (env (MS PCT) ...)." (%style st (lit empty)))
            (when (< 4 high)
              (do (Screen put screen env-top (+ x 1) "Volume envelope" (%style st (lit heading)))
                  (%draw-envelope! st screen (+ env-top 1) (+ x 1) high (- (Screen cols screen) (+ x 2)) points env-at (%get st %env-held)))))))))

; F3: the samples, the settings of the one picked beside them, and its
; sound drawn beneath, its loop between [ and ], its sustain loop
; between { and }.  A sample edited and not yet written is marked *.
(def %draw-samples!
  (fn (_ st screen top bottom)
    (def cols (Screen cols screen))
    (def ws (%samples st))
    (Screen put screen top 1 "Sample list" (%style st (lit heading)))
    (if (null? ws)
      (Screen put screen (+ top 2) 2 "No samples yet: Insert, or :sample NAME FILE.wav [ROOT] [START END], reads one." 0)
      (do (def w (%picked-sample st))
          (def args (%sample-args st w))
          (def d (%sound st w))
          (def edited (player-edited))
          (def high (List length %sample-fields))
          (%draw-list! screen (+ top 2) (+ (+ top 2) high) 1
            (List map (fn (_ x)
                        (Str8 append (if (List includes? (List ref 1 x) edited) "*" " ") (%pad 14 (%wave-name x)) " "
                          (%pad 24 (first (rest (List ref 2 x))))))
              ws)
            (%min (%get st %sample-at) (- (List length ws) 1))
            (if (null? (%get st %sample-field)) (%style st (lit cursor)) (%style st (lit heading))))
          (def x 44)
          (Screen put screen top x (Str8 append "Settings of " (%wave-name w)) (%style st (lit heading)))
          (List fold
            (fn (_ i f)
              (def v (%field-value args d (List ref 1 f)))
              (def text (match ((null? v) "off")
                               ((symbol? v) (symbol->str v))
                               ((eq? (List ref 1 f) (lit speed)) (Str8 append (Str8 str v) " Hz"))
                               (#t (Str8 str v))))
              (%put-text! screen cols (+ (+ top 2) i) x (%pad 16 (first f)) 0)
              (%put-text! screen cols (+ (+ top 2) i) (+ x 16) (%pad 10 text)
                (if (%same? i (%get st %sample-field)) (%style st (lit cursor)) (%style st (lit volume))))
              (+ i 1))
            0 %sample-fields)
          (def wtop (+ (+ top 3) high))
          (if (null? d)
            (%put-text! screen cols wtop 2 (Str8 append "The file " (first args) " cannot be read.") 0)
            (do (%put-text! screen cols wtop 1
                  (Str8 append "Sound   " (Str8 str (List ref 1 d)) " frames, "
                    (%seconds (List ref 1 d) (%field-value args d (lit speed))) " s at C-5   Alt-O writes it to " (first (rest (List ref 2 w))))
                  (%style st (lit empty)))
                (when (< 3 (- bottom (+ wtop 2)))
                  (%draw-sound! st screen (+ wtop 1) 1 (- (- bottom wtop) 2) (- cols 2) d
                    (%sample-loop-of-args args d) (sample-setting args (lit sustain))))))
          (when (if (not (null? (sample-setting args (lit sustain)))) #t
                  (not (null? (sample-setting args (lit vibrato)))))
            (%put-text! screen cols (- bottom 1) 1 "Sustain loops and vibrato are kept, and not heard: the mixer has neither." (%style st (lit empty))))))))

(def %sample-loop-of-args
  (fn (_ args d) (if (null? (sample-loop args)) (List ref 3 d) (sample-loop args))))

; FRAMES at RATE frames a second, in seconds to the hundredth.
(def %seconds
  (fn (_ frames rate)
    (def c (int/ (* frames 100) (%max 1 rate)))
    (Str8 append (Str8 str (int/ c 100)) "." (Str8 pad-left 2 #\0 (Str8 str (int% c 100))))))

; Sound D drawn on SCREEN from row TOP, HIGH rows of WIDE columns from X:
; each column the least to the most of its frames, the middle 0, and a
; row beneath with LOOP's [ ] and SUSTAIN's { }.
(def %draw-sound!
  (fn (_ st screen top x high wide d loop sustain)
    (def cols (Screen cols screen))
    (def h (- high 1))
    (def frames (List ref 1 d))
    (def cache (%get st %sample-peaks))
    (def peaks
      (if (if (pair? cache) (if (eq? (first cache) (List ref 2 d)) (= (List ref 1 cache) wide) #f) #f) (List ref 2 cache)
        ((fn (_ ps) (%put! st %sample-peaks (list (List ref 2 d) wide ps)) ps) (sample-peaks (List ref 2 d) frames wide))))
    (def row-of (fn (_ v) (%min (- h 1) (%max 0 (int/ (* (- 32767 v) (- h 1)) 65535)))))
    (def style (%style st (lit volume)))
    (List fold
      (fn (_ c pk)
        (def a (row-of (rest pk)))
        (def b (row-of (first pk)))
        (List for-each (fn (_ r) (%put-text! screen cols (+ top r) (+ x c) "|" style)) (List range a (+ b 1)))
        (+ c 1))
      0 peaks)
    (def col-of (fn (_ f) (%min (- wide 1) (int/ (* f wide) (%max 1 frames)))))
    (def marks (fn (_ pts open close)
                 (unless (null? pts)
                   (do (%put-text! screen cols (+ top h) (+ x (col-of (first pts))) open (%style st (lit heading)))
                       (%put-text! screen cols (+ top h) (+ x (col-of (- (List ref 1 pts) 1))) close (%style st (lit heading)))))))
    (marks loop "[" "]")
    (marks sustain "{" "}")))
(def edit-draw!
  (fn (_ st screen)
    (Screen clear screen)
    (def rows (Screen rows screen))
    (def cols (Screen cols screen))
    (Screen fill screen 0 0 cols (%style st (lit title)))
    (Screen put screen 0 0 (%title st cols) (%style st (lit title)))
    (Screen put screen 1 0 (%order-line st cols) 0)
    (match
      ((not (null? (%get st %browse))) (%draw-page! st screen (%get st %help) (rest (%get st %browse)) 2 (- rows 3)))
      ; A list with nothing picked in it, too wide for the screen, pages
      ; as the help does.
      ((if (%get st %help) (if (null? (%get st %pick)) (%panel-cut? (%get st %help) (- rows 3) cols) #f) #f)
        (do (%put! st %browse (pair () 0)) (edit-message! st %browse-hint)
            (%draw-page! st screen (%get st %help) 0 2 (- rows 3))))
      ((%get st %help) (%draw-panel! st screen (%get st %help) 2 (- rows 3) (%get st %pick)))
      ((eq? (%get st %page) (lit orders)) (%draw-orders! st screen 3 (- rows 2)))
      ((eq? (%get st %page) (lit song)) (%draw-song-page! st screen 3 (- rows 2)))
      ((eq? (%get st %page) (lit instruments)) (%draw-instruments! st screen 3 (- rows 2)))
      ((eq? (%get st %page) (lit samples)) (%draw-samples! st screen 3 (- rows 2)))
      ((null? (%get st %pattern)) (Screen put screen 3 1 "The song has no pattern: :pattern NAME makes one." 0))
      (#t (%draw-grid! st screen 3 (- rows 2))))
    (def input (%get st %input))
    (match
      ((null? input)
        ((fn (_ hint)
           (Screen put screen (- rows 1) 0
             (if (str=? (%get st %msg) "") (Str8 append " " (if (str=? hint "") "? help   Space play   p pattern   : command" hint)) (Str8 append " " (%get st %msg)))
             (if (str=? (%get st %msg) "") (%style st (lit empty)) 0)))
         (rest (List find (fn (_ h) (eq? (first h) (%get st %page))) %page-hints))))
      (#t ((fn (_ prompt)
             ; The cursor is at the end: a line too long for the screen
             ; shows its end, ... for the rest.
             (def text (rest input))
             (def room (- (- cols 1) (Str8 length prompt)))
             (def shown (if (< (Str8 length text) room) text
                          (Str8 append "..." (Str8 sub (- (Str8 length text) (%max 0 (- room 3))) (%max 0 (- room 3)) text))))
             (Screen put screen (- rows 1) 0 (Str8 append prompt shown) 0)
             (Screen cursor screen (- rows 1) (%min (- cols 1) (+ (Str8 length prompt) (Str8 length shown)))))
           (match ((eq? (first input) (lit command)) ":")
                  ((eq? (first input) (lit cell)) "cell: ")
                  ((eq? (first input) (lit effects)) "effects: ")
                  (#t "instrument: ")))))
    st))


(provide tracker/draw edit-draw!)
