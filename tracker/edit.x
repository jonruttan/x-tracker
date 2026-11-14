; # x-tracker -- a music tracker on x-lang
;
; ## tracker/edit.x -- the editor: its state, keys and drawing
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; What the terminal shows and what a key does to it, kept apart from the
; terminal itself (tracker/app) so a spec can press keys and read the
; screen back.  A pattern fills the screen: a row a line, a channel a
; column headed by its instrument.  Above it the song's tempo, the octave
; notes are typed in and the order, the pattern edited marked in it.
;
; Notes are typed on the letters as on two rows of a piano's keys: z s x
; d c v g b h n j m the octave's C to B, q 2 w 3 e r 5 t 6 y 7 u the octave
; above, then i; . holds and - lets go.  Enter edits a cell's text, its
; effects and its gain among it (x/audio/tracker's notes say how); E an
; instrument's form.  : takes a command, as vi does: :w, :q, :bpm 90,
; :pattern NAME, :order a b a ...  ? lists the keys and the commands.
;
; The state is a Vector; the slots are named below.  The document is never
; changed in place (tracker/file, tracker/song): a change makes a new one,
; and the old is kept to undo to.

(module tracker/edit)

(import x/type/vector)
(import x/tui/screen)
(import x/tui/style)
(import x/core/doors int/ int% int+ int- int< int= str-byte-len str-byte-ref str-byte-sub)
(import tracker/song song-new song-name song-rename song-patterns song-pattern song-order song-prop
  song-instruments song-instrument-text song-waves song-set-pattern song-set-order song-set-prop song-set-instrument
  pattern-rows pattern-cell pattern-set-cell pattern-resize pattern-insert-row pattern-delete-row
  pattern-add-channel pattern-drop-channel song-cell-problem song-effects song-set-effect song-drop-effect
  song-copy-instrument song-rename-instrument song-drop-instrument song-instrument-uses song-rename-pattern
  song-drop-pattern pattern-set-instrument pattern-move-channel pattern-block pattern-paste pattern-map-block
  cell-transpose cell-gain)
(import tracker/file file-songs file-song! file-add-song file-drop-song file-changed? file-write! file-waves file-wave file-set-wave)
(import tracker/player player-playing? player-mode player-start! player-stop! player-update! player-preview!
  player-pump! player-place player-tension! player-pace! player-waves player-waves! player-wave?)

(def %doc 0)
(def %path 1)
(def %song 2)       ; which song of the document, from 0
(def %pattern 3)    ; the name of the pattern edited, or nil when the song has none
(def %at 4)         ; the place in the order the pattern was reached from, or nil
(def %row 5)
(def %chan 6)
(def %top 7)        ; the first row shown
(def %left 8)       ; the first channel shown
(def %octave 9)
(def %step 10)      ; rows the cursor moves after a note is typed
(def %msg 11)
(def %input 12)     ; (KIND . TEXT) while a line is typed: command, cell or instrument
(def %undo 13)      ; ((DOC SONG PATTERN) ...), the latest first
(def %redo 14)
(def %player 15)    ; the player (tracker/player), or nil when there is no sound
(def %quit 16)
(def %help 17)      ; the lines shown over the grid, ? or :song, or #f
(def %warned 18)    ; whether :q was refused once for a change not written
(def %heard 19)     ; the place last drawn as heard, (AT . ROW), or nil
(def %follow 20)    ; whether the pattern and row heard are followed while playing
(def %pick 21)      ; the song highlighted while :song lists them, or nil
(def %stale 22)     ; whether the song heard is behind the song edited
(def %borrowed 23)  ; the (wave ...) forms the player was given from other files (-w)
(def %order-at 24)  ; the place picked in the order while O edits it, or nil
(def %mark 25)      ; (ROW . CHANNEL) where the block marked with V starts, or nil
(def %clip 26)      ; the cells copied, a list of columns, or nil
(def %slots 27)

(def %get (fn (_ st i) (Vector ref i st)))
(def %put! (fn (_ st i x) (Vector set! i x st)))
(def %max (fn (_ a b) (if (< a b) b a)))
(def %min (fn (_ a b) (if (< a b) a b)))
(def %same? (fn (_ a b) (if (null? b) #f (= a b))))
(def %num (fn (_ s) (guard (e ()) ((prim-ref (lit convert) (lit to)) s (Type named INTEGER) 10))))

; --- the state ---------------------------------------------------------------

(def edit-song (fn (_ st) (List ref (%get st %song) (file-songs (%get st %doc)))))
(def edit-doc (fn (_ st) (%get st %doc)))
(def edit-quit? (fn (_ st) (%get st %quit)))
(def edit-message (fn (_ st) (%get st %msg)))
(def edit-message! (fn (_ st text) (%put! st %msg text)))
(def edit-player (fn (_ st) (%get st %player)))
(def edit-place (fn (_ st) (list (%get st %pattern) (%get st %row) (%get st %chan))))

(def %channels
  (fn (_ st)
    (if (null? (%get st %pattern)) () (song-pattern (edit-song st) (%get st %pattern)))))

(def %rows (fn (_ st) (%max 1 (pattern-rows (%channels st)))))

; The pattern to edit in song S: the first of its order, or its first
; pattern, or nil; and the place in the order it is at.
(def %first-pattern
  (fn (_ s)
    (match ((not (null? (song-order s))) (pair (first (song-order s)) 0))
           ((not (null? (song-patterns s))) (pair (first (first (song-patterns s))) ()))
           (#t (pair () ())))))

; The cursor kept inside the pattern, and the rows and channels shown
; about it.
(def %clamp!
  (fn (_ st)
    (when (if (null? (%get st %pattern)) #f (null? (%channels st)))
      (do (def fp (%first-pattern (edit-song st))) (%put! st %pattern (first fp)) (%put! st %at (rest fp))))
    (%put! st %row (%max 0 (%min (%get st %row) (- (%rows st) 1))))
    (%put! st %chan (%max 0 (%min (%get st %chan) (- (List length (%channels st)) 1))))
    st))

; The Ith song edited, from its start: the song playing stopped, and the
; place heard and any change it was still to be told of forgotten.  The
; octave, the step and following are the editor's, not the song's.
(def %go-song!
  (fn (_ st i)
    (def p (%get st %player))
    (unless (null? p) (when (player-playing? p) (player-stop! p)))
    (%put! st %heard ())
    (%put! st %stale #f)
    (%put! st %input ())
    (%put! st %song i)
    (def fp (%first-pattern (edit-song st)))
    (%put! st %pattern (first fp))
    (%put! st %at (rest fp))
    (%put! st %row 0) (%put! st %chan 0) (%put! st %top 0) (%put! st %left 0)
    (%put! st %mark ()) (%put! st %order-at ())
    st))

; An editor of DOC, read from PATH, heard through PLAYER (nil for none).
; A document with no song is given one.
(def edit-make
  (fn (_ doc path player)
    (def st (Vector make %slots ()))
    (%put! st %doc (if (null? (file-songs doc)) (file-add-song doc (song-new "untitled")) doc))
    (%put! st %path path)
    (%put! st %octave 4)
    (%put! st %step 1)
    (%put! st %msg "")
    (%put! st %player player)
    (%put! st %quit #f)
    (%put! st %help #f)
    (%put! st %warned #f)
    (%put! st %follow #t)
    (%put! st %stale #f)
    (%put! st %borrowed
      (if (null? player) ()
        (List filter (fn (_ w) (null? (file-wave doc (symbol->str (List ref 1 w))))) (player-waves player))))
    (%go-song! st 0)))

; --- changes -----------------------------------------------------------------

; A change is heard from the next pattern, so the song playing is told
; of it later (edit-settle!), once for any number of keys: telling it
; reads the whole song into the tracker again.
(def %heard-change! (fn (_ st) (%put! st %stale #t)))

; The song playing told of the changes since it was last told: what the
; caller does when no key is waiting.
(def edit-settle!
  (fn (_ st)
    (def p (%get st %player))
    (when (%get st %stale)
      (do (%put! st %stale #f)
          (unless (if (null? p) #t (not (player-playing? p)))
            ((fn (_ e) (unless (null? e) (edit-message! st e)))
             (guard (e (if (Err err? e) (e msg) "the song cannot be played"))
               (do (player-update! p (edit-song st) (%get st %pattern)) ()))))))))

; Where the editor is, to undo to: (DOC SONG PATTERN).
(def %here (fn (_ st) (list (%get st %doc) (%get st %song) (%get st %pattern))))

; The mixer given the document's waves, and the borrowed ones it does
; not have, as they were: after a change or an undo of one.
(def %sync-waves!
  (fn (_ st)
    (def doc (%get st %doc))
    (unless (null? (%get st %player))
      (player-waves! (%get st %player)
        (List append (List filter (fn (_ w) (null? (file-wave doc (symbol->str (List ref 1 w))))) (%get st %borrowed))
          (file-waves doc))))))

; The document made DOC: the old one kept to undo to.
(def %doc-change!
  (fn (_ st doc)
    (%put! st %undo (pair (%here st) (List take 200 (%get st %undo))))
    (%put! st %redo ())
    (%put! st %doc doc)
    (%put! st %warned #f)
    (%sync-waves! st)
    (%heard-change! st)
    (%clamp! st)))

; The song made S.
(def %change!
  (fn (_ st s) (%doc-change! st (file-song! (%get st %doc) (%get st %song) s))))

(def %set-channels!
  (fn (_ st chs) (%change! st (song-set-pattern (edit-song st) (%get st %pattern) chs))))

; One step of undo, FROM the list taken from and TO the list given to:
; back in the song the step was made in.
(def %undo-step!
  (fn (_ st from to what)
    (if (null? (%get st from)) (edit-message! st (Str8 append "Nothing to " what "."))
      (do (def back (first (%get st from)))
          (%put! st to (pair (%here st) (%get st to)))
          (%put! st %doc (first back))
          (unless (= (List ref 1 back) (%get st %song)) (%go-song! st (List ref 1 back)))
          (%put! st %pattern (List ref 2 back))
          (%put! st from (rest (%get st from)))
          (edit-message! st "")
          (%sync-waves! st)
          (%heard-change! st)
          (%clamp! st)))))

(def %cell (fn (_ st) (pattern-cell (%channels st) (%get st %chan) (%get st %row))))

(def %move!
  (fn (_ st dr)
    (%put! st %row (int% (+ (+ (%get st %row) dr) (* 64 (%rows st))) (%rows st)))))

; TEXT put in the cell at the cursor, the cursor moved on by the step.
(def %put-cell!
  (fn (_ st text)
    (def why (song-cell-problem text))
    (if (not (null? why)) (edit-message! st why)
      (do (%set-channels! st (pattern-set-cell (%channels st) (%get st %chan) (%get st %row) text))
          (%move! st (%get st %step))))))

; The effects and gain of the cell at the cursor, from its first : or /.
(def %suffix
  (fn (_ cell)
    (def at (List find-index (fn (_ i) (List includes? (Str8 sub i 1 cell) (list ":" "/"))) (List range 0 (Str8 length cell))))
    (if (null? at) "" (Str8 sub at (- (Str8 length cell) at) cell))))

(def %note-names (list "C" "C#" "D" "D#" "E" "F" "F#" "G" "G#" "A" "A#" "B"))

; The piano's keys: each key and its semitone above the octave's C.
(def %piano
  (list (pair "z" 0) (pair "s" 1) (pair "x" 2) (pair "d" 3) (pair "c" 4) (pair "v" 5) (pair "g" 6) (pair "b" 7)
        (pair "h" 8) (pair "n" 9) (pair "j" 10) (pair "m" 11) (pair "," 12)
        (pair "q" 12) (pair "2" 13) (pair "w" 14) (pair "3" 15) (pair "e" 16) (pair "r" 17) (pair "5" 18)
        (pair "t" 19) (pair "6" 20) (pair "y" 21) (pair "7" 22) (pair "u" 23) (pair "i" 24)))

(def %note-for
  (fn (_ st semi)
    (def n (+ (* 12 (%get st %octave)) semi))
    (Str8 append (List ref (int% n 12) %note-names) (Str8 str (int/ n 12)))))

; A note typed: put in the cell, keeping its effects, and heard.
(def %note!
  (fn (_ st semi)
    (def note (%note-for st semi))
    (def inst (first (List ref (%get st %chan) (%channels st))))
    (def old (%cell st))
    ; Heard first, before the cell is changed and the screen drawn.
    (unless (null? (%get st %player))
      ((fn (_ e) (unless (null? e) (edit-message! st e)))
       (guard (e (if (Err err? e) (e msg) "the note cannot be played"))
         (do (player-preview! (%get st %player) (edit-song st) inst note) (edit-feed! st) ()))))
    (%put-cell! st (Str8 append note (if (List includes? (first (Str8 split "/" old)) (list "." "-")) "" (%suffix old))))))

; --- playing -----------------------------------------------------------------

(def %play!
  (fn (_ st mode)
    (def p (%get st %player))
    (match
      ((null? p) (edit-message! st "No sound: the audio could not be opened."))
      ((if (player-playing? p) (eq? (player-mode p) mode) #f) (do (player-stop! p) (%put! st %heard ()) (edit-message! st "")))
      ((null? (%get st %pattern)) (edit-message! st "The song has no pattern to play."))
      ((if (eq? mode (lit song)) (null? (song-order (edit-song st))) #f) (edit-message! st "The song has no order: :order NAME ..."))
      (#t ((fn (_ e) (edit-message! st (if (null? e) "" e)))
           (guard (e (if (Err err? e) (e msg) "the song cannot be played"))
             (do (%put! st %stale #f)
                 (player-start! p (edit-song st) mode (if (null? (%get st %at)) 0 (%get st %at)) (%get st %pattern)) ())))))))

; The player's stream topped up, nothing else: what a caller does just
; before work that keeps it from coming round for a while.  A song the
; mixer cannot play is stopped, and why is the message.
(def edit-feed!
  (fn (_ st)
    (def p (%get st %player))
    (unless (null? p)
      ((fn (_ e) (unless (null? e) (do (player-stop! p) (edit-message! st e))))
       (guard (e (if (Err err? e) (e msg) "the song cannot be played"))
         (do (player-pump! p) ()))))))

; The player fed, and the place heard: answers whether it moved since
; the screen was drawn.
(def edit-tick!
  (fn (_ st)
    (def p (%get st %player))
    (if (null? p) #f
      (do (edit-feed! st)
          (def heard (if (player-playing? p) (player-place p) ()))
          (def moved (not (equal? heard (%get st %heard))))
          (%put! st %heard heard)
          (when (if moved (if (%get st %follow) (not (null? heard)) #f) #f) (%follow! st p heard))
          moved))))

; --- the order ---------------------------------------------------------------

(def %goto-at!
  (fn (_ st at)
    (def order (song-order (edit-song st)))
    (unless (null? order)
      (do (%put! st %at (int% (+ at (List length order)) (List length order)))
          (%put! st %pattern (List ref (%get st %at) order))
          (%clamp! st)))))

; The pattern HEARD is in edited, and the cursor on the row heard.
(def %follow!
  (fn (_ st p heard)
    (unless (if (eq? (player-mode p) (lit pattern)) #t (%same? (first heard) (%get st %at)))
      (%goto-at! st (first heard)))
    (%put! st %row (%min (rest heard) (- (%rows st) 1)))))

(def %goto-pattern!
  (fn (_ st name)
    (%put! st %pattern name)
    (%put! st %at (List index-of name (song-order (edit-song st))))
    (%clamp! st)))

; --- commands ----------------------------------------------------------------

(def %write!
  (fn (_ st path)
    (def to (if (null? path) (%get st %path) path))
    (match ((null? to) (do (edit-message! st "No file name: :w FILE") #f))
           (#t ((fn (_ e)
                  (if (null? e) (do (%put! st %path to) (edit-message! st (Str8 append "Written: " to)) #t)
                    (do (edit-message! st e) #f)))
                (guard (e (if (Err err? e) (e msg) "the file cannot be written"))
                  (do (%put! st %doc (file-write! (%get st %doc) to)) ())))))))

(def %quit!
  (fn (_ st force)
    (if (if force #t (if (%get st %warned) #t (not (file-changed? (%get st %doc)))))
      (%put! st %quit #t)
      (do (%put! st %warned #t)
          (edit-message! st "The song has changed: :w writes it, :q! leaves without.")))))

(def %number-cmd!
  (fn (_ st args least most f)
    (def n (if (null? args) () (%num (first args))))
    (if (if (null? n) #t (if (< n least) #t (< most n)))
      (edit-message! st (Str8 append "A number from " (Str8 str least) " to " (Str8 str most) "."))
      (f n))))

(def %name? (fn (_ w) (not (if (Str8 includes? "\"" w) #t (if (Str8 includes? "(" w) #t (Str8 includes? ")" w))))))

; --- waves -------------------------------------------------------------------

(def %wave-name (fn (_ w) (symbol->str (List ref 1 w))))
(def %amps-text (fn (_ w) (Str8 join " " (List map (fn (_ a) (Str8 str a)) (rest (rest w))))))

; The waves the document's songs name, each once, then the file's own
; that no song names.
(def %wave-names
  (fn (_ st)
    (def doc (%get st %doc))
    (def used
      (List fold (fn (_ acc s) (List fold (fn (_ a n) (if (List includes? n a) a (List append a (list n)))) acc (song-waves s)))
        () (file-songs doc)))
    (List append used (List filter (fn (_ n) (not (List includes? n used))) (List map %wave-name (file-waves doc))))))

; The borrowed wave named NAME, from a file read with -w, or nil.
(def %borrowed-wave (fn (_ st name) (List find (fn (_ w) (str=? (%wave-name w) name)) (%get st %borrowed))))

; Where the wave named NAME comes from, and its harmonics.
(def %wave-source
  (fn (_ st name)
    (def mine (file-wave (%get st %doc) name))
    (def theirs (%borrowed-wave st name))
    (match ((not (null? mine)) (Str8 append "in the file      " (%amps-text mine)))
           ((not (null? theirs)) (Str8 append "borrowed (-w)    " (%amps-text theirs)))
           ((List includes? name (list "sine" "noise")) "the mixer's own")
           ((player-wave? name) "given to the mixer")
           (#t "missing: :wave NAME AMP ... makes it"))))

(def %wave-lines
  (fn (_ st)
    (pair "Waves   :wave NAME AMP ... makes or changes one   :waves keep copies the borrowed ones in"
      (List map (fn (_ n) (Str8 append "  " (%pad 12 n) (%wave-source st n) " ")) (%wave-names st)))))

; The waves the songs name and borrow, copied into the document, so the
; file no longer needs the one they were borrowed from.
(def %keep-waves!
  (fn (_ st)
    (def doc (%get st %doc))
    (def kept
      (List filter (fn (_ w) (not (null? w)))
        (List map (fn (_ n) (if (null? (file-wave doc n)) (%borrowed-wave st n) ())) (%wave-names st))))
    (if (null? kept) (edit-message! st "No wave is borrowed: the file has every wave its songs name but the mixer's own.")
      (do (%doc-change! st (List fold (fn (_ d w) (file-set-wave d (%wave-name w) (rest (rest w)))) doc kept))
          (edit-message! st (Str8 append "Kept in the file: " (Str8 join " " (List map %wave-name kept)) "."))))))

; :wave NAME shows the wave; :wave NAME AMP ... makes or changes it.
(def %wave-cmd!
  (fn (_ st args)
    (def amps (if (null? args) () (List map %num (rest args))))
    (match
      ((null? args) (edit-message! st ":wave NAME AMP ...   :waves lists them"))
      ((null? (rest args)) (edit-message! st (Str8 append (first args) ": " (%wave-source st (first args)))))
      ((not (%name? (first args))) (edit-message! st "A wave's name is a word."))
      ((List includes? (first args) (list "sine" "noise")) (edit-message! st (Str8 append (first args) " is the mixer's own.")))
      ((if (List any? (fn (_ a) (if (null? a) #t (< a 0))) amps) #t (List all? (fn (_ a) (= a 0)) amps))
        (edit-message! st "A wave's harmonics are whole numbers from 0, not all 0: (wave hollow 6 0 2 0 1)."))
      (#t (do (%doc-change! st (file-set-wave (%get st %doc) (first args) amps))
              (edit-message! st (Str8 append "Wave " (first args) ": " (Str8 join " " (rest args)) ".")))))))

(def %command!
  (fn (_ st line)
    (def words (List filter (fn (_ w) (not (str=? w ""))) (Str8 split " " line)))
    (def cmd (if (null? words) "" (first words)))
    (def args (if (null? words) () (rest words)))
    (def s (edit-song st))
    (edit-message! st "")
    (match
      ((str=? cmd "") ())
      ((str=? cmd "w") (%write! st (if (null? args) () (first args))))
      ((str=? cmd "q") (%quit! st #f))
      ((str=? cmd "q!") (%quit! st #t))
      ((if (str=? cmd "wq") #t (str=? cmd "x")) (when (%write! st (if (null? args) () (first args))) (%quit! st #t)))
      ((List includes? cmd (list "bpm" "rows" "ticks" "tension-bpm"))
        (%number-cmd! st args (if (str=? cmd "tension-bpm") 0 1) 999 (fn (_ n) (%change! st (song-set-prop s cmd n)))))
      ((str=? cmd "len")
        (if (null? (%get st %pattern)) (edit-message! st "No pattern.")
          (%number-cmd! st args 1 256 (fn (_ n) (%set-channels! st (pattern-resize (%channels st) n))))))
      ((str=? cmd "octave") (%number-cmd! st args 0 8 (fn (_ n) (%put! st %octave n))))
      ((str=? cmd "step") (%number-cmd! st args 0 64 (fn (_ n) (%put! st %step n))))
      ((str=? cmd "tension")
        (%number-cmd! st args 0 100 (fn (_ n) (unless (null? (%get st %player)) (player-tension! (%get st %player) n)))))
      ((str=? cmd "pace")
        (%number-cmd! st args 10 400 (fn (_ n) (unless (null? (%get st %player)) (player-pace! (%get st %player) n)))))
      ((str=? cmd "order")
        ((fn (_ missing)
           (if (null? missing) (%change! st (song-set-order s args))
             (edit-message! st (Str8 append "No pattern " (first missing) "."))))
         (List filter (fn (_ n) (null? (song-pattern s n))) args)))
      ((str=? cmd "pattern")
        (match ((not (= (List length args) 1)) (edit-message! st ":pattern NAME"))
               ((not (null? (song-pattern s (first args)))) (%goto-pattern! st (first args)))
               ((not (%name? (first args))) (edit-message! st "A pattern's name is a word."))
               (#t ((fn (_ chs)
                      (%change! st (song-set-pattern s (first args) chs))
                      (%goto-pattern! st (first args))
                      (edit-message! st (Str8 append "New pattern " (first args) ".")))
                    (if (null? (%channels st))
                      (List map (fn (_ i) (pair i (List repeat 16 "."))) (List take 1 (song-instruments s)))
                      (List map (fn (_ ch) (pair (first ch) (List repeat (%rows st) "."))) (%channels st)))))))
      ((str=? cmd "channel")
        (match ((not (= (List length args) 1)) (edit-message! st ":channel INSTRUMENT"))
               ((not (List includes? (first args) (song-instruments s))) (edit-message! st (Str8 append "No instrument " (first args) ".")))
               ((null? (%get st %pattern)) (edit-message! st "No pattern."))
               (#t (do (%set-channels! st (pattern-add-channel (%channels st) (first args)))
                       (%put! st %chan (- (List length (%channels st)) 1))))))
      ((str=? cmd "drop")
        (if (< (List length (%channels st)) 2) (edit-message! st "A pattern keeps one channel.")
          (%set-channels! st (pattern-drop-channel (%channels st) (%get st %chan)))))
      ((if (str=? cmd "instrument") (= (List length args) 1) #f)
        (%put! st %input (pair (lit instrument)
                           ((fn (_ t) (if (null? t) (Str8 append "(instrument " (first args) " (wave sine) (env (0 0) (5 70) (250 35)) (release 150) (gain 50))") (%one-line t)))
                            (song-instrument-text s (first args))))))
      ((str=? cmd "instrument")
        ((fn (_ e) (unless (null? e) (edit-message! st e)))
         (guard (e (if (Err err? e) (e msg) "not an instrument"))
           (do (%change! st (song-set-instrument s (Str8 append "(" line ")"))) ()))))
      ((str=? cmd "song")
        (if (null? args) (do (%put! st %pick (%get st %song)) (%put! st %help (%song-lines st)))
          ((fn (_ name i)
             (if (null? i)
               (do (%put! st %undo (pair (%here st) (%get st %undo)))
                   (%put! st %doc (file-add-song (%get st %doc) (song-new name)))
                   (%go-song! st (- (List length (file-songs (%get st %doc))) 1))
                   (edit-message! st (Str8 append "New song " name ".")))
               (%go-song! st i)))
           (Str8 join " " args) (List find-index (fn (_ s2) (str=? (song-name s2) (Str8 join " " args))) (file-songs (%get st %doc))))))
      ((str=? cmd "waves")
        (match ((null? args) (%put! st %help (%wave-lines st)))
               ((if (= (List length args) 1) (str=? (first args) "keep") #f) (%keep-waves! st))
               (#t (edit-message! st ":waves  or  :waves keep"))))
      ((str=? cmd "wave") (%wave-cmd! st args))
      ((str=? cmd "rename")
        (if (null? args) (edit-message! st ":rename NAME") (%change! st (song-rename s (Str8 join " " args)))))
      ((List includes? cmd (list "effects" "effect" "instruments" "copy-instrument" "rename-instrument" "drop-instrument"
                                 "patterns" "copy-pattern" "rename-pattern" "drop-pattern" "copy-song" "drop-song"
                                 "channel-instrument" "transpose" "gain"))
        (%edit-cmd! st cmd args line))
      (#t (edit-message! st (Str8 append "No command " cmd ": ? lists them."))))))

; --- editing the rest of a song ------------------------------------------------

; A word naming a new thing NAME in WHAT, or why not.
(def %new-name-problem
  (fn (_ name taken what)
    (match ((not (%name? name)) (Str8 append "A " what "'s name is a word."))
           ((List includes? name taken) (Str8 append "There is a " what " " name " already."))
           (#t ()))))

; F run, its error the message: F answers nil or a message of its own.
(def %try!
  (fn (_ st what f)
    ((fn (_ e) (unless (null? e) (edit-message! st e)))
     (guard (e (if (Err err? e) (e msg) what)) (f)))))

(def %effect-lines
  (fn (_ st)
    (def fx (song-effects (edit-song st)))
    (pair "Effects over the mix, in order   :effect (NAME N ...) adds one   :effect K edits the Kth   :effect drop K"
      (if (null? fx) (list "  none")
        (List map (fn (_ k) (Str8 append "  " (Str8 pad-left 2 #\space (Str8 str (+ k 1))) "  " (%one-line (List ref k fx)) " "))
          (List range 0 (List length fx)))))))

(def %instrument-lines
  (fn (_ st)
    (def s (edit-song st))
    (pair "Instruments   :instrument NAME edits one   :copy-instrument, :rename-instrument, :drop-instrument"
      (List flat-map
        (fn (_ n)
          (list (Str8 append "  " (%one-line (song-instrument-text s n)) " ")
                (Str8 append "      in: " ((fn (_ ps) (if (null? ps) "no pattern" (Str8 join " " ps))) (song-instrument-uses s n)) " ")))
        (song-instruments s)))))

(def %pattern-lines
  (fn (_ st)
    (def s (edit-song st))
    (def order (song-order s))
    (pair "Patterns   :pattern NAME edits one   :copy-pattern NEW, :rename-pattern NEW, :drop-pattern [NAME]   O edits the order"
      (List map
        (fn (_ p)
          (Str8 append "  " (%pad 12 (first p)) (Str8 pad-left 4 #\space (Str8 str (pattern-rows (rest p)))) " rows  "
            (Str8 join " " (List map first (rest p)))
            ((fn (_ n) (if (= n 0) "   (not in the order)" (Str8 append "   played " (Str8 str n) "x"))) (List length (List filter (fn (_ o) (str=? o (first p))) order)))
            " "))
        (song-patterns s)))))

; :effect (FORM) adds an effect, :effect K edits the Kth on the command
; line, :effect K (FORM) puts it in, :effect drop K drops it.
(def %effect-cmd!
  (fn (_ st args line)
    (def s (edit-song st))
    (def n (List length (song-effects s)))
    (def k (if (null? args) () (%num (first args))))
    (def form-text ((fn (_ at) (if (null? at) "" (Str8 sub at (- (Str8 length line) at) line))) (Str8 index-of "(" line)))
    (match
      ((null? args) (edit-message! st ":effect (NAME N ...)   :effect K   :effect drop K   :effects lists them"))
      ((Str8 starts? "(" (first args)) (%try! st "not an effect" (fn (_) (%change! st (song-set-effect s n form-text)) ())))
      ((if (str=? (first args) "drop") (not (null? (rest args))) #f)
        ((fn (_ j) (if (if (null? j) #t (if (< j 1) #t (< n j))) (edit-message! st (Str8 append "No effect " (List ref 1 args) "."))
                     (%change! st (song-drop-effect s (- j 1)))))
         (%num (List ref 1 args))))
      ((if (null? k) #t (if (< k 1) #t (< n k))) (edit-message! st (Str8 append "No effect " (first args) ": :effects lists them.")))
      ((null? (rest args)) (%put! st %input (pair (pair (lit effect) (- k 1)) (%one-line (List ref (- k 1) (song-effects s))))))
      (#t (%try! st "not an effect" (fn (_) (%change! st (song-set-effect s (- k 1) form-text)) ()))))))

; The rows and channels the block covers, (R0 R1 C0 C1), from the mark
; to the cursor; the cursor's cell alone when nothing is marked.
(def %block
  (fn (_ st)
    (def m (%get st %mark))
    (def r (%get st %row)) (def c (%get st %chan))
    (if (null? m) (list r r c c)
      ((fn (_ mr mc) (list (%min mr r) (%max mr r) (%min mc c) (%max mc c)))
       (%min (first m) (- (%rows st) 1)) (%min (rest m) (- (List length (%channels st)) 1))))))

; Each cell of the block made F of it; the mark kept, so a second
; change can follow.
(def %map-block!
  (fn (_ st f)
    (def b (%block st))
    (%set-channels! st (pattern-map-block (%channels st) (List ref 2 b) (List ref 3 b) (first b) (List ref 1 b) f))))

(def %copy-block!
  (fn (_ st)
    (def b (%block st))
    (%put! st %clip (pattern-block (%channels st) (List ref 2 b) (List ref 3 b) (first b) (List ref 1 b)))
    (edit-message! st (Str8 append "Copied " (Str8 str (+ 1 (- (List ref 1 b) (first b)))) " rows of "
                        (Str8 str (+ 1 (- (List ref 3 b) (List ref 2 b)))) " channels: P pastes them."))))

(def %edit-cmd!
  (fn (_ st cmd args line)
    (def s (edit-song st))
    (def pat (%get st %pattern))
    (def one (if (null? args) () (first args)))
    (match
      ((str=? cmd "effects") (%put! st %help (%effect-lines st)))
      ((str=? cmd "effect") (%effect-cmd! st args line))
      ((str=? cmd "instruments") (%put! st %help (%instrument-lines st)))
      ((str=? cmd "patterns") (%put! st %help (%pattern-lines st)))
      ((str=? cmd "copy-instrument")
        (match ((not (= (List length args) 2)) (edit-message! st ":copy-instrument NAME NEW"))
               ((null? (song-instrument-text s one)) (edit-message! st (Str8 append "No instrument " one ".")))
               ((not (null? (%new-name-problem (List ref 1 args) (song-instruments s) "instrument")))
                 (edit-message! st (%new-name-problem (List ref 1 args) (song-instruments s) "instrument")))
               (#t (%change! st (song-copy-instrument s one (List ref 1 args))))))
      ((str=? cmd "rename-instrument")
        (match ((not (= (List length args) 2)) (edit-message! st ":rename-instrument NAME NEW"))
               ((null? (song-instrument-text s one)) (edit-message! st (Str8 append "No instrument " one ".")))
               ((not (null? (%new-name-problem (List ref 1 args) (song-instruments s) "instrument")))
                 (edit-message! st (%new-name-problem (List ref 1 args) (song-instruments s) "instrument")))
               (#t (%change! st (song-rename-instrument s one (List ref 1 args))))))
      ((str=? cmd "drop-instrument")
        (match ((not (= (List length args) 1)) (edit-message! st ":drop-instrument NAME"))
               ((null? (song-instrument-text s one)) (edit-message! st (Str8 append "No instrument " one ".")))
               ((not (null? (song-instrument-uses s one)))
                 (edit-message! st (Str8 append one " plays in " (Str8 join " " (song-instrument-uses s one)) ": drop its channels first.")))
               (#t (%change! st (song-drop-instrument s one)))))
      ((str=? cmd "channel-instrument")
        (match ((not (= (List length args) 1)) (edit-message! st ":channel-instrument NAME"))
               ((null? pat) (edit-message! st "No pattern."))
               ((null? (song-instrument-text s one)) (edit-message! st (Str8 append "No instrument " one ".")))
               (#t (%set-channels! st (pattern-set-instrument (%channels st) (%get st %chan) one)))))
      ((str=? cmd "copy-pattern")
        (match ((not (= (List length args) 1)) (edit-message! st ":copy-pattern NEW"))
               ((null? pat) (edit-message! st "No pattern."))
               ((not (null? (%new-name-problem one (List map first (song-patterns s)) "pattern")))
                 (edit-message! st (%new-name-problem one (List map first (song-patterns s)) "pattern")))
               (#t (do (%change! st (song-set-pattern s one (%channels st)))
                       (%goto-pattern! st one)
                       (edit-message! st (Str8 append "Copied to " one "."))))))
      ((str=? cmd "rename-pattern")
        (match ((not (= (List length args) 1)) (edit-message! st ":rename-pattern NEW"))
               ((null? pat) (edit-message! st "No pattern."))
               ((not (null? (%new-name-problem one (List map first (song-patterns s)) "pattern")))
                 (edit-message! st (%new-name-problem one (List map first (song-patterns s)) "pattern")))
               (#t (do (%change! st (song-rename-pattern s pat one)) (%put! st %pattern one)))))
      ((str=? cmd "drop-pattern")
        ((fn (_ name)
           (match ((null? name) (edit-message! st "No pattern."))
                  ((null? (song-pattern s name)) (edit-message! st (Str8 append "No pattern " name ".")))
                  ((< (List length (song-patterns s)) 2) (edit-message! st "A song keeps one pattern."))
                  (#t (do (%change! st (song-drop-pattern s name))
                          (%clamp! st)
                          (edit-message! st (Str8 append "Dropped " name "."))))))
         (if (null? one) pat one)))
      ((str=? cmd "copy-song")
        (if (null? args) (edit-message! st ":copy-song NAME")
          ((fn (_ name)
             (if (List any? (fn (_ s2) (str=? (song-name s2) name)) (file-songs (%get st %doc)))
               (edit-message! st (Str8 append "There is a song " name " already."))
               (do (%put! st %undo (pair (%here st) (%get st %undo)))
                   (%put! st %doc (file-add-song (%get st %doc) (song-rename s name)))
                   (%go-song! st (- (List length (file-songs (%get st %doc))) 1))
                   (edit-message! st (Str8 append "Copied to " name ".")))))
           (Str8 join " " args))))
      ((str=? cmd "drop-song")
        (if (< (List length (file-songs (%get st %doc))) 2) (edit-message! st "A file keeps one song.")
          ((fn (_ name)
             (%put! st %undo (pair (%here st) (%get st %undo)))
             (%put! st %doc (file-drop-song (%get st %doc) (%get st %song)))
             (%go-song! st (%max 0 (- (%get st %song) 1)))
             (edit-message! st (Str8 append "Dropped " name ": U brings it back.")))
           (song-name s))))
      ((str=? cmd "transpose")
        ((fn (_ n) (%unless-bad! st (null? n) ":transpose N, semitones up or down"
                     (fn (_) (%map-block! st (fn (_ c) (cell-transpose c n))))))
         (if (null? one) () (%num one))))
      ((str=? cmd "gain")
        ((fn (_ n) (%unless-bad! st (if (null? n) #t (if (< n 0) #t (< 400 n))) ":gain PCT, from 0 to 400"
                     (fn (_) (%map-block! st (fn (_ c) (cell-gain c n))))))
         (if (null? one) () (%num one))))
      (#t ()))))

; MSG the message when BAD, else F run.
(def %unless-bad! (fn (_ st bad msg f) (if bad (edit-message! st msg) (f))))

; --- the order, edited in place ----------------------------------------------

; A key while O edits the order: left and right pick a place, up and
; down change its pattern, i puts a copy after it, d drops it, [ ] move
; it, Enter edits its pattern, Escape or O stops.
(def %order-key!
  (fn (_ st key)
    (def s (edit-song st))
    (def order (song-order s))
    (def n (List length order))
    (def at (%min (%get st %order-at) (%max 0 (- n 1))))
    (def names (List map first (song-patterns s)))
    (def put-order! (fn (_ o k) (do (%change! st (song-set-order s o)) (%put! st %order-at k))))
    (def stop! (fn (_) (do (%put! st %order-at ()) (edit-message! st ""))))
    (match
      ((if (eq? key (lit escape)) #t (%is? key "O")) (stop!))
      ((eq? key (lit left)) (%put! st %order-at (%max 0 (- at 1))))
      ((eq? key (lit right)) (%put! st %order-at (%min (%max 0 (- n 1)) (+ at 1))))
      ((if (%is? key "i") #t (eq? key (lit insert)))
        (put-order! (if (= n 0) (List take 1 names) (List insert (+ at 1) (List ref at order) order)) (if (= n 0) 0 (+ at 1))))
      ((= n 0) ())
      ((if (%is? key "d") #t (if (eq? key (lit delete)) #t (eq? key (lit backspace))))
        (put-order! (List remove at 1 order) (%max 0 (%min at (- n 2)))))
      ((if (eq? key (lit up)) #t (eq? key (lit down)))
        ((fn (_ i) (put-order! (List update at (List ref (int% (+ i (+ (List length names) (if (eq? key (lit up)) -1 1))) (List length names)) names) order) at))
         (%max 0 (List index-of (List ref at order) names))))
      ((%is? key "[") (when (< 0 at) (put-order! (List update (- at 1) (List ref at order) (List update at (List ref (- at 1) order) order)) (- at 1))))
      ((%is? key "]") (when (< at (- n 1)) (put-order! (List update (+ at 1) (List ref at order) (List update at (List ref (+ at 1) order) order)) (+ at 1))))
      ((eq? key (lit enter)) (do (stop!) (%goto-at! st at)))
      (#t ()))))

; --- keys --------------------------------------------------------------------

(def %is? (fn (_ key s) (if (str? key) (str=? key s) #f)))
(def %str-entry (fn (_ k alist) (List find (fn (_ e) (str=? (first e) k)) alist)))

(def %input-text (fn (_ st) (rest (%get st %input))))

; The line typed, finished by Enter.
(def %input-done!
  (fn (_ st)
    (def kind (first (%get st %input)))
    (def text (%input-text st))
    (%put! st %input ())
    (match
      ((eq? kind (lit command)) (%command! st text))
      ((eq? kind (lit cell)) (%put-cell! st (Str8 trim text)))
      ((pair? kind)
        (%try! st "not an effect" (fn (_) (%change! st (song-set-effect (edit-song st) (rest kind) (Str8 trim text))) ())))
      (#t ((fn (_ e) (unless (null? e) (edit-message! st e)))
           (guard (e (if (Err err? e) (e msg) "not an instrument"))
             (do (%change! st (song-set-instrument (edit-song st) text)) ())))))))

(def %input-key!
  (fn (_ st key)
    (match
      ((eq? key (lit enter)) (%input-done! st))
      ((if (eq? key (lit escape)) #t (eq? key (lit interrupt))) (%put! st %input ()))
      ((eq? key (lit backspace))
        ((fn (_ t) (if (str=? t "") (%put! st %input ())
                     (%put! st %input (pair (first (%get st %input)) (Str8 sub 0 (- (Str8 length t) 1) t)))))
         (%input-text st)))
      ((eq? key (lit kill-bol)) (%put! st %input (pair (first (%get st %input)) "")))
      ((str? key) (%put! st %input (pair (first (%get st %input)) (Str8 append (%input-text st) key))))
      (#t ()))))

; An instrument's text on one line, for editing.
(def %one-line
  (fn (_ text) (Str8 join " " (List filter (fn (_ w) (not (str=? w ""))) (Str8 split " " (Str8 replace "\n" " " text))))))

(def edit-key!
  (fn (_ st key)
    (match
      ((null? key) ())
      ((not (null? (%get st %input))) (%input-key! st key))
      ((not (null? (%get st %pick))) (%pick-key! st key))
      ((%get st %help) (%put! st %help #f))
      ((not (null? (%get st %order-at))) (%order-key! st key))
      ((%is? key "O")
        (do (%put! st %order-at (if (null? (%get st %at)) 0 (%get st %at)))
            (edit-message! st "Order: left right pick, up down its pattern, i copy, d drop, [ ] move, Enter edit, Escape done")))
      ((eq? key (lit interrupt)) (%quit! st #f))
      ((%is? key ":") (%put! st %input (pair (lit command) "")))
      ((%is? key "?") (%put! st %help %help-lines))
      ((%is? key "U") (%undo-step! st %undo %redo "undo"))
      ((%is? key "R") (%undo-step! st %redo %undo "redo"))
      ((%is? key " ") (%play! st (lit song)))
      ((%is? key "p") (%play! st (lit pattern)))
      ((%is? key "F")
        (do (%put! st %follow (not (%get st %follow)))
            (edit-message! st (if (%get st %follow) "Following the playing." "Not following the playing."))))
      ((%is? key "[") (%goto-at! st (- (if (null? (%get st %at)) 0 (%get st %at)) 1)))
      ((%is? key "]") (%goto-at! st (+ (if (null? (%get st %at)) -1 (%get st %at)) 1)))
      ((%is? key "<") (%put! st %octave (%max 0 (- (%get st %octave) 1))))
      ((%is? key ">") (%put! st %octave (%min 8 (+ (%get st %octave) 1))))
      ((%is? key "{") (%put! st %step (%max 0 (- (%get st %step) 1))))
      ((%is? key "}") (%put! st %step (%min 64 (+ (%get st %step) 1))))
      ((null? (%get st %pattern)) (edit-message! st "The song has no pattern: :pattern NAME makes one."))
      ((eq? key (lit up)) (%move! st -1))
      ((eq? key (lit down)) (%move! st 1))
      ((eq? key (lit page-up)) (%put! st %row (%max 0 (- (%get st %row) 16))))
      ((eq? key (lit page-down)) (%put! st %row (%min (- (%rows st) 1) (+ (%get st %row) 16))))
      ((eq? key (lit home)) (%put! st %row 0))
      ((eq? key (lit end)) (%put! st %row (- (%rows st) 1)))
      ((eq? key (lit left)) (%put! st %chan (%max 0 (- (%get st %chan) 1))))
      ((eq? key (lit right)) (%put! st %chan (%min (- (List length (%channels st)) 1) (+ (%get st %chan) 1))))
      ((eq? key (lit complete)) (%put! st %chan (int% (+ (%get st %chan) 1) (List length (%channels st)))))
      ((eq? key (lit enter)) (%put! st %input (pair (lit cell) (%cell st))))
      ((%is? key "E")
        (%put! st %input (pair (lit instrument)
                           (%one-line (song-instrument-text (edit-song st) (first (List ref (%get st %chan) (%channels st))))))))
      ((%is? key "V")
        (if (null? (%get st %mark))
          (do (%put! st %mark (pair (%get st %row) (%get st %chan)))
              (edit-message! st "Marking: move to the block's other corner; Y copy, X cut, P paste, Delete clear, :transpose N, :gain PCT"))
          (do (%put! st %mark ()) (edit-message! st ""))))
      ((eq? key (lit escape)) (%put! st %mark ()))
      ((%is? key "Y") (do (%copy-block! st) (%put! st %mark ())))
      ((%is? key "X") (do (%copy-block! st) (%map-block! st (fn (_ c) ".")) (%put! st %mark ())))
      ((%is? key "P")
        (if (null? (%get st %clip)) (edit-message! st "Nothing copied: V marks a block, Y copies it.")
          (%set-channels! st (pattern-paste (%channels st) (%get st %chan) (%get st %row) (%get st %clip)))))
      ((%is? key "(")
        (when (< 0 (%get st %chan))
          (do (%set-channels! st (pattern-move-channel (%channels st) (%get st %chan) -1)) (%put! st %chan (- (%get st %chan) 1)))))
      ((%is? key ")")
        (when (< (%get st %chan) (- (List length (%channels st)) 1))
          (do (%set-channels! st (pattern-move-channel (%channels st) (%get st %chan) 1)) (%put! st %chan (+ (%get st %chan) 1)))))
      ((if (null? (%get st %mark)) #f (if (%is? key ".") #t (if (eq? key (lit backspace)) #t (eq? key (lit delete)))))
        (do (%map-block! st (fn (_ c) ".")) (%put! st %mark ())))
      ((%is? key "I") (%set-channels! st (pattern-insert-row (%channels st) (%get st %row))))
      ((%is? key "D") (%set-channels! st (pattern-delete-row (%channels st) (%get st %row))))
      ((if (%is? key ".") #t (if (eq? key (lit backspace)) #t (eq? key (lit delete)))) (%put-cell! st "."))
      ((%is? key "-") (%put-cell! st "-"))
      ((if (str? key) (not (null? (%str-entry key %piano))) #f) (%note! st (rest (%str-entry key %piano))))
      (#t ()))))

; --- drawing -----------------------------------------------------------------

(def %bar (Style make (list (lit reverse)) () ()))
(def %dim (Style make (list (lit dim)) () ()))
(def %bold (Style make (list (lit bold)) () ()))
(def %beat (Style make () 3 ()))
(def %off (Style make () 1 ()))
(def %fx (Style make () 6 ()))
(def %cursor (Style make (list (lit reverse)) () ()))
(def %playing (Style make (list (lit bold)) 2 ()))
(def %block-style (Style make () 0 6))

; S padded with blanks or cut to W bytes.  A cell is ASCII by its syntax,
; and a screen of them is drawn for every row heard, so this is the byte
; doors and one concatenation, not class sends.
(def %blanks "                                                                ")
(def %pad
  (fn (_ w s)
    (def n (str-byte-len s))
    (match ((int< w n) (str-byte-sub s 0 w))
           ((int< (int- w n) (str-byte-len %blanks)) (%str-concat (list s (str-byte-sub %blanks 0 (int- w n)))))
           (#t (Str8 pad-right w #\space s)))))

(def %help-lines
  (list "Keys"
        "  z s x d c v g b h n j m ,   a note, C to C, in the octave"
        "  q 2 w 3 e r 5 t 6 y 7 u i   a note, the octave above"
        "  .  or Delete    hold          -   let go"
        "  < >   octave      { }   step: rows moved after a note"
        "  arrows Tab PgUp PgDn Home End   move"
        "  Enter   edit the cell: NOTE[:GAIN][/EFFECT...]"
        "  E   edit the channel's instrument     I D   insert, delete a row"
        "  [ ]   the pattern before, after in the order"
        "  Space   play the song from here     p   play the pattern"
        "  F   follow the playing, or stop following"
        "  O   edit the order in place     ( )   move the channel left, right"
        "  V   mark a block    Y X P   copy, cut, paste    Delete   clear it"
        "  U R   undo, redo     ?   this     ctrl-c   quit"
        "Commands"
        "  :w [FILE]  :q  :q!  :wq            :song [NAME]  :rename NAME"
        "  :bpm N  :rows N  :ticks N  :tension-bpm N  :len N"
        "  :pattern NAME  :order NAME ...  :channel INSTRUMENT  :drop"
        "  :instrument NAME PROP ...  :octave N  :step N  :tension N  :pace N"
        "  :waves  list them   :waves keep   copy the borrowed in   :wave NAME AMP ..."
        "  :effects  :effect (NAME N ...)  :effect K  :effect drop K"
        "  :instruments  :instrument NAME  :copy-, :rename-, :drop-instrument"
        "  :patterns  :copy-pattern NEW  :rename-pattern NEW  :drop-pattern [NAME]"
        "  :copy-song NAME  :drop-song  :channel-instrument NAME"
        "  :transpose N  :gain PCT   the block, or the cell"
        "Effects (after /):  a arpeggio  v vibrato  s slide  p portamento"
        "  t tremolo  f fade  l low-pass  c cut  d delay  r retrigger"
        ""
        "Any key closes this."))

; The songs of the document, the one edited marked.
(def %song-lines
  (fn (_ st)
    (def here (song-name (edit-song st)))
    (pair "Songs   up, down: pick   Enter: edit it   Escape: close   :song NAME makes one"
      (List map (fn (_ s) (Str8 append (if (str=? (song-name s) here) "  > " "    ") (song-name s) " "))
        (file-songs (%get st %doc))))))

; A key while :song lists the songs: up and down move the highlight,
; Enter edits the song highlighted, any other key closes the list.
(def %pick-key!
  (fn (_ st key)
    (def n (List length (file-songs (%get st %doc))))
    (def close! (fn (_) (do (%put! st %pick ()) (%put! st %help #f))))
    (match
      ((eq? key (lit up)) (%put! st %pick (int% (+ (- (%get st %pick) 1) n) n)))
      ((eq? key (lit down)) (%put! st %pick (int% (+ (%get st %pick) 1) n)))
      ((eq? key (lit home)) (%put! st %pick 0))
      ((eq? key (lit end)) (%put! st %pick (- n 1)))
      ((eq? key (lit enter)) ((fn (_ i) (close!) (%go-song! st i) (edit-message! st "")) (%get st %pick)))
      (#t (close!)))))

; TEXT put on SCREEN, COLS wide, at ROW and COL; nothing when COL is
; past its right edge.  x/tui/screen's put keeps to the rows but not to
; the columns: one past the edge is written past the row's end, and past
; the last row's, into whatever the heap holds there.
(def %put-text!
  (fn (_ screen cols row col text style)
    (when (int< col cols) (Screen put screen row col text style))))

; LINES put on SCREEN from row TOP, HIGH rows: the first a heading on a
; row of its own, the rest beneath it, a column of HIGH less one, the
; columns side by side as wide as the widest line, as many as the screen
; is wide for.  A line not starting with a blank is a heading, in bold;
; the line HI of the rest, when it is not nil, is highlighted.
(def %draw-panel!
  (fn (_ screen lines top high hi)
    (def h (%max 1 (- high 1)))
    (def body (rest lines))
    (def cols (Screen cols screen))
    (def w (+ 2 (List fold (fn (_ m l) (%max m (Str8 length l))) 0 body)))
    (def style (fn (_ l) (if (< 0 (Str8 length l)) (if (Str8 starts? " " l) 0 %bold) 0)))
    (Screen put screen top 0 (first lines) (style (first lines)))
    (List fold
      (fn (_ i l)
        (%put-text! screen cols (+ (+ top 1) (int% i h)) (* w (int/ i h)) l (if (%same? i hi) %cursor (style l)))
        (+ i 1))
      0 body)))

(def %title
  (fn (_ st)
    (def s (edit-song st))
    (def p (%get st %player))
    (Str8 append " x-tracker  " (if (null? (%get st %path)) "(no file)" (%get st %path))
      (if (file-changed? (%get st %doc)) " [+]" "")
      "   \"" (song-name s) "\""
      "   bpm " (Str8 str (song-prop s "bpm" 90)) "  rows " (Str8 str (song-prop s "rows" 4))
      "  ticks " (Str8 str (song-prop s "ticks" 6))
      "   octave " (Str8 str (%get st %octave)) "  step " (Str8 str (%get st %step))
      (match ((null? p) "   (no sound)")
             ((not (player-playing? p)) "")
             ((eq? (player-mode p) (lit song)) "   > song")
             (#t "   > pattern")))))

; The order, the place edited marked [NAME], the place heard >NAME.
(def %order-line
  (fn (_ st)
    (def order (song-order (edit-song st)))
    (def heard (if (null? (%get st %heard)) () (first (%get st %heard))))
    (def playing-song (if (null? (%get st %player)) #f (if (player-playing? (%get st %player)) (eq? (player-mode (%get st %player)) (lit song)) #f)))
    (Str8 append " order: "
      (if (null? order) "(none)"
        (Str8 join " "
          (List map (fn (_ i)
                      (def name (List ref i order))
                      (def mark (if (if playing-song (%same? i heard) #f) (Str8 append ">" name) name))
                      (match ((%same? i (%get st %order-at)) (Str8 append "<" mark ">"))
                             ((if (null? (%get st %order-at)) (%same? i (%get st %at)) #f) (Str8 append "[" mark "]"))
                             (#t mark)))
            (List range 0 (List length order)))))
      (if (if (null? (%get st %at)) (not (null? (%get st %pattern))) #f)
        (Str8 append "   editing " (%get st %pattern) ", not in the order") ""))))

; Whether S has a / from byte I on.
(def %slash?
  (fn (self s i) (if (int< i (str-byte-len s)) (if (int= (str-byte-ref s i) 47) #t (self s (int+ i 1))) #f)))

(def %cell-style
  (fn (_ cell)
    (def b (if (int< 0 (str-byte-len cell)) (str-byte-ref cell 0) 0))
    (match ((if (int= b 46) (int= 1 (str-byte-len cell)) #f) %dim)
           ((int= b 45) %off)
           ((%slash? cell 0) %fx)
           (#t 0))))

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

(def %draw-grid!
  (fn (_ st screen top bottom)
    (def chs (%channels st))
    (def rows (%rows st))
    (def beat (%max 1 (song-prop (edit-song st) "rows" 4)))
    (def cols (Screen cols screen))
    (def w (%max 6 (%min 14 (+ 1 (List fold (fn (_ n c) (%max n (Str8 length c))) 0 (List flat-map rest chs))))))
    (def fit (%max 1 (int/ (- cols 5) w)))
    (when (< (%get st %chan) (%get st %left)) (%put! st %left (%get st %chan)))
    (when (not (< (%get st %chan) (+ (%get st %left) fit))) (%put! st %left (+ (- (%get st %chan) fit) 1)))
    (def shown (- (- bottom top) 1))
    (when (< (%get st %row) (%get st %top)) (%put! st %top (%get st %row)))
    (when (not (< (%get st %row) (+ (%get st %top) shown))) (%put! st %top (+ (- (%get st %row) shown) 1)))
    (def left (%get st %left))
    (def shown-chs (List take (%min (List length chs) fit) (List drop left chs)))
    (def heard (%heard-row st))
    (def first-row (%get st %top))
    (def cur-row (%get st %row))
    (def cur-chan (int- (%get st %chan) left))
    ; The block marked, its rows and its channels as shown, or nil.
    (def blk (if (null? (%get st %mark)) () ((fn (_ b) (list (first b) (List ref 1 b) (int- (List ref 2 b) left) (int- (List ref 3 b) left))) (%block st))))
    (def in-blk? (fn (_ r k) (if (null? blk) #f (if (int< r (first blk)) #f (if (int< (List ref 1 blk) r) #f (if (int< k (List ref 2 blk)) #f (not (int< (List ref 3 blk) k))))))))
    ((fn (self cs k)
       (unless (null? cs)
         (do (%put-text! screen cols top (int+ 5 (* w k)) (%pad (int- w 1) (first (first cs))) %bold)
             (self (rest cs) (int+ k 1)))))
     shown-chs 0)
    ; Each channel's cells from the first row shown, walked a row at a
    ; time: a row's cells put, the lists of the rows after it answered.
    (def put-row!
      (fn (self y r cs k acc)
        (if (null? cs) acc
          ((fn (_ cells)
             (def cell (if (null? cells) "." (first cells)))
             (%put-text! screen cols (int+ (int+ top 1) y) (int+ 5 (* w k)) (%pad (int- w 1) cell)
               (match ((if (int= r cur-row) (int= k cur-chan) #f) %cursor) ((in-blk? r k) %block-style) (#t (%cell-style cell))))
             (self y r (rest cs) (int+ k 1) (pair (if (null? cells) () (rest cells)) acc)))
           (first cs)))))
    (def rev (fn (self xs acc) (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))
    ((fn (self y cs)
       (def r (int+ first-row y))
       (when (if (int< y shown) (int< r rows) #f)
         (do (%put-text! screen cols (int+ (int+ top 1) y) 0 (Str8 pad-left 3 #\space (Str8 str r))
               (if (%same? r heard) %playing (if (int= 0 (int% r beat)) %beat %dim)))
             (when (%same? r heard) (%put-text! screen cols (int+ (int+ top 1) y) 3 ">" %playing))
             (self (int+ y 1) (rev (put-row! y r cs 0 ()) ())))))
     0 (List map (fn (_ ch) (List drop first-row (rest ch))) shown-chs))))

(def edit-draw!
  (fn (_ st screen)
    (Screen clear screen)
    (def rows (Screen rows screen))
    (def cols (Screen cols screen))
    (Screen fill screen 0 0 cols %bar)
    (Screen put screen 0 0 (%title st) %bar)
    (Screen put screen 1 0 (%order-line st) 0)
    (match
      ((%get st %help) (%draw-panel! screen (%get st %help) 2 (- rows 3) (%get st %pick)))
      ((null? (%get st %pattern)) (Screen put screen 3 1 "The song has no pattern: :pattern NAME makes one." 0))
      (#t (%draw-grid! st screen 3 (- rows 2))))
    (def input (%get st %input))
    (match
      ((null? input)
        (Screen put screen (- rows 1) 0
          (if (str=? (%get st %msg) "") " ? keys   Space play   p pattern   : command" (Str8 append " " (%get st %msg)))
          (if (str=? (%get st %msg) "") %dim 0)))
      (#t ((fn (_ prompt)
             (Screen put screen (- rows 1) 0 (Str8 append prompt (rest input)) 0)
             (Screen cursor screen (- rows 1) (%min (- cols 1) (+ (Str8 length prompt) (Str8 length (rest input))))))
           (match ((eq? (first input) (lit command)) ":")
                  ((eq? (first input) (lit cell)) "cell: ")
                  (#t "instrument: ")))))
    st))

(provide tracker/edit edit-make edit-song edit-doc edit-quit? edit-message edit-message! edit-player edit-place
  edit-feed! edit-settle! edit-tick! edit-key! edit-draw!)
