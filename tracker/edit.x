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
(import x/core/doors int/ int% int+ int- int< int= str-byte-len str-byte-ref str-byte-sub)
(import tracker/song song-new song-name song-rename song-patterns song-pattern song-order song-prop
  song-instruments song-instrument-text song-waves song-set-pattern song-set-order song-set-prop song-set-instrument
  pattern-rows pattern-cell pattern-set-cell pattern-resize pattern-insert-row pattern-delete-row
  pattern-add-channel pattern-drop-channel song-cell-problem)
(import tracker/file file-songs file-song! file-add-song file-changed? file-write! file-waves file-wave file-set-wave)
(import tracker/player player-playing? player-mode player-start! player-stop! player-update! player-preview!
  player-pump! player-place player-tension! player-pace! player-waves player-waves! player-wave? player-open
  player-start-at! player-tension player-pace player-volume player-volume! player-hears? player-mute! player-solo!
  player-muted? player-soloed? player-unmute! player-loop! player-loop player-render!)
(import tracker/config config-default config-set-text! config-get config-put! config-style config-key config-lines
  config-backup!)

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
(def %config 24)    ; the settings (tracker/config)
(def %mark 25)      ; the row L marked as a loop's first, or nil
(def %slots 26)

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
    st))

; An editor of DOC, read from PATH, heard through PLAYER (nil for none),
; with the settings CONFIG (tracker/config) when given, else the defaults.
; A document with no song is given one.
(def edit-make
  (fn (_ doc path player . config)
    (def st (Vector make %slots ()))
    (def cfg (if (null? config) (config-default) (first config)))
    (%put! st %config cfg)
    (%put! st %doc (if (null? (file-songs doc)) (file-add-song doc (song-new "untitled")) doc))
    (%put! st %path path)
    (%put! st %octave (config-get cfg (lit octave)))
    (%put! st %step (config-get cfg (lit step)))
    (%put! st %msg "")
    (%put! st %player player)
    (%put! st %quit #f)
    (%put! st %help #f)
    (%put! st %warned #f)
    (%put! st %follow (config-get cfg (lit follow)))
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
    (%put! st %undo (pair (%here st) (List take (- (config-get (%get st %config) (lit undo)) 1) (%get st %undo))))
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

(def %no-sound "No sound: the audio could not be opened.")

; The song (MODE song) or the pattern edited (pattern) played from ROW,
; the pattern looping RANGE, (FROM . TO) or nil for all its rows; when
; TOGGLE, the same mode playing is stopped instead.  The message is
; DONE, or why it cannot be played.
(def %start!
  (fn (_ st mode row range toggle done)
    (def p (%get st %player))
    (match
      ((null? p) (edit-message! st %no-sound))
      ((if toggle (if (player-playing? p) (eq? (player-mode p) mode) #f) #f)
        (do (player-stop! p) (%put! st %heard ()) (edit-message! st "")))
      ((null? (%get st %pattern)) (edit-message! st "The song has no pattern to play."))
      ((if (eq? mode (lit song)) (null? (song-order (edit-song st))) #f) (edit-message! st "The song has no order: :order NAME ..."))
      (#t ((fn (_ e) (edit-message! st (if (null? e) done e)))
           (guard (e (if (Err err? e) (e msg) "the song cannot be played"))
             (do (%put! st %stale #f)
                 (player-loop! p range)
                 (player-start-at! p (edit-song st) mode (if (null? (%get st %at)) 0 (%get st %at)) (%get st %pattern) row)
                 ())))))))

(def %play! (fn (_ st mode) (%start! st mode 0 () #t "")))

; The song played from the cursor's row: the pattern alone when it is
; not in the order.
(def %play-here!
  (fn (_ st)
    (%start! st (if (null? (%get st %at)) (lit pattern) (lit song)) (%get st %row) () #f
      (Str8 append "Playing from row " (Str8 str (%get st %row)) "."))))

; Rows A to B of the pattern edited, either way round, played over and over.
(def %loop!
  (fn (_ st a b)
    (def from (%min a b))
    (def to (%min (%max a b) (- (%rows st) 1)))
    (%put! st %mark ())
    (%start! st (lit pattern) from (pair from to) #f
      (Str8 append "Looping rows " (Str8 str from) " to " (Str8 str to) ": p plays the whole pattern."))))

; L: the cursor's row marked as a loop's first, or with a row marked,
; the rows from it to the cursor's looped.
(def %loop-key!
  (fn (_ st)
    (if (null? (%get st %mark))
      (do (%put! st %mark (%get st %row))
          (edit-message! st (Str8 append "Loop from row " (Str8 str (%get st %row)) ": L on its last row plays it, Escape forgets.")))
      (%loop! st (%get st %mark) (%get st %row)))))

; Tension (WHAT tension), pace or volume moved by BY, kept from LEAST
; to MOST, and heard at once.
(def %nudge!
  (fn (_ st what by least most)
    (def p (%get st %player))
    (if (null? p) (edit-message! st %no-sound)
      (do (def now (match ((str=? what "Tension") (player-tension p)) ((str=? what "Pace") (player-pace p)) (#t (player-volume p))))
          (def n (%max least (%min most (+ now by))))
          (match ((str=? what "Tension") (player-tension! p n)) ((str=? what "Pace") (player-pace! p n)) (#t (player-volume! p n)))
          (edit-message! st (Str8 append what " " (Str8 str n) (if (str=? what "Tension") "" "%") "."))))))

; Channel X (KIND channel) or instrument X muted, or soloed when SOLO,
; or heard again when it was.
(def %hush!
  (fn (_ st kind x solo)
    (def p (%get st %player))
    (def what (if (eq? kind (lit channel)) (Str8 append "Channel " (Str8 str x)) (Str8 append "Instrument " x)))
    (if (null? p) (edit-message! st %no-sound)
      ((fn (_ e)
         (edit-message! st
           (match ((not (null? e)) e)
                  (solo (Str8 append what (if (player-soloed? p kind x) " soloed." " no longer soloed.")))
                  (#t (Str8 append what (if (player-muted? p kind x) " muted." " heard again."))))))
       (guard (e (if (Err err? e) (e msg) "the song cannot be played"))
         (do (if solo (player-solo! p kind x) (player-mute! p kind x)) ()))))))

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

; What is muted and soloed: the pattern's channels and the song's
; instruments.
(def %hush-text
  (fn (_ st)
    (def p (%get st %player))
    (def chans (List range 0 (List length (%channels st))))
    (def insts (song-instruments (edit-song st)))
    (def part
      (fn (_ word ask)
        (def cs (List filter (fn (_ i) (ask p (lit channel) i)) chans))
        (def ins (List filter (fn (_ i) (ask p (lit instrument) i)) insts))
        (if (if (null? cs) (null? ins) #f) ""
          (Str8 append word ": " (Str8 join " " (List append (List map (fn (_ i) (Str8 append "channel " (Str8 str i))) cs) ins)) ".  "))))
    (if (null? p) %no-sound
      ((fn (_ text) (if (str=? text "") "Nothing is muted or soloed." (Str8 trim text)))
       (Str8 append (part "Muted" player-muted?) (part "Soloed" player-soloed?))))))

; M:SS for FRAMES at the mixer's rate.
(def %frames-text
  (fn (_ frames)
    (def secs (int/ frames 44100))
    (Str8 append (Str8 str (int/ secs 60)) ":" (Str8 pad-left 2 #\0 (Str8 str (int% secs 60))))))

; The song played once through to a WAV file at PATH, as it would be
; heard: what the player mutes, its tension, pace and volume.  The song
; playing is stopped first: rendering keeps the loop from feeding it.
(def %render!
  (fn (_ st path)
    (def p (%get st %player))
    (unless (null? p) (when (player-playing? p) (do (player-stop! p) (%put! st %heard ()))))
    (edit-message! st
      (guard (e (if (Err err? e) (e msg) "the song cannot be rendered"))
        (Str8 append "Rendered " path ": "
          (%frames-text (player-render! (if (null? p) (player-open () (file-waves (%get st %doc))) p) (edit-song st) path))
          ".")))))

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
                  (do (config-backup! (%get st %config) to)
                      (%put! st %doc (file-write! (%get st %doc) to)) ())))))))

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

; :set lists the settings; :set NAME VALUE ... changes one for the
; session.  The octave, the step and following are the editor's own as
; well, changed by keys too.
(def %set-cmd!
  (fn (_ st args)
    (def cfg (%get st %config))
    (config-put! cfg (lit octave) (%get st %octave))
    (config-put! cfg (lit step) (%get st %step))
    (config-put! cfg (lit follow) (%get st %follow))
    (if (null? args) (%put! st %help (config-lines cfg))
      ((fn (_ why)
         (if (not (null? why)) (edit-message! st why)
           (do (%put! st %octave (config-get cfg (lit octave)))
               (%put! st %step (config-get cfg (lit step)))
               (%put! st %follow (config-get cfg (lit follow)))
               (edit-message! st (Str8 append "Set: " (Str8 join " " args))))))
       (config-set-text! cfg (Str8 join " " args))))))

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
      ((str=? cmd "volume")
        (%number-cmd! st args 0 100 (fn (_ n) (if (null? (%get st %player)) (edit-message! st %no-sound) (player-volume! (%get st %player) n)))))
      ((List includes? cmd (list "mute" "solo"))
        (match ((null? args) (edit-message! st (%hush-text st)))
               ((not (List includes? (first args) (song-instruments s))) (edit-message! st (Str8 append "No instrument " (first args) ".")))
               (#t (%hush! st (lit instrument) (first args) (str=? cmd "solo")))))
      ((str=? cmd "unmute")
        (if (null? (%get st %player)) (edit-message! st %no-sound)
          (do (player-unmute! (%get st %player)) (edit-message! st "Every channel and instrument heard."))))
      ((str=? cmd "loop")
        (match ((null? args) (if (null? (%get st %player)) (edit-message! st %no-sound) (%start! st (lit pattern) 0 () #f "Looping the whole pattern.")))
               ((not (= (List length args) 2)) (edit-message! st ":loop FROM TO   rows of the pattern, played over and over"))
               ((if (null? (%num (first args))) #t (if (null? (%num (List ref 1 args))) #t (< (%min (%num (first args)) (%num (List ref 1 args))) 0)))
                 (edit-message! st "Rows are numbers from 0."))
               ((null? (%get st %pattern)) (edit-message! st "No pattern."))
               (#t (%loop! st (%num (first args)) (%num (List ref 1 args))))))
      ((str=? cmd "render")
        (if (null? args) (edit-message! st ":render FILE   the song played once, to a WAV file")
          (%render! st (Str8 join " " args))))
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
      ((str=? cmd "set") (%set-cmd! st args))
      ((str=? cmd "rename")
        (if (null? args) (edit-message! st ":rename NAME") (%change! st (song-rename s (Str8 join " " args)))))
      (#t (edit-message! st (Str8 append "No command " cmd ": ? lists them."))))))

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

; A key pressed: taken as the key of the action it is bound to, but in a
; line being typed (tracker/config).
(def edit-key!
  (fn (_ st typed)
    (def key (if (null? (%get st %input)) (config-key (%get st %config) typed) typed))
    (match
      ((null? key) ())
      ((not (null? (%get st %input))) (%input-key! st key))
      ((not (null? (%get st %pick))) (%pick-key! st key))
      ((%get st %help) (%put! st %help #f))
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
      ((%is? key "(") (%nudge! st "Tension" -10 0 100))
      ((%is? key ")") (%nudge! st "Tension" 10 0 100))
      ((%is? key "_") (%nudge! st "Pace" -10 10 400))
      ((%is? key "+") (%nudge! st "Pace" 10 10 400))
      ((%is? key "9") (%nudge! st "Volume" -10 0 100))
      ((%is? key "0") (%nudge! st "Volume" 10 0 100))
      ((if (eq? key (lit escape)) (not (null? (%get st %mark))) #f) (do (%put! st %mark ()) (edit-message! st "")))
      ((null? (%get st %pattern)) (edit-message! st "The song has no pattern: :pattern NAME makes one."))
      ((%is? key "P") (%play-here! st))
      ((%is? key "L") (%loop-key! st))
      ((%is? key "M") (%hush! st (lit channel) (%get st %chan) #f))
      ((%is? key "S") (%hush! st (lit channel) (%get st %chan) #t))
      ((%is? key "H") (%hush! st (lit instrument) (first (List ref (%get st %chan) (%channels st))) #f))
      ((%is? key "O") (%hush! st (lit instrument) (first (List ref (%get st %chan) (%channels st))) #t))
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
      ((%is? key "I") (%set-channels! st (pattern-insert-row (%channels st) (%get st %row))))
      ((%is? key "D") (%set-channels! st (pattern-delete-row (%channels st) (%get st %row))))
      ((if (%is? key ".") #t (if (eq? key (lit backspace)) #t (eq? key (lit delete)))) (%put-cell! st "."))
      ((%is? key "-") (%put-cell! st "-"))
      ((if (str? key) (not (null? (%str-entry key %piano))) #f) (%note! st (rest (%str-entry key %piano))))
      (#t ()))))

; --- drawing -----------------------------------------------------------------

; The style the setting colour NAME gives (tracker/config): looked up
; once a drawing, not once a cell.
(def %style (fn (_ st name) (config-style (%get st %config) name)))

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
        "  P   play from the cursor's row      L   loop rows: L on the first, L on the last"
        "  M S   mute, solo the channel        H O   mute, solo its instrument"
        "  ( )   tension     _ +   pace     9 0   volume"
        "  F   follow the playing, or stop following"
        "  U R   undo, redo     ?   this     ctrl-c   quit"
        "Commands"
        "  :w [FILE]  :q  :q!  :wq            :song [NAME]  :rename NAME"
        "  :bpm N  :rows N  :ticks N  :tension-bpm N  :len N"
        "  :pattern NAME  :order NAME ...  :channel INSTRUMENT  :drop"
        "  :instrument NAME PROP ...  :octave N  :step N  :tension N  :pace N"
        "  :waves  list them   :waves keep   copy the borrowed in   :wave NAME AMP ..."
        "  :mute [INSTRUMENT]  :solo [INSTRUMENT]  :unmute  :loop [FROM TO]  :volume N"
        "  :render FILE   the song played once, to a WAV file"
        "  :set  list the settings   :set NAME VALUE ...  change one: octave step follow"
        "        backup undo, colour NAME ATTRIBUTES FG BG, key ACTION KEY ..."
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
  (fn (_ st screen lines top high hi)
    (def h (%max 1 (- high 1)))
    (def body (rest lines))
    (def cols (Screen cols screen))
    (def w (+ 2 (List fold (fn (_ m l) (%max m (Str8 length l))) 0 body)))
    (def heading (%style st (lit heading)))
    (def cursor (%style st (lit cursor)))
    (def style (fn (_ l) (if (< 0 (Str8 length l)) (if (Str8 starts? " " l) 0 heading) 0)))
    (Screen put screen top 0 (first lines) (style (first lines)))
    (List fold
      (fn (_ i l)
        (%put-text! screen cols (+ (+ top 1) (int% i h)) (* w (int/ i h)) l (if (%same? i hi) cursor (style l)))
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
             ((null? (player-loop p)) "   > pattern")
             (#t (Str8 append "   > rows " (Str8 str (first (player-loop p))) "-" (Str8 str (rest (player-loop p))))))
      (if (null? p) ""
        (Str8 append
          (if (= 0 (player-tension p)) "" (Str8 append "  tension " (Str8 str (player-tension p))))
          (if (= 100 (player-pace p)) "" (Str8 append "  pace " (Str8 str (player-pace p)) "%"))
          (if (= 100 (player-volume p)) "" (Str8 append "  volume " (Str8 str (player-volume p)) "%")))))))

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
                      (if (%same? i (%get st %at)) (Str8 append "[" mark "]") mark))
            (List range 0 (List length order)))))
      (if (if (null? (%get st %at)) (not (null? (%get st %pattern))) #f)
        (Str8 append "   editing " (%get st %pattern) ", not in the order") ""))))

; Whether S has a / from byte I on.
(def %slash?
  (fn (self s i) (if (int< i (str-byte-len s)) (if (int= (str-byte-ref s i) 47) #t (self s (int+ i 1))) #f)))

(def %cell-style
  (fn (_ cell empty off effect)
    (def b (if (int< 0 (str-byte-len cell)) (str-byte-ref cell 0) 0))
    (match ((if (int= b 46) (int= 1 (str-byte-len cell)) #f) empty)
           ((int= b 45) off)
           ((%slash? cell 0) effect)
           (#t 0))))

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
    (def empty (%style st (lit empty)))
    (def off (%style st (lit off)))
    (def effect (%style st (lit effect)))
    (def cursor (%style st (lit cursor)))
    (def playing (%style st (lit playing)))
    (def on-beat (%style st (lit beat)))
    ((fn (self cs k)
       (unless (null? cs)
         (do (%put-text! screen cols top (int+ 5 (* w k)) (%pad (int- w 1) (first (first cs))) (%heading-style st (int+ left k) (first (first cs))))
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
               (if (if (int= r cur-row) (int= k cur-chan) #f) cursor (%cell-style cell empty off effect)))
             (self y r (rest cs) (int+ k 1) (pair (if (null? cells) () (rest cells)) acc)))
           (first cs)))))
    (def rev (fn (self xs acc) (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))
    ((fn (self y cs)
       (def r (int+ first-row y))
       (when (if (int< y shown) (int< r rows) #f)
         (do (%put-text! screen cols (int+ (int+ top 1) y) 0 (Str8 pad-left 3 #\space (Str8 str r))
               (if (%same? r heard) playing (if (int= 0 (int% r beat)) on-beat empty)))
             (when (%same? r heard) (%put-text! screen cols (int+ (int+ top 1) y) 3 ">" playing))
             (self (int+ y 1) (rev (put-row! y r cs 0 ()) ())))))
     0 (List map (fn (_ ch) (List drop first-row (rest ch))) shown-chs))))

(def edit-draw!
  (fn (_ st screen)
    (Screen clear screen)
    (def rows (Screen rows screen))
    (def cols (Screen cols screen))
    (Screen fill screen 0 0 cols (%style st (lit title)))
    (Screen put screen 0 0 (%title st) (%style st (lit title)))
    (Screen put screen 1 0 (%order-line st) 0)
    (match
      ((%get st %help) (%draw-panel! st screen (%get st %help) 2 (- rows 3) (%get st %pick)))
      ((null? (%get st %pattern)) (Screen put screen 3 1 "The song has no pattern: :pattern NAME makes one." 0))
      (#t (%draw-grid! st screen 3 (- rows 2))))
    (def input (%get st %input))
    (match
      ((null? input)
        (Screen put screen (- rows 1) 0
          (if (str=? (%get st %msg) "") " ? keys   Space play   p pattern   : command" (Str8 append " " (%get st %msg)))
          (if (str=? (%get st %msg) "") (%style st (lit empty)) 0)))
      (#t ((fn (_ prompt)
             (Screen put screen (- rows 1) 0 (Str8 append prompt (rest input)) 0)
             (Screen cursor screen (- rows 1) (%min (- cols 1) (+ (Str8 length prompt) (Str8 length (rest input))))))
           (match ((eq? (first input) (lit command)) ":")
                  ((eq? (first input) (lit cell)) "cell: ")
                  (#t "instrument: ")))))
    st))

(provide tracker/edit edit-make edit-song edit-doc edit-quit? edit-message edit-message! edit-player edit-place
  edit-feed! edit-settle! edit-tick! edit-key! edit-draw!)
