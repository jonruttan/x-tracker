; # x-tracker -- a music tracker on x-lang
;
; ## tracker/edit.x -- the editor: what its keys and commands do
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
; The state is tracker/state's, drawn by tracker/draw.  The document is never
; changed in place (tracker/file, tracker/song): a change makes a new one,
; and the old is kept to undo to.

(module tracker/edit)

(import x/type/vector)
(import x/codec/xon)
(import x/tui/screen)
(import x/core/doors int/ int% int+ int- int< int= str-byte-len str-byte-ref str-byte-sub str->sym)
(import tracker/song song-new song-name song-rename song-patterns song-pattern song-order song-prop
  song-instruments song-instrument-text song-waves song-set-pattern song-set-order song-set-prop song-set-instrument
  pattern-rows pattern-cell pattern-set-cell pattern-resize pattern-insert-row pattern-delete-row
  pattern-add-channel pattern-drop-channel song-cell-problem song-effects song-set-effect song-drop-effect
  song-copy-instrument song-rename-instrument song-drop-instrument song-instrument-uses song-rename-pattern
  song-drop-pattern pattern-set-instrument pattern-move-channel pattern-block pattern-paste pattern-map-block
  cell-transpose cell-gain pattern-insert-rows pattern-delete-rows pattern-slide pattern-stretch)
(import tracker/file file-songs file-song! file-add-song file-drop-song file-changed? file-write! file-waves file-wave-clash file-wave file-set-wave file-sample? file-sample-at file-dir file-form-text)
(import tracker/player player-playing? player-mode player-start! player-stop! player-update! player-preview!
  player-pump! player-place player-tension! player-pace! player-waves player-waves! player-wave? player-open player-give!
  player-start-at! player-tension player-pace player-volume player-volume! player-hears? player-mute! player-solo!
  player-muted? player-soloed? player-unmute! player-loop! player-loop player-order-loop! player-render! player-pcm player-pcm! player-edited player-wav
  player-pattern)
(import tracker/sample sample-copy sample-cut sample-resample sample-reverse sample-invert sample-centre sample-normalise
  sample-amplify sample-silence sample-fade sample-peak sample-write! sample-setting sample-set-setting sample-loop sample-set-loop)
(import tracker/help help-index help-topic help-topics help-on)
(import tracker/cell cell-parts cell-join cell-note?)
(import tracker/field field-make field-kind field-line field-key! field-history field-remember! history-kind history-read history-of history-put history-add!)
(import tracker/config config-default config-set-text! config-get config-put! config-style config-key config-lines
  config-backup!)
(import tracker/state %blanks %pad %doc %path %song %pattern %at %row %chan %top %left %octave %step %msg %input %undo %redo %player %quit %help %warned %heard %follow %pick %stale %borrowed %config %order-at %mark %clip %loop-at %browse %page %field %digit %mark-end %inst-at %env-at %env-held %setting-at %sample-at %sample-field %sample-cache %sample-peaks %paused %targets %drag %input-at %midi-held %order-loop %order-loop-at %history %history-path %slots %get %put! %max %min %same? %num edit-song edit-doc edit-quit? edit-message edit-message! edit-player edit-place %channels %rows %block %style %target! %browse-hint )


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
    ; The place in the order kept to the pattern edited: still its place
    ; when the order there still plays it, else its first place, or nil
    ; when the order has none of it.
    ((fn (_ order at name)
       (unless (if (null? at) #f (if (< at (List length order)) (str=? (List ref at order) name) #f))
         (%put! st %at (if (null? name) () (List index-of name order)))))
     (song-order (edit-song st)) (%get st %at) (%get st %pattern))
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
    (%put! st %mark ()) (%put! st %mark-end ()) (%put! st %order-at ())
    (%put! st %field 0) (%put! st %digit ())
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
    (%put! st %page (lit pattern))
    (%put! st %inst-at 0)
    (%put! st %setting-at 0)
    (%put! st %sample-at 0)
    (%put! st %env-held #f)
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

; Where the editor is, to undo to: (DOC SONG PATTERN SOUNDS), SOUNDS the
; sounds an edit of them changed, ((NAME SOUND) ...), each as it was.
(def %here (fn (_ st . sounds) (list (%get st %doc) (%get st %song) (%get st %pattern) (if (null? sounds) () (first sounds)))))

; ENTRY the newest step of undo, as deep as (undo N), and nothing to redo.
(def %remember!
  (fn (_ st entry)
    (%put! st %undo (pair entry (List take (- (config-get (%get st %config) (lit undo)) 1) (%get st %undo))))
    (%put! st %redo ())))

; The document's waves, each sample's file named from the file's directory.
(def %doc-waves
  (fn (_ st)
    (if (null? (%get st %path)) (file-waves (%get st %doc)) (file-waves (%get st %doc) (file-dir (%get st %path))))))

; The mixer given the document's waves, and the borrowed ones it does
; not have, as they were: after a change or an undo of one.  Two waves
; that make one name differently are told, the first heard.
(def %sync-waves!
  (fn (_ st)
    (def doc (%get st %doc))
    ((fn (_ m) (unless (null? m) (edit-message! st m))) (file-wave-clash doc))
    (unless (null? (%get st %player))
      (player-waves! (%get st %player)
        (List append (List filter (fn (_ w) (null? (file-wave doc (symbol->str (List ref 1 w))))) (%get st %borrowed))
          (%doc-waves st))))))

; The document made DOC: the old one kept to undo to.
(def %doc-change!
  (fn (_ st doc)
    (%remember! st (%here st))
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

; The sample named NAME of the song, or nil.
(def %sample-named (fn (_ st name) (List find (fn (_ w) (eq? (List ref 1 w) name)) (%samples st))))

; The sounds named in SOUNDS, ((NAME SOUND) ...), as they are now.
(def %sounds-now
  (fn (_ st sounds)
    (List map (fn (_ e) (list (first e) ((fn (_ w) (if (null? w) () (%sound st w))) (%sample-named st (first e))))) sounds)))

; One step of undo, FROM the list taken from and TO the list given to:
; back in the song the step was made in, and the sounds it changed
; heard as they were.
(def %undo-step!
  (fn (_ st from to what)
    (if (null? (%get st from)) (edit-message! st (Str8 append "Nothing to " what "."))
      (do (def back (first (%get st from)))
          (def sounds (List ref 3 back))
          (%put! st to (pair (%here st (%sounds-now st sounds)) (%get st to)))
          (%put! st %doc (first back))
          (unless (= (List ref 1 back) (%get st %song)) (%go-song! st (List ref 1 back)))
          (%put! st %pattern (List ref 2 back))
          (%put! st from (rest (%get st from)))
          (edit-message! st "")
          (%sync-waves! st)
          (List for-each
            (fn (_ e)
              ((fn (_ w)
                 (unless (if (null? w) #t (null? (List ref 1 e)))
                   (do (player-pcm! (first e) (%sample-args st w) (List ref 1 e))
                       (%put! st %sample-peaks ())
                       (edit-message! st (Str8 append (if (str=? what "undo") "Undone" "Redone") ": the sound of " (%wave-name w) ".")))))
               (%sample-named st (first e))))
            sounds)
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
; DONE, or why it cannot be played.  The song plays from PLACE when given,
; else from the place edited.
(def %start!
  (fn (_ st mode row range toggle done . place)
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
                 (player-order-loop! p (%get st %order-loop))
                 (player-start-at! p (edit-song st) mode (if (pair? place) (first place) (if (null? (%get st %at)) 0 (%get st %at))) (%get st %pattern) row)
                 ())))))))

; The song from the loop's first place when the order is looped, else
; from the place edited; or the pattern edited.
(def %play!
  (fn (_ st mode)
    (if (if (eq? mode (lit song)) (pair? (%get st %order-loop)) #f)
      (%start! st mode 0 () #t "" (first (%get st %order-loop)))
      (%start! st mode 0 () #t ""))))

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
    (%put! st %loop-at ())
    (%start! st (lit pattern) from (pair from to) #f
      (Str8 append "Looping rows " (Str8 str from) " to " (Str8 str to) ": p plays the whole pattern."))))

; L: the cursor's row marked as a loop's first, or with a row marked,
; the rows from it to the cursor's looped.
(def %loop-key!
  (fn (_ st)
    (if (null? (%get st %loop-at))
      (do (%put! st %loop-at (%get st %row))
          (edit-message! st (Str8 append "Loop from row " (Str8 str (%get st %row)) ": L on its last row plays it, Escape forgets.")))
      (%loop! st (%get st %loop-at) (%get st %row)))))

; Places A to B of the order, either way round, played over and over
; from the first.
(def %order-loop!
  (fn (_ st a b)
    (def n (List length (song-order (edit-song st))))
    (def from (%min (%min a b) (- n 1)))
    (def to (%min (%max a b) (- n 1)))
    (%put! st %order-loop (pair from to))
    (%put! st %order-loop-at ())
    (%start! st (lit song) 0 () #f
      (Str8 append "Looping places " (Str8 str from) " to " (Str8 str to) " of the order: L on F11 or :loop order stops it.")
      from)))

; The order played through again; a song playing plays on from where it
; is heard.
(def %order-loop-off!
  (fn (_ st)
    (def p (%get st %player))
    (%put! st %order-loop ())
    (%put! st %order-loop-at ())
    (if (if (null? p) #f (if (player-playing? p) (eq? (player-mode p) (lit song)) #f))
      ((fn (_ heard) (%start! st (lit song) (rest heard) () #f "The whole order is played." (first heard))) (player-place p))
      (edit-message! st "The whole order is played."))))

; L on F11: the order loop stopped, or the place picked marked as its
; first, or with a place marked, the places from it to the one picked
; looped.
(def %order-loop-key!
  (fn (_ st)
    (match
      ((pair? (%get st %order-loop)) (%order-loop-off! st))
      ((null? (%get st %order-loop-at))
        (do (%put! st %order-loop-at (%get st %order-at))
            (edit-message! st (Str8 append "Loop from place " (Str8 str (%get st %order-at)) ": L on its last place plays it, Escape forgets."))))
      (#t (%order-loop! st (%get st %order-loop-at) (%get st %order-at))))))

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
          (%frames-text (player-render! (if (null? p) (player-open () (%doc-waves st)) p) (edit-song st) path))
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
    (def edited (List filter (fn (_ w) (List includes? (List ref 1 w) (player-edited))) (%samples st)))
    (match
      ((if force #t (%get st %warned)) (%put! st %quit #t))
      ((file-changed? (%get st %doc))
        (do (%put! st %warned #t) (edit-message! st "The song has changed: :w writes it, :q! leaves without.")))
      ((not (null? edited))
        (do (%put! st %warned #t)
            (edit-message! st (Str8 append "The sound of " (%wave-name (first edited)) " is edited: Alt-O on F3 writes it, :q! leaves without."))))
      (#t (%put! st %quit #t)))))

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

; Whether the wave named NAME is one the mixer has of its own: one it has
; that the player did not give it.
(def %mixer-own?
  (fn (_ st name)
    (def p (%get st %player))
    (if (player-wave? name)
      (not (List any? (fn (_ w) (str=? (%wave-name w) name)) (if (null? p) () (player-waves p))))
      #f)))

; Where the wave named NAME comes from, and its harmonics.
(def %wave-source
  (fn (_ st name)
    (def mine (file-wave (%get st %doc) name))
    (def theirs (%borrowed-wave st name))
    (match ((not (null? mine)) (Str8 append "in the file      " (%amps-text mine)))
           ((not (null? theirs)) (Str8 append "borrowed (-w)    " (%amps-text theirs)))
           ((%mixer-own? st name) "the mixer's own")
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
      ((%mixer-own? st (first args)) (edit-message! st (Str8 append (first args) " is the mixer's own.")))
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
      ((if (str=? cmd "loop") (if (pair? args) (str=? (first args) "order") #f) #f)
        (match ((null? (rest args)) (%order-loop-off! st))
               ((not (= (List length args) 3)) (edit-message! st ":loop order FROM TO   places of the order, played over and over"))
               ((if (null? (%num (List ref 1 args))) #t (if (null? (%num (List ref 2 args))) #t (< (%min (%num (List ref 1 args)) (%num (List ref 2 args))) 0)))
                 (edit-message! st "Places are numbers from 0, as F11 shows them."))
               ((null? (song-order s)) (edit-message! st "The song has no order: :order NAME ..."))
               (#t (%order-loop! st (%num (List ref 1 args)) (%num (List ref 2 args))))))
      ((str=? cmd "page") (%page-command! st (Str8 join " " args)))
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
               (do (%remember! st (%here st))
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
      ((str=? cmd "sample") (%sample-cmd! st args))
      ((str=? cmd "sound") (%sound-cmd! st args))
      ((str=? cmd "open") (%open-cmd! st args))
      ((str=? cmd "amplify")
        (if (null? (%get st %pattern)) (edit-message! st "No pattern.")
          (%number-cmd! st args 0 400 (fn (_ n) (%map-block! st (fn (_ c) (%amplified c n)))))))
      ((str=? cmd "set") (%set-cmd! st args))
      ((str=? cmd "help") (%help-cmd! st args))
      ((str=? cmd "rename")
        (if (null? args) (edit-message! st ":rename NAME") (%change! st (song-rename s (Str8 join " " args)))))
      ((List includes? cmd (list "effects" "effect" "instruments" "copy-instrument" "rename-instrument" "drop-instrument"
                                 "patterns" "copy-pattern" "rename-pattern" "drop-pattern" "copy-song" "drop-song"
                                 "channel-instrument" "transpose" "gain"))
        (%edit-cmd! st cmd args line))
      (#t (edit-message! st (Str8 append "No command " cmd ": :help commands lists them."))))))

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
               (do (%remember! st (%here st))
                   (%put! st %doc (file-add-song (%get st %doc) (song-rename s name)))
                   (%go-song! st (- (List length (file-songs (%get st %doc))) 1))
                   (edit-message! st (Str8 append "Copied to " name ".")))))
           (Str8 join " " args))))
      ((str=? cmd "drop-song")
        (if (< (List length (file-songs (%get st %doc))) 2) (edit-message! st "A file keeps one song.")
          ((fn (_ name)
             (%remember! st (%here st))
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

; --- the pattern editor's fields ------------------------------------------------

; The cursor moved D fields: past a channel's effect to the next
; channel's note, before its note to the last one's effect.
(def %field-move!
  (fn (_ st d)
    (def n (List length (%channels st)))
    (def at (+ (+ (* 4 (%get st %chan)) (%get st %field)) d))
    (def to (%max 0 (%min (- (* 4 n) 1) at)))
    (%put! st %digit ())
    (%put! st %chan (int/ to 4))
    (%put! st %field (int% to 4))))

; The cell at the cursor's parts (tracker/cell) made F of them, the
; cell's text checked; the cursor moved on by the step when MOVE.
(def %parts-change!
  (fn (_ st f move)
    (def p (cell-parts (%cell st)))
    (def text ((fn (_ q) (cell-join (first q) (List ref 1 q) (List ref 2 q))) (f p)))
    (def why (song-cell-problem text))
    (if (not (null? why)) (edit-message! st why)
      (do (%set-channels! st (pattern-set-cell (%channels st) (%get st %chan) (%get st %row) text))
          (when move (%move! st (%get st %step)))))))

; A digit typed in the instrument or the volume column: the first of two
; is held, the second makes the number.  The volume is the note's gain,
; 0 to 99, in percent of its instrument's; the instrument, from 01, is
; the channel's: x-tracker plays a channel with one instrument.
(def %digit!
  (fn (_ st d)
    (def held (%get st %digit))
    (def field (%get st %field))
    (if (null? held)
      (do (%put! st %digit (* 10 d))
          (edit-message! st (Str8 append (if (= field 1) "Instrument " "Volume ") (Str8 str d) "_")))
      (do (%put! st %digit ())
          (edit-message! st "")
          (def n (+ held d))
          (if (= field 2)
            (if (cell-note? (first (cell-parts (%cell st))))
              (%parts-change! st (fn (_ p) (list (first p) n (List ref 2 p))) #t)
              (edit-message! st "A volume is a note's: type a note first."))
            ((fn (_ names)
               (if (if (< 0 n) (not (< (List length names) n)) #f)
                 (do (%set-channels! st (pattern-set-instrument (%channels st) (%get st %chan) (List ref (- n 1) names)))
                     (edit-message! st (Str8 append "Channel " (Str8 str (+ 1 (%get st %chan))) " plays " (List ref (- n 1) names)
                                         ", every row: x-tracker plays a channel with one instrument.")))
                 (edit-message! st (Str8 append "No instrument " (Str8 str n) ": F4 lists them."))))
             (song-instruments (edit-song st))))))))

; A key in the effect column: Enter, or a letter starting one, edits the
; cell's effects as text, each a letter and its numbers, apart by /.
(def %effect-key!
  (fn (_ st key)
    (def now (Str8 join "/" (List ref 2 (cell-parts (%cell st)))))
    (%put! st %input (pair (lit effects) (if (eq? key (lit enter)) now (if (str=? now "") key (Str8 append now "/" key)))))))

; --- blocks -------------------------------------------------------------------

; The block's corner at the cursor: Alt-B its first, Alt-E its last.
; Either alone marks the cursor's cell; a block whose last corner is not
; set follows the cursor.
(def %mark-at! (fn (_ st) (pair (%get st %row) (%get st %chan))))

(def %block-begin!
  (fn (_ st)
    (%put! st %mark (%mark-at! st))
    (when (null? (%get st %mark-end)) (%put! st %mark-end (%mark-at! st)))
    (%block-said! st)))

(def %block-end!
  (fn (_ st)
    (when (null? (%get st %mark)) (%put! st %mark (%mark-at! st)))
    (%put! st %mark-end (%mark-at! st))
    (%block-said! st)))

(def %block-said!
  (fn (_ st)
    (def b (%block st))
    (edit-message! st (Str8 append "Block: rows " (Str8 str (first b)) " to " (Str8 str (List ref 1 b)) ", channels "
                        (Str8 str (+ 1 (List ref 2 b))) " to " (Str8 str (+ 1 (List ref 3 b)))
                        "   Alt-C copy  Alt-Z cut  Alt-P paste  Alt-Q Alt-A transpose  Alt-U unmark"))))

(def %unmark! (fn (_ st) (%put! st %mark ()) (%put! st %mark-end ()) (edit-message! st "")))

; Shift and an arrow: the block from where the cursor was, to where it goes.
(def %shift-move!
  (fn (_ st f)
    (when (null? (%get st %mark)) (%put! st %mark (%mark-at! st)))
    (f)
    (%put! st %mark-end (%mark-at! st))
    (%block-said! st)))

; Alt-L: the cursor's channel, then again the whole pattern.
(def %mark-column!
  (fn (_ st)
    (def whole (if (null? (%get st %mark)) #f
                 (if (= 0 (first (%get st %mark)))
                   (if (= (rest (%get st %mark)) (%get st %chan)) (= (rest (%get st %mark-end)) (%get st %chan)) #f) #f)))
    (if whole
      (do (%put! st %mark (pair 0 0)) (%put! st %mark-end (pair (- (%rows st) 1) (- (List length (%channels st)) 1))))
      (do (%put! st %mark (pair 0 (%get st %chan))) (%put! st %mark-end (pair (- (%rows st) 1) (%get st %chan)))))
    (%block-said! st)))

; Alt-D: the beat's rows from the cursor, then twice as many each again.
(def %quick-mark!
  (fn (_ st)
    (def beat (%max 1 (song-prop (edit-song st) "rows" 4)))
    (def m (%get st %mark))
    (def again (if (null? m) #f (if (= (first m) (%get st %row)) (= (rest m) (%get st %chan)) #f)))
    (def n (if again (* 2 (+ 1 (- (first (%get st %mark-end)) (first m)))) beat))
    (%put! st %mark (%mark-at! st))
    (%put! st %mark-end (pair (%min (- (%rows st) 1) (+ (%get st %row) (- n 1))) (%get st %chan)))
    (%block-said! st)))

; The clipboard put at the cursor: over what is there (OVER), or mixed
; into its holds (MIX), or the rows below moved down (neither), in the
; channels it covers.
(def %paste!
  (fn (_ st how)
    (def clip (%get st %clip))
    (def c (%get st %chan)) (def r (%get st %row))
    (def chs (%channels st))
    (if (null? clip) (edit-message! st "Nothing copied: Alt-B and Alt-E mark a block, Alt-C copies it.")
      (%set-channels! st
        (match ((eq? how (lit over)) (pattern-paste chs c r clip))
               ((eq? how (lit mix))
                 (pattern-paste chs c r
                   (List map (fn (_ k) (List map (fn (_ j) ((fn (_ now new) (if (str=? now ".") new now))
                                                            (pattern-cell chs (+ c k) (+ r j)) (List ref j (List ref k clip))))
                                         (List range 0 (List length (List ref k clip)))))
                     (List range 0 (%min (List length clip) (- (List length chs) c))))))
               (#t (pattern-paste (pattern-insert-rows chs c (+ c (- (List length clip) 1)) r (List length (first clip))) c r clip)))))))

; The block's notes' gains, or its cells' first effects' numbers, slid
; from the first row's to the last's over the rows between: Alt-K, Alt-X.
(def %interpolate!
  (fn (_ st what)
    (def b (%block st))
    (if (= (first b) (List ref 1 b)) (edit-message! st "Mark a block of more than one row to slide across.")
      (%set-channels! st
        (List fold (fn (_ chs c) (pattern-slide chs c (first b) (List ref 1 b) what))
          (%channels st) (List range (List ref 2 b) (+ (List ref 3 b) 1)))))))

; The block made twice as long, or half, from its first row: Alt-F, Alt-G.
(def %stretch!
  (fn (_ st twice)
    (def b (%block st))
    (def n (+ (- (List ref 1 b) (first b)) 1))
    (%set-channels! st
      (List fold (fn (_ chs c) (pattern-stretch chs c (first b) (List ref 1 b) twice))
        (%channels st) (List range (List ref 2 b) (+ (List ref 3 b) 1))))
    ; The block keeps the rows it now fills.
    (unless (null? (%get st %mark-end))
      (do (%put! st %mark (pair (first b) (List ref 2 b)))
          (%put! st %mark-end
            (pair (%min (- (%rows st) 1) (+ (first b) (- (if twice (* n 2) (int/ (+ n 1) 2)) 1))) (List ref 3 b)))))))

; --- the pages ------------------------------------------------------------------

; What each page's foot says when it is shown.
(def %page-hints
  (list (pair (lit pattern) "")
        (pair (lit samples) "Samples   up down pick   Tab the settings   Space or the piano hear it   Alt-G I H M B L E F edit   Alt-O write   Ctrl-Z undo")
        (pair (lit instruments) "Instruments   up down pick   Enter edit   Tab its envelope   Space or the piano hear it   F2 the pattern")
        (pair (lit info) "Playing   up down a channel   M S mute, solo it   Enter or G edit the pattern heard   + - the next, previous place   F8 stop")
        (pair (lit orders) "Order   up down pick   left right its pattern   Insert copy   Delete drop   [ ] move   Enter edit")
        (pair (lit song) "Song   up down pick   left right change   Enter type it   F2 the pattern")))

(def %show-page!
  (fn (_ st page)
    (%put! st %page page)
    (%put! st %digit ())
    (when (eq? page (lit orders)) (%put! st %order-at (if (null? (%get st %at)) 0 (%get st %at))))
    (unless (eq? page (lit orders)) (%put! st %order-at ()))
    (edit-message! st "")
    #t))

; The pages, in the order of the row of pages: (PAGE NAME F-KEY
; ALT-KEY), each reached by its F-key, by Alt and its place in the row,
; or by :page NAME.
(def %page-keys
  (list (list (lit help) "help" (lit f1) (lit alt-1)) (list (lit pattern) "pattern" (lit f2) (lit alt-2))
        (list (lit samples) "samples" (lit f3) (lit alt-3)) (list (lit instruments) "instruments" (lit f4) (lit alt-4))
        (list (lit info) "info" (lit f5) (lit alt-5)) (list (lit orders) "order" (lit f11) (lit alt-6))
        (list (lit song) "song" (lit f12) (lit alt-7))))

; PAGE shown: help opens the help, and the info page plays the song as
; F5 does in Schism Tracker.
(def %go-page!
  (fn (_ st page)
    (match ((eq? page (lit help)) (%browse! st 0 0))
           ((eq? page (lit info)) (do (%play-start! st) (%show-page! st page)))
           (#t (%show-page! st page)))
    #t))

; The entry of %page-keys whose F-key or Alt key KEY is, or nil.
(def %page-of-key (fn (_ key) (List find (fn (_ p) (if (eq? key (List ref 2 p)) #t (eq? key (List ref 3 p)))) %page-keys)))

; :page NAME: the page whose name NAME is, or starts with.
(def %page-command!
  (fn (_ st name)
    ((fn (_ e)
       (if (null? e) (edit-message! st (Str8 append ":page " (Str8 join " " (List map (fn (_ p) (List ref 1 p)) %page-keys))))
         (%go-page! st (first e))))
     (if (str=? name "") () (List find (fn (_ p) (Str8 starts? name (List ref 1 p))) %page-keys)))))

; The song played from the start of its order, its first pattern shown.
(def %play-start!
  (fn (_ st)
    (if (null? (song-order (edit-song st))) (edit-message! st "The song has no order: :order NAME ...")
      (do (%goto-at! st 0) (%put! st %row 0) (%start! st (lit song) 0 () #f "")))))

(def %stop!
  (fn (_ st)
    (def p (%get st %player))
    (unless (null? p) (when (player-playing? p) (player-stop! p)))
    (%put! st %heard ())
    (%put! st %paused ())
    (edit-message! st "")))

; The keys every page takes, Impulse Tracker's: the pages on F1 to F5,
; F11 and F12 and Alt-1 to Alt-7, playing on F5 to F8, writing and
; leaving.  Answers whether KEY was one.
(def %global-key!
  (fn (_ st key)
    (def has-pattern (not (null? (%get st %pattern))))
    (match
      ((not (symbol? key)) #f)
      ((pair? (%page-of-key key)) (%go-page! st (first (%page-of-key key))))
      ((eq? key (lit ctrl-f5)) (do (%play-start! st) #t))
      ((eq? key (lit shift-f8)) (do (%pause! st) #t))
      ((eq? key (lit f6)) (do (%start! st (lit pattern) 0 () #f "") #t))
      ((eq? key (lit shift-f6)) (do (%start! st (lit song) 0 () #f "") #t))
      ((eq? key (lit f7)) (do (if has-pattern (%play-here! st) (edit-message! st "The song has no pattern to play.")) #t))
      ((eq? key (lit f8)) (do (%stop! st) #t))
      ((if (eq? key (lit ctrl-s)) #t (eq? key (lit f10))) (do (%write! st ()) #t))
      ((eq? key (lit f9)) (do (%put! st %input (pair (lit command) "open ")) #t))
      ((eq? key (lit ctrl-q)) (do (%quit! st #f) #t))
      ((eq? key (lit ctrl-z)) (do (%undo-step! st %undo %redo "undo") #t))
      ((eq? key (lit ctrl-y)) (do (%undo-step! st %redo %undo "redo") #t))
      ((if has-pattern (eq? key (lit alt-f9)) #f) (do (%hush! st (lit channel) (%get st %chan) #f) #t))
      ((if has-pattern (eq? key (lit alt-f10)) #f) (do (%hush! st (lit channel) (%get st %chan) #t) #t))
      (#t #f))))

; A key on a page other than the pattern's: Escape goes back to it; :,
; ?, Space, U and R are as there.
(def %page-key!
  (fn (_ st key)
    (def page (%get st %page))
    (match
      ((eq? key (lit escape)) (%show-page! st (lit pattern)))
      ((eq? key (lit interrupt)) (%quit! st #f))
      ((%is? key ":") (%put! st %input (pair (lit command) "")))
      ((%is? key "?") (%browse! st 0 0))
      ((%is? key "U") (%undo-step! st %undo %redo "undo"))
      ((%is? key "R") (%undo-step! st %redo %undo "redo"))
      ((eq? page (lit orders)) (%orders-key! st key))
      ((eq? page (lit song)) (%song-page-key! st key))
      ((eq? page (lit instruments)) (%instruments-key! st key))
      ((eq? page (lit samples)) (%samples-key! st key))
      ((eq? page (lit info)) (%info-key! st key))
      (#t ()))))

; The order list: up and down a place, left and right its pattern, the
; keys of O otherwise; Enter edits the pattern there.
(def %orders-key!
  (fn (_ st key)
    (when (null? (%get st %order-at)) (%put! st %order-at 0))
    (match
      ((eq? key (lit up)) (%order-key! st (lit left)))
      ((eq? key (lit down)) (%order-key! st (lit right)))
      ((if (eq? key (lit left)) #t (%is? key "-")) (%order-key! st (lit up)))
      ((if (eq? key (lit right)) #t (%is? key "+")) (%order-key! st (lit down)))
      ((eq? key (lit enter))
        (do (%order-key! st key) (%show-page! st (lit pattern))))
      ((%is? key " ") (%play! st (lit song)))
      ((%is? key "L") (%order-loop-key! st))
      ((if (eq? key (lit escape)) (not (null? (%get st %order-loop-at))) #f) (do (%put! st %order-loop-at ()) (edit-message! st "")))
      (#t (%order-key! st key)))
    (when (if (null? (%get st %order-at)) (eq? (%get st %page) (lit orders)) #f) (%put! st %order-at 0))))

; --- the song page ----------------------------------------------------------------

; The song page's lines: (LABEL VALUE COMMAND STEP), COMMAND the command
; Enter types, STEP what left and right change it by, nil for none.
(def %song-settings
  (fn (_ st)
    (def s (edit-song st))
    (List append
      (list (list "Name" (song-name s) (Str8 append "rename " (song-name s)) ())
            (list "Tempo, beats a minute" (Str8 str (song-prop s "bpm" 90)) "bpm " 1)
            (list "Rows a beat" (Str8 str (song-prop s "rows" 4)) "rows " 1)
            (list "Ticks a row" (Str8 str (song-prop s "ticks" 6)) "ticks " 1)
            (list "Tempo added at full tension" (Str8 str (song-prop s "tension-bpm" 0)) "tension-bpm " 1)
            (list "Octave typed in" (Str8 str (%get st %octave)) "octave " 1)
            (list "Step after a note" (Str8 str (%get st %step)) "step " 1)
            (list "Follow the playing" (if (%get st %follow) "on" "off") "set follow " ()))
      (List map (fn (_ i) (list (Str8 append "Effect " (Str8 str (+ i 1))) (%one-line (List ref i (song-effects s)))
                                (Str8 append "effect " (Str8 str (+ i 1))) ()))
        (List range 0 (List length (song-effects s))))
      (list (list "A new effect" "" "effect (" ())))))

(def %song-page-key!
  (fn (_ st key)
    (def lines (%song-settings st))
    (def at (%min (%get st %setting-at) (- (List length lines) 1)))
    (def line (List ref at lines))
    (def nudge!
      (fn (_ d)
        (if (null? (List ref 3 line)) (when (str=? (first line) "Follow the playing") (%command! st (Str8 append "set follow " (if (%get st %follow) "off" "on"))))
          (%command! st (Str8 append (List ref 2 line) (Str8 str (+ d (%num (List ref 1 line)))))))))
    (match
      ((eq? key (lit up)) (%put! st %setting-at (%max 0 (- at 1))))
      ((eq? key (lit down)) (%put! st %setting-at (%min (- (List length lines) 1) (+ at 1))))
      ((eq? key (lit left)) (nudge! -1))
      ((eq? key (lit right)) (nudge! 1))
      ((eq? key (lit page-up)) (nudge! -10))
      ((eq? key (lit page-down)) (nudge! 10))
      ((eq? key (lit enter))
        (%put! st %input (pair (lit command) (if (null? (List ref 3 line)) (List ref 2 line) (Str8 append (List ref 2 line) (List ref 1 line))))))
      ((if (eq? key (lit delete)) (Str8 starts? "Effect " (first line)) #f)
        (%command! st (Str8 append "effect drop " (Str8 sub 7 (- (Str8 length (first line)) 7) (first line)))))
      ((%is? key " ") (%play! st (lit song)))
      (#t ()))))

; --- the instruments page ---------------------------------------------------------

(def %write-form file-form-text)

; The instrument picked on the instruments page, its name, or nil.
(def %picked-instrument
  (fn (_ st)
    ((fn (_ names) (if (null? names) () (List ref (%min (%get st %inst-at) (- (List length names) 1)) names)))
     (song-instruments (edit-song st)))))

; Instrument NAME's form, (instrument NAME PROP ...).
(def %instrument-form
  (fn (_ st name) (first (Xon parse (song-instrument-text (edit-song st) name)))))

; Its envelope's points, ((MS PCT) ...), or nil for none.
(def %envelope
  (fn (_ form)
    ((fn (_ e) (if (null? e) () (rest e)))
     (List find (fn (_ p) (if (pair? p) (eq? (first p) (lit env)) #f)) (rest (rest form))))))

; Instrument NAME with its envelope made POINTS.
(def %set-envelope!
  (fn (_ st name points)
    (def form (%instrument-form st name))
    (def props (rest (rest form)))
    (def env (pair (lit env) points))
    (def had (List any? (fn (_ p) (if (pair? p) (eq? (first p) (lit env)) #f)) props))
    (def made (List append (list (lit instrument) (List ref 1 form))
                (if had (List map (fn (_ p) (if (if (pair? p) (eq? (first p) (lit env)) #f) env p)) props) (List append props (list env)))))
    (%try! st "not an instrument" (fn (_) (%change! st (song-set-instrument (edit-song st) (%write-form made))) ()))))

; A note of instrument NAME heard, SEMI semitones above the octave's C.
(def %hear-instrument!
  (fn (_ st name semi)
    (unless (null? (%get st %player))
      (%try! st "the note cannot be played"
        (fn (_) (player-preview! (%get st %player) (edit-song st) name (%note-for st semi)) (edit-feed! st) ())))))

; The cells of channels CHANS at the cursor's row heard, each as its
; channel's instrument plays it: 4 the cursor's, 8 the row's.
(def %hear-cells!
  (fn (_ st chans)
    (List for-each
      (fn (_ c)
        (def cell (pattern-cell (%channels st) c (%get st %row)))
        (def note (first (cell-parts cell)))
        (when (if (cell-note? note) (not (null? (%get st %player))) #f)
          (%try! st "the note cannot be played"
            (fn (_) (player-preview! (%get st %player) (edit-song st) (first (List ref c (%channels st))) note) (edit-feed! st) ()))))
      chans)
    (%move! st 1)))

; Point I of instrument NAME's envelope POINTS put at MS and PCT: kept
; between the points either side of it, the first at its time, and
; within 0 to 100%.
(def %put-point!
  (fn (_ st name points i ms pct)
    (def n (List length points))
    (def lo (if (= i 0) 0 (first (List ref (- i 1) points))))
    (def hi (if (= i (- n 1)) 60000 (first (List ref (+ i 1) points))))
    (%set-envelope! st name
      (List update i (list (if (= i 0) (first (List ref 0 points)) (%max lo (%min hi ms))) (%max 0 (%min 100 pct))) points))))

(def %instruments-key!
  (fn (_ st key)
    (def names (song-instruments (edit-song st)))
    (def name (%picked-instrument st))
    (def points (if (null? name) () (%envelope (%instrument-form st name))))
    (def at (%get st %env-at))
    (def n (List length points))
    (def piano (if (str? key) (%str-entry key %piano) ()))
    (def move-point!
      (fn (_ dms dpct)
        (def i (%min at (- n 1)))
        (def p (List ref i points))
        (%put-point! st name points i (+ (first p) dms) (+ (List ref 1 p) dpct))))
    (match
      ((null? name) (when (eq? key (lit enter)) (%put! st %input (pair (lit command) "instrument "))))
      ((eq? key (lit complete))
        (if (null? at) (if (null? points) (edit-message! st "No envelope: Enter edits the instrument, (env (MS PCT) ...).") (%put! st %env-at 0))
          (do (%put! st %env-at ()) (%put! st %env-held #f))))
      ((%is? key " ") (%hear-instrument! st name 0))
      ((not (null? piano)) (%hear-instrument! st name (rest piano)))
      ; The list has the keys.
      ((null? at)
        (match ((eq? key (lit up)) (%put! st %inst-at (%max 0 (- (%min (%get st %inst-at) (- (List length names) 1)) 1))))
               ((eq? key (lit down)) (%put! st %inst-at (%min (- (List length names) 1) (+ (%get st %inst-at) 1))))
               ((eq? key (lit enter)) (%put! st %input (pair (lit instrument) (%one-line (song-instrument-text (edit-song st) name)))))
               ((eq? key (lit insert)) (%put! st %input (pair (lit command) "instrument ")))
               (#t ())))
      ; The envelope has them: a point picked, picked up with Enter and
      ; moved with the arrows, Alt for ten at a time.
      ((eq? key (lit enter)) (%put! st %env-held (not (%get st %env-held))))
      ((if (%get st %env-held) (List includes? key (list (lit left) (lit right) (lit up) (lit down) (lit alt-left) (lit alt-right) (lit alt-up) (lit alt-down))) #f)
        (match ((eq? key (lit left)) (move-point! -1 0)) ((eq? key (lit right)) (move-point! 1 0))
               ((eq? key (lit alt-left)) (move-point! -10 0)) ((eq? key (lit alt-right)) (move-point! 10 0))
               ((eq? key (lit up)) (move-point! 0 1)) ((eq? key (lit down)) (move-point! 0 -1))
               ((eq? key (lit alt-up)) (move-point! 0 10)) (#t (move-point! 0 -10))))
      ((eq? key (lit left)) (%put! st %env-at (%max 0 (- at 1))))
      ((eq? key (lit right)) (%put! st %env-at (%min (- n 1) (+ at 1))))
      ((eq? key (lit insert))
        ((fn (_ i)
           (def p (List ref i points))
           (def q (if (< i (- n 1)) (List ref (+ i 1) points) (list (+ (first p) 50) 0)))
           (%set-envelope! st name (List insert (+ i 1) (list (int/ (+ (first p) (first q)) 2) (int/ (+ (List ref 1 p) (List ref 1 q)) 2)) points))
           (%put! st %env-at (+ i 1)))
         (%min at (- n 1))))
      ((eq? key (lit delete))
        (if (< n 2) (edit-message! st "An envelope keeps one point.")
          (do (%set-envelope! st name (List remove (%min at (- n 1)) 1 points)) (%put! st %env-at (%max 0 (- (%min at (- n 1)) 1))))))
      (#t ()))))

; --- the info page ------------------------------------------------------------------
;
; Schism Tracker's info page, F5: what is playing, channel by channel, and
; the rows about the one heard.  Up and down pick a channel; M and S mute
; and solo it, as on the pattern; Enter or G edits the pattern heard at
; its row; + and - play the place after or before in the order.

; The pattern heard and its row, (NAME . ROW), or nil while nothing plays.
(def %heard-pattern
  (fn (_ st)
    (def p (%get st %player))
    (def heard (%get st %heard))
    (if (if (null? p) #t (if (null? heard) #t (not (player-playing? p)))) ()
      ((fn (_ name) (if (null? name) () (pair name (rest heard))))
       (if (eq? (player-mode p) (lit pattern)) (player-pattern p)
         ((fn (_ order) (if (< (first heard) (List length order)) (List ref (first heard) order) ())) (song-order (edit-song st))))))))

; Channel CH of pattern PAT at ROW: (NOTE GAIN AGO), the last note
; struck at or before ROW, its gain in percent, and the rows since it;
; nil when none has been.
(def %struck
  (fn (_ ch row)
    (def cells (rest ch))
    ((fn (self i)
       (match ((< i 0) ())
              ((cell-note? (first (cell-parts (List ref i cells))))
                ((fn (_ parts) (list (first parts) (if (null? (List ref 1 parts)) 100 (List ref 1 parts)) (- row i)))
                 (cell-parts (List ref i cells))))
              (#t (self (- i 1)))))
     (%min row (- (List length cells) 1)))))

(def %info-key!
  (fn (_ st key)
    (def hp (%heard-pattern st))
    (def n (if (null? hp) (List length (%channels st)) (List length (song-pattern (edit-song st) (first hp)))))
    (def p (%get st %player))
    (match
      ((eq? key (lit up)) (%put! st %chan (%max 0 (- (%get st %chan) 1))))
      ((eq? key (lit down)) (%put! st %chan (%min (%max 0 (- n 1)) (+ (%get st %chan) 1))))
      ((if (%is? key "m") #t (%is? key "q")) (%hush! st (lit channel) (%get st %chan) #f))
      ((%is? key "s") (%hush! st (lit channel) (%get st %chan) #t))
      ((if (eq? key (lit enter)) #t (%is? key "g"))
        (if (null? hp) (edit-message! st "Nothing is playing: F5 plays the song.")
          (do (if (eq? (player-mode p) (lit pattern)) (%goto-pattern! st (first hp)) (%goto-at! st (first (%get st %heard))))
              (%put! st %row (%min (rest hp) (- (%rows st) 1)))
              (%show-page! st (lit pattern)))))
      ((if (%is? key "+") #t (%is? key "-"))
        (if (if (null? hp) #t (eq? (player-mode p) (lit pattern))) (edit-message! st "+ and - move the song played through its order.")
          (do (%goto-at! st (+ (first (%get st %heard)) (if (%is? key "+") 1 -1)))
              (%put! st %row 0)
              (%start! st (lit song) 0 () #f ""))))
      (#t ()))))

; Shift-F8: the song stopped where it is heard, or played on from there.
(def %pause!
  (fn (_ st)
    (def p (%get st %player))
    (def held (%get st %paused))
    (match
      ((null? p) (edit-message! st %no-sound))
      ((player-playing? p)
        ((fn (_ heard)
           (%put! st %paused (list (player-mode p) (first heard) (if (null? (player-pattern p)) (%get st %pattern) (player-pattern p)) (rest heard)))
           (player-stop! p)
           (%put! st %heard ())
           (edit-message! st (Str8 append "Paused at row " (Str8 str (rest heard)) ": Shift-F8 plays on.")))
         (player-place p)))
      ((null? held) (edit-message! st "Nothing is paused."))
      (#t ((fn (_ e) (%put! st %paused ()) (edit-message! st (if (null? e) "" e)))
           (guard (e (if (Err err? e) (e msg) "the song cannot be played"))
             (do (player-start-at! p (edit-song st) (first held) (List ref 1 held) (List ref 2 held) (List ref 3 held)) ())))))))

; --- the samples page ---------------------------------------------------------------
;
; Schism Tracker's sample list: the samples, the settings of the one
; picked beside them, and its sound drawn beneath.  Tab walks the
; settings; the Alt keys edit the sound, as Schism's do, and :sound does
; what has no key.  An edited sound is heard at once and kept until
; Alt-O writes it to its file.

; The file's waves that are samples, (wave NAME (sample FILE ...)).
(def %samples (fn (_ st) (List filter file-sample? (file-waves (%get st %doc)))))

; The sample picked, its wave form, or nil.
(def %picked-sample
  (fn (_ st)
    (def ws (%samples st))
    (if (null? ws) () (List ref (%min (%get st %sample-at) (- (List length ws) 1)) ws))))

; W's (sample FILE ...) without the head, FILE named from the directory
; of the file edited.
(def %sample-args (fn (_ st w) (rest (List ref 2 (file-sample-at w (if (null? (%get st %path)) () (file-dir (%get st %path))))))))

; The sound of sample W as it is heard, (RATE FRAMES PCM LOOP ROOT):
; edited, or else its file's, read once; nil when the file cannot be
; read.
(def %sound
  (fn (_ st w)
    (def kept (player-pcm (List ref 1 w)))
    (def path (first (%sample-args st w)))
    (def cache (%get st %sample-cache))
    (match
      ((not (null? kept)) kept)
      ((if (pair? cache) (str=? (first cache) path) #f) (rest cache))
      (#t ((fn (_ d) (%put! st %sample-cache (pair path d)) d)
           (guard (e ()) (player-wav path)))))))

; The settings the page shows, in the order Tab walks them: (LABEL KEY).
(def %sample-fields
  (list (list "Default volume" (lit volume)) (list "Global volume" (lit global)) (list "Default pan" (lit pan))
        (list "C-5 speed" (lit speed)) (list "Loop start" (lit loop-start)) (list "Loop end" (lit loop-end))
        (list "Sustain start" (lit sustain-start)) (list "Sustain end" (lit sustain-end))
        (list "Vibrato speed" (lit vib-speed)) (list "Vibrato depth" (lit vib-depth)) (list "Vibrato rate" (lit vib-rate))
        (list "Vibrato wave" (lit vib-wave))))

(def %vib-waves (list (lit sine) (lit ramp) (lit square) (lit random)))

; The loop of ARGS, else D's own, (START END), or nil.
(def %sample-loop-of (fn (_ args d) (if (null? (sample-loop args)) (if (null? d) () (List ref 3 d)) (sample-loop args))))

(def %vibrato-of
  (fn (_ args) ((fn (_ v) (if (null? v) (list 0 0 0 (lit sine)) v)) (sample-setting args (lit vibrato)))))

; Setting KEY of ARGS, the sample's form, and D, its sound: a number, a
; wave's name, or nil for one that is off.
(def %field-value
  (fn (_ args d key)
    (def one (fn (_ k least) ((fn (_ v) (if (null? v) least (first v))) (sample-setting args k))))
    (def loop (%sample-loop-of args d))
    (def sus (sample-setting args (lit sustain)))
    (match
      ((eq? key (lit volume)) (one (lit volume) 64))
      ((eq? key (lit global)) (one (lit global) 64))
      ((eq? key (lit pan)) (one (lit pan) ()))
      ((eq? key (lit speed)) (one (lit speed) (if (null? d) () (first d))))
      ((eq? key (lit loop-start)) (if (null? loop) () (first loop)))
      ((eq? key (lit loop-end)) (if (null? loop) () (List ref 1 loop)))
      ((eq? key (lit sustain-start)) (if (null? sus) () (first sus)))
      ((eq? key (lit sustain-end)) (if (null? sus) () (List ref 1 sus)))
      ((eq? key (lit vib-speed)) (first (%vibrato-of args)))
      ((eq? key (lit vib-depth)) (List ref 1 (%vibrato-of args)))
      ((eq? key (lit vib-rate)) (List ref 2 (%vibrato-of args)))
      (#t (List ref 3 (%vibrato-of args))))))

(def %clamped (fn (_ v least most) (%max least (%min most v))))

; ARGS with setting KEY made V, held within what it can be for a sound
; of FRAMES; nil turns off a pan, a loop or a sustain loop.
(def %field-set
  (fn (_ args frames key v)
    (def loop (sample-loop args))
    (def sus (sample-setting args (lit sustain)))
    (def vib (%vibrato-of args))
    (def points
      (fn (_ pts i)
        (match ((null? v) ())
               ((= i 0) ((fn (_ e) (list (%clamped v 0 (- e 1)) e)) (if (null? pts) frames (List ref 1 pts))))
               (#t ((fn (_ s) (list s (%clamped v (+ s 1) frames))) (if (null? pts) 0 (first pts)))))))
    (match
      ((List includes? key (list (lit volume) (lit global))) (sample-set-setting args key (list (%clamped v 0 64))))
      ((eq? key (lit pan)) (sample-set-setting args key (if (null? v) () (list (%clamped v 0 64)))))
      ((eq? key (lit speed)) (sample-set-setting args key (list (%clamped v 1 999999))))
      ((eq? key (lit loop-start)) (sample-set-loop args (points loop 0)))
      ((eq? key (lit loop-end)) (sample-set-loop args (points loop 1)))
      ((eq? key (lit sustain-start)) (sample-set-setting args (lit sustain) (points sus 0)))
      ((eq? key (lit sustain-end)) (sample-set-setting args (lit sustain) (points sus 1)))
      ((eq? key (lit vib-wave)) (sample-set-setting args (lit vibrato) (List update 3 v vib)))
      (#t (sample-set-setting args (lit vibrato)
            (List update (List find-index (fn (_ k) (eq? k key)) (list (lit vib-speed) (lit vib-depth) (lit vib-rate)))
              (%clamped v 0 64) vib))))))

; The sample W's form made of ARGS2, its file as the form names it: the
; document changed, and the mixer given it.
(def %sample-form!
  (fn (_ st w args2)
    (def own (rest (List ref 2 w)))
    (%doc-change! st (file-set-wave (%get st %doc) (%wave-name w) (list (pair (lit sample) (pair (first own) (rest args2))))))))

; Setting KEY of the sample picked moved by DELTA: a pan, a loop or a
; sustain loop that is off turned on, a vibrato's wave the next.
(def %field-step!
  (fn (_ st key delta)
    (def w (%picked-sample st))
    (def args (%sample-args st w))
    (def d (%sound st w))
    (def frames (if (null? d) 1 (List ref 1 d)))
    (def v (%field-value args d key))
    (%sample-form! st w
      (match
        ((eq? key (lit vib-wave))
          (%field-set args frames key (List ref (int% (+ (List find-index (fn (_ x) (eq? x v)) %vib-waves) (if (< delta 0) 3 1)) 4) %vib-waves)))
        ((null? v) (%field-set args frames key (match ((eq? key (lit pan)) 32) ((List includes? key (list (lit loop-end) (lit sustain-end))) frames) (#t 0))))
        (#t (%field-set args frames key (+ v delta)))))))

; How far left and right move setting KEY of a sound of FRAMES, and with
; Alt.
(def %field-steps
  (fn (_ key frames)
    (match ((List includes? key (list (lit loop-start) (lit loop-end) (lit sustain-start) (lit sustain-end))) (pair 1 (%max 1 (int/ frames 64))))
           ((eq? key (lit speed)) (pair 1 100))
           (#t (pair 1 8)))))

; Edits of the sound: each (fn (_ d args from to n)) answering (D2
; ARGS2): the sound and the sample's form after it.  FROM and TO are the
; frames it covers, the loop's or else the whole sound's, and N the number
; given with it.
(def %same-length (fn (_ f) (fn (_ d args from to n) (list (%sound-with d (f (List ref 2 d) (List ref 1 d) from to n)) args))))

(def %sound-with (fn (_ d pcm) (list (first d) (List ref 1 d) pcm (List ref 3 d) (List ref 4 d))))

; D cut to the frames FROM up to TO kept or, when KEEP is #f, taken out;
; the loop and sustain loop of ARGS moved with the frames, or dropped
; when cut into.
(def %cut-sound
  (fn (_ d args from to keep)
    (def frames (List ref 1 d))
    (def c (if keep (list (sample-copy (List ref 2 d) from to) (- to from)) (sample-cut (List ref 2 d) frames from to)))
    (def moved
      (fn (_ pts)
        (match ((null? pts) ())
               (keep (if (if (<= from (first pts)) (<= (List ref 1 pts) to) #f) (list (- (first pts) from) (- (List ref 1 pts) from)) ()))
               ((<= (List ref 1 pts) from) pts)
               ((<= to (first pts)) (list (- (first pts) (- to from)) (- (List ref 1 pts) (- to from))))
               (#t ()))))
    (list (list (first d) (List ref 1 c) (first c) () (List ref 4 d))
          (sample-set-setting (sample-set-loop args (moved (%sample-loop-of args d))) (lit sustain) (moved (sample-setting args (lit sustain)))))))

; D drawn out or squeezed to N frames, read straight between its frames
; when LERP is #t or else the nearest; the loops scaled with it, and the
; speed too when KEEP-PITCH is #t.
(def %resize-sound
  (fn (_ d args n lerp keep-pitch)
    (def frames (List ref 1 d))
    (def r (sample-resample (List ref 2 d) frames n lerp))
    (def scaled (fn (_ pts) (if (null? pts) () (List map (fn (_ x) (%min n (int/ (* x n) frames))) pts))))
    (def args2 (sample-set-setting (sample-set-loop args (scaled (%sample-loop-of args d))) (lit sustain) (scaled (sample-setting args (lit sustain)))))
    (list (list (first d) n (first r) () (List ref 4 d))
          (if keep-pitch (sample-set-setting args2 (lit speed) (list (%max 1 (int/ (* (%field-value args d (lit speed)) n) frames)))) args2))))

(def %sound-edits
  (list (pair "reverse" (%same-length (fn (_ pcm frames from to n) (sample-reverse pcm frames))))
        (pair "invert" (%same-length (fn (_ pcm frames from to n) (sample-invert pcm frames))))
        (pair "centre" (%same-length (fn (_ pcm frames from to n) (sample-centre pcm frames))))
        (pair "normalise" (%same-length (fn (_ pcm frames from to n) (sample-normalise pcm frames))))
        (pair "amplify" (%same-length (fn (_ pcm frames from to n) (sample-amplify pcm frames from to n))))
        (pair "silence" (%same-length (fn (_ pcm frames from to n) (sample-silence pcm frames from to))))
        (pair "fade-in" (%same-length (fn (_ pcm frames from to n) (sample-fade pcm frames from to #t))))
        (pair "fade-out" (%same-length (fn (_ pcm frames from to n) (sample-fade pcm frames from to #f))))
        (pair "cut" (fn (_ d args from to n) (%cut-sound d args from to #f)))
        (pair "crop" (fn (_ d args from to n) (%cut-sound d args from to #t)))
        (pair "cut-before" (fn (_ d args from to n) (%cut-sound d args from (List ref 1 d) #t)))
        (pair "cut-after" (fn (_ d args from to n) (%cut-sound d args 0 to #t)))
        (pair "resize" (fn (_ d args from to n) (%resize-sound d args n #t #f)))
        (pair "stretch" (fn (_ d args from to n) (%resize-sound d args n #f #f)))
        (pair "resample" (fn (_ d args from to n) (%resize-sound d args n #t #t)))))

; The edits that take a number, and the least and most it can be.
(def %sound-numbers
  (list (list "amplify" 0 1000) (list "resize" 1 9999999) (list "stretch" 1 9999999) (list "resample" 1 9999999)))

; The sound of sample W made D2 and its form ARGS2, the sound before it
; kept to undo to: heard at once, kept until Alt-O writes it.
(def %sound-change!
  (fn (_ st w d2 args2)
    (def name (List ref 1 w))
    (def args (%sample-args st w))
    (def entry (%here st (list (list name (%sound st w)))))
    (def before (%get st %undo))
    (%put! st %sample-peaks ())
    (player-pcm! name args2 d2)
    (unless (equal? args args2) (%sample-form! st w args2))
    ; One step for the sound and its form: the form's own step taken
    ; back into this one.
    (if (same? before (%get st %undo)) (%remember! st entry) (%put! st %undo (pair entry (rest (%get st %undo)))))))

; :sound OP [N] [FROM TO]: the edit OP done to the sound of the sample
; picked, over the frames FROM up to TO, else its loop, else all of it.
(def %sound-cmd!
  (fn (_ st args)
    (def w (%picked-sample st))
    (def op (if (null? args) () (first args)))
    (def edit (if (null? op) () (%str-entry op %sound-edits)))
    (def wants (if (null? op) () (List find (fn (_ e) (str=? (first e) op)) %sound-numbers)))
    (def nums (if (null? args) () (List map %num (rest args))))
    (def d (if (null? w) () (%sound st w)))
    (match
      ((null? w) (edit-message! st "No sample: F3, then Insert reads one."))
      ((null? op) (edit-message! st (Str8 append ":sound OP [N] [FROM TO], OP one of " (Str8 join " " (List map first %sound-edits)) ", set, mono, save, undo")))
      ((str=? op "save") (%sound-save! st w))
      ((str=? op "undo") (%undo-step! st %undo %redo "undo"))
      ((str=? op "mono") (edit-message! st "A sample is one channel already: the WAV reader takes the mean of a file's channels."))
      ((str=? op "set")
        ((fn (_ key)
           (match ((null? key) (edit-message! st (Str8 append ":sound set KEY N, KEY one of " (Str8 join " " (List map (fn (_ f) (symbol->str (List ref 1 f))) %sample-fields)))))
                  ((eq? key (lit vib-wave))
                    (if (if (< 2 (List length args)) (List includes? (str->sym (List ref 2 args)) %vib-waves) #f)
                      (%sample-form! st w (%field-set (%sample-args st w) (if (null? d) 1 (List ref 1 d)) key (str->sym (List ref 2 args))))
                      (edit-message! st ":sound set vib-wave sine|ramp|square|random")))
                  ((if (< 2 (List length args)) (str=? (List ref 2 args) "off") #f)
                    (%sample-form! st w (%field-set (%sample-args st w) (if (null? d) 1 (List ref 1 d)) key ())))
                  ((if (< 2 (List length args)) (null? (%num (List ref 2 args))) #t) (edit-message! st ":sound set KEY N, or off"))
                  (#t (%sample-form! st w (%field-set (%sample-args st w) (if (null? d) 1 (List ref 1 d)) key (%num (List ref 2 args)))))))
         (if (< 1 (List length args))
           ((fn (_ f) (if (null? f) () (List ref 1 f))) (List find (fn (_ f) (str=? (symbol->str (List ref 1 f)) (List ref 1 args))) %sample-fields))
           ())))
      ((null? edit) (edit-message! st (Str8 append "No edit " op ": :sound alone lists them.")))
      ((null? d) (edit-message! st (Str8 append "The file " (first (%sample-args st w)) " cannot be read.")))
      ((if (List includes? op (list "cut-before" "cut-after")) (null? (%sample-loop-of (%sample-args st w) d)) #f)
        (edit-message! st "The sample has no loop: Tab to Loop start, then Space."))
      ((List any? null? nums) (edit-message! st "The numbers after the edit are whole numbers."))
      ((if (null? wants) #f (if (null? nums) #t (if (< (first nums) (List ref 1 wants)) #t (< (List ref 2 wants) (first nums)))))
        (edit-message! st (Str8 append ":sound " op " N, N from " (Str8 str (List ref 1 wants)) " to " (Str8 str (List ref 2 wants)) ".")))
      (#t
        ((fn (_ range)
           (def frames (List ref 1 d))
           (def from (%clamped (first range) 0 frames))
           (def to (%clamped (List ref 1 range) from frames))
           (if (if (= from to) (List includes? op (list "silence" "fade-in" "fade-out" "cut" "crop")) #f)
             (edit-message! st "No frames to edit: FROM is TO.")
             ((fn (_ r)
                (if (= (List ref 1 (first r)) 0) (edit-message! st "That would leave no sound.")
                  (do (%sound-change! st w (first r) (List ref 1 r))
                      (edit-message! st (Str8 append "Sound of " (%wave-name w) ": " op ", " (Str8 str (List ref 1 (first r))) " frames. Alt-O writes it.")))))
              ((rest edit) d (%sample-args st w) from to (if (null? wants) () (first nums))))))
         (match ((not (< (List length nums) (if (null? wants) 2 3))) (if (null? wants) nums (rest nums)))
                ((List includes? op %loop-edits)
                  ((fn (_ l) (if (null? l) (list 0 (List ref 1 d)) l)) (%sample-loop-of (%sample-args st w) d)))
                (#t (list 0 (List ref 1 d)))))))))

; The edits that cover the loop when no frames are given.
(def %loop-edits (list "silence" "fade-in" "fade-out" "cut" "crop" "cut-before" "cut-after"))

; Sample W's sound written to its file, a WAV file of one channel at its
; C-5 speed.
(def %sound-save!
  (fn (_ st w)
    (def args (%sample-args st w))
    (def d (%sound st w))
    (if (null? d) (edit-message! st (Str8 append "The file " (first args) " cannot be read."))
      (%try! st "the file cannot be written"
        (fn (_)
          (sample-write! (List ref 2 d) (List ref 1 d) (%field-value args d (lit speed)) (first args))
          (%put! st %sample-cache ())
          (player-pcm! (List ref 1 w) args ())
          (edit-message! st (Str8 append "Written: " (first args) ", " (Str8 str (List ref 1 d)) " frames."))
          ())))))

; Alt keys of the list, as Schism's: each the :sound it does, a string
; ending in a blank for one typed on.
(def %sample-alt-keys
  (list (pair (lit alt-g) "reverse") (pair (lit alt-i) "invert") (pair (lit alt-h) "centre")
        (pair (lit alt-b) "cut-before") (pair (lit alt-l) "cut-after") (pair (lit alt-D) "mono")
        (pair (lit alt-o) "save")))

(def %samples-key!
  (fn (_ st key)
    (def ws (%samples st))
    (def at (%min (%get st %sample-at) (%max 0 (- (List length ws) 1))))
    (def w (if (null? ws) () (List ref at ws)))
    (def field (%get st %sample-field))
    (def fkey (if (null? field) () (List ref 1 (List ref field %sample-fields))))
    (def piano (if (str? key) (%str-entry key %piano) ()))
    (def alt (if (symbol? key) (Assoc entry key %sample-alt-keys) ()))
    (def frames (fn (_) ((fn (_ d) (if (null? d) 1 (List ref 1 d))) (%sound st w))))
    (def typed (fn (_ text) (%put! st %input (pair (lit command) text))))
    (match
      ((if (eq? key (lit insert)) #t (null? w)) (when (List includes? key (list (lit insert) (lit enter))) (typed "sample ")))
      ((eq? key (lit complete)) (%put! st %sample-field (if (null? field) 0 (if (< field (- (List length %sample-fields) 1)) (+ field 1) ()))))
      ((eq? key (lit shift-tab)) (%put! st %sample-field (if (null? field) (- (List length %sample-fields) 1) (if (< 0 field) (- field 1) ()))))
      ((not (null? alt)) (%sound-cmd! st (list (rest alt))))
      ((eq? key (lit alt-m))
        ((fn (_ d)
           (typed (Str8 append "sound amplify "
                    (if (null? d) "100" (Str8 str (%min 1000 (int/ 3276700 (%max 1 (sample-peak (List ref 2 d) (List ref 1 d))))))))))
         (%sound st w)))
      ((List includes? key (list (lit alt-e) (lit alt-f) (lit alt-E) (lit alt-F)))
        (typed (Str8 append "sound " (match ((eq? key (lit alt-e)) "resize ") ((eq? key (lit alt-f)) "stretch ") (#t "resample "))
                 (Str8 str (frames)))))
      ((List includes? key (list (lit alt-+) (lit alt--) (lit alt-=)))
        ((fn (_ hz) (%sample-form! st w (%field-set (%sample-args st w) (frames) (lit speed) (if (eq? key (lit alt--)) (int/ hz 2) (* hz 2)))))
         (%field-value (%sample-args st w) (%sound st w) (lit speed))))
      ((if (null? field) (List includes? key (list "+" "-")) #f)
        ((fn (_ hz) (%sample-form! st w (%field-set (%sample-args st w) (frames) (lit speed)
                                          (if (%is? key "+") (int/ (* hz 1059463) 1000000) (int/ (* hz 1000000) 1059463)))))
         (%field-value (%sample-args st w) (%sound st w) (lit speed))))
      ((eq? key (lit up)) (do (%put! st %sample-at (%max 0 (- at 1))) (%put! st %sample-peaks ())))
      ((eq? key (lit down)) (do (%put! st %sample-at (%min (%max 0 (- (List length ws) 1)) (+ at 1))) (%put! st %sample-peaks ())))
      ((null? field)
        (match
          ((eq? key (lit enter))
            (typed (Str8 append "sample " (%wave-name w) " " (Str8 join " " (List map %write-form (rest (List ref 2 w)))))))
          ((%is? key " ") (%hear-sample! st (%wave-name w) "C4"))
          ((not (null? piano)) (%hear-sample! st (%wave-name w) (%note-for st (rest piano))))
          (#t ())))
      ((List includes? key (list (lit left) (lit right) (lit alt-left) (lit alt-right)))
        ((fn (_ steps)
           (%field-step! st fkey (* (if (List includes? key (list (lit left) (lit alt-left))) -1 1)
                                   (if (List includes? key (list (lit alt-left) (lit alt-right))) (rest steps) (first steps)))))
         (%field-steps fkey (frames))))
      ((if (%is? key " ") (List includes? fkey (list (lit pan) (lit loop-start) (lit loop-end) (lit sustain-start) (lit sustain-end))) #f)
        (if (null? (%field-value (%sample-args st w) (%sound st w) fkey)) (%field-step! st fkey 0)
          (%sample-form! st w (%field-set (%sample-args st w) (frames) fkey ()))))
      ((eq? key (lit enter))
        ((fn (_ v) (typed (Str8 append "sound set " (symbol->str fkey) " " (if (null? v) "off" (if (symbol? v) (symbol->str v) (Str8 str v))))))
         (%field-value (%sample-args st w) (%sound st w) fkey)))
      ((%is? key " ") (%hear-sample! st (%wave-name w) "C4"))
      ((not (null? piano)) (%hear-sample! st (%wave-name w) (%note-for st (rest piano))))
      (#t ()))))

; Sample NAME heard at NOTE, as an instrument of it alone would play it.
(def %hear-sample!
  (fn (_ st name note . chord)
    (unless (null? (%get st %player))
      (%try! st "the sample cannot be played"
        (fn (_)
          (player-preview! (%get st %player)
            (song-set-instrument (edit-song st) (Str8 append "(instrument sample-heard (wave " name ") (env (0 100) (60000 100)) (release 30))"))
            "sample-heard" note (if (pair? chord) (first chord) #f))
          (edit-feed! st) ())))))

; :sample NAME FILE [ROOT] [START END]: the WAV file FILE kept as the wave
; NAME, read from the directory of the file edited, sounding at ROOT and
; looping from START to END when they are given; the settings the page
; gave the sample, and its sound as edited, kept.
(def %sample-cmd!
  (fn (_ st args)
    (def name (if (null? args) () (first args)))
    (match
      ((< (List length args) 2) (edit-message! st ":sample NAME FILE.wav [ROOT] [START END]"))
      ((not (%name? name)) (edit-message! st "A sample's name is a word."))
      (#t ((fn (_ parts)
             (def had (file-wave (%get st %doc) name))
             (def kept (if (if (null? had) #f (file-sample? had)) (List filter pair? (rest (rest (List ref 2 had)))) ()))
             (def parts2 (List append parts kept))
             (def form (list (lit wave) (str->sym name) (pair (lit sample) parts2)))
             (def dir (if (null? (%get st %path)) "." (file-dir (%get st %path))))
             (%try! st "not a WAV file"
               (fn (_)
                 ; A new file is heard as it is; read once here, so one
                 ; that is not a WAV file says so now.
                 (if (if (null? had) #f (if (file-sample? had) (str=? (List ref 1 (List ref 2 had)) (first parts)) #f))
                   (player-give! (file-sample-at form dir))
                   (player-pcm! (str->sym name) (rest (List ref 2 (file-sample-at form dir))) ()))
                 (%put! st %sample-cache ())
                 (%put! st %sample-peaks ())
                 (%doc-change! st (file-set-wave (%get st %doc) name (list (pair (lit sample) parts2))))
                 (edit-message! st (Str8 append "Sample " name ": " (List ref 1 args) ". An instrument plays it with (wave " name ")."))
                 ())))
           (pair (List ref 1 args)
             (List map (fn (_ w) (if (null? (%num w)) w (%num w))) (rest (rest args)))))))))

; --- the pattern editor's columns ---------------------------------------------------

(def %digits (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"))
(def %effect-letters (list "a" "v" "s" "p" "t" "f" "l" "w" "o" "x" "y" "c" "d" "r" "e"))

; A key in the instrument, volume or effect column: digits make the
; instrument or the volume, . clears the volume or the effects, a
; letter or Enter edits the effects.  A key that would type a note does
; nothing there.  Answers whether KEY was one of these.
(def %field-key!
  (fn (_ st key)
    (def field (%get st %field))
    (def digit (if (str? key) (List index-of key %digits) ()))
    (match
      ((null? (%get st %pattern)) #f)
      ((if (null? field) #t (= field 0)) #f)
      ((if (null? digit) #f (< field 3)) (do (%digit! st digit) #t))
      ((%is? key ".")
        (do (match ((= field 2) (%parts-change! st (fn (_ p) (list (first p) () (List ref 2 p))) #t))
                   ((= field 3) (%parts-change! st (fn (_ p) (list (first p) (List ref 1 p) ())) #t))
                   (#t ()))
            #t))
      ((if (= field 3) (if (eq? key (lit enter)) #t (if (str? key) (List includes? key %effect-letters) #f)) #f)
        (do (%effect-key! st key) #t))
      ((if (str? key) (not (null? (%str-entry key %piano))) #f) #t)
      (#t #f))))

; --- opening another file --------------------------------------------------------

; :open FILE: FILE edited in place of this one, made when it is first
; written if it does not exist; refused once while there are changes not
; written, as :q is.
(def %open-cmd!
  (fn (_ st args)
    (def path (Str8 join " " args))
    (match
      ((null? args) (edit-message! st ":open FILE"))
      ((if (file-changed? (%get st %doc)) (not (%get st %warned)) #f)
        (do (%put! st %warned #t) (edit-message! st "The song has changed: :w writes it, :open again leaves it.")))
      (#t (%try! st "the file cannot be read"
            (fn (_)
              (def doc (file-read path))
              (%put! st %doc (if (null? (file-songs doc)) (file-add-song doc (song-new "untitled")) doc))
              (%put! st %path path)
              (%put! st %undo ()) (%put! st %redo ()) (%put! st %warned #f)
              (%go-song! st 0)
              (%sync-waves! st)
              (%show-page! st (lit pattern))
              (edit-message! st (Str8 append "Opened " path "."))
              ()))))))

; CELL's gain taken to PCT percent of itself: a note's, held and let-go
; cells as they were.
(def %amplified
  (fn (_ cell pct)
    (def p (cell-parts cell))
    (if (not (cell-note? (first p))) cell
      (cell-join (first p) (%min 400 (int/ (+ 50 (* pct (if (null? (List ref 1 p)) 100 (List ref 1 p)))) 100)) (List ref 2 p)))))
; --- a MIDI keyboard ---------------------------------------------------------------
;
; A note played on a MIDI keyboard (tracker/app reads it, (midi on)) is
; heard as a typed one is: the channel's instrument on the pattern, the
; instrument or the sample picked on F4 and F3, a chord's notes together.
; On the pattern it goes in the cursor's cell as a typed note does, its
; velocity the volume column's gain, and the cursor moves on by the step.
; Middle C is C of the octave, so < and > move the keyboard.  With
; (midi-off on) a key let go when no other is held puts a let-go.

; The name of note N, middle C 60, with the octave over 4 added; nil past
; octaves 0 to 8.
(def %midi-name
  (fn (_ st n)
    (def k (+ n (* 12 (- (%get st %octave) 4))))
    (if (if (< k 12) #t (< 119 k)) ()
      (Str8 append (List ref (int% k 12) %note-names) (Str8 str (- (int/ k 12) 1))))))

; Whether the pattern has the keys: its page, no line typed and nothing
; over it.
(def %pattern-keyed?
  (fn (_ st)
    (if (if (eq? (%get st %page) (lit pattern)) (null? (%get st %input)) #f)
      (if (null? (%get st %pattern)) #f
        (if (%get st %help) #f (if (null? (%get st %browse)) (null? (%get st %order-at)) #f)))
      #f)))

(def %midi-on!
  (fn (_ st n vel)
    (def name (%midi-name st n))
    (def gain (%max 1 (int/ (+ (* vel 100) 63) 127)))
    (def note (if (null? name) () (if (<= 100 gain) name (Str8 append name ":" (Str8 str gain)))))
    (def p (%get st %player))
    (def hear! (fn (_ s inst) (unless (null? p) (%try! st "the note cannot be played" (fn (_) (player-preview! p s inst note #t) (edit-feed! st) ())))))
    (%put! st %midi-held (pair n (List filter (fn (_ k) (not (= k n))) (%get st %midi-held))))
    (match
      ((null? note) ())
      ((eq? (%get st %page) (lit samples))
        (unless (null? (%samples st)) (%hear-sample! st (%wave-name (%picked-sample st)) note #t)))
      ((eq? (%get st %page) (lit instruments))
        (unless (null? (%picked-instrument st)) (hear! (edit-song st) (%picked-instrument st))))
      ((null? (%get st %pattern)) ())
      (#t (do (hear! (edit-song st) (first (List ref (%get st %chan) (%channels st))))
              (when (%pattern-keyed? st)
                ((fn (_ old)
                   (def slash (List find (fn (_ i) (str=? (Str8 sub i 1 old) "/")) (List range 0 (Str8 length old))))
                   (%put-cell! st (Str8 append note (if (null? slash) "" (Str8 sub slash (- (Str8 length old) slash) old)))))
                 (%cell st))))))))

(def %midi-off!
  (fn (_ st n)
    (%put! st %midi-held (List filter (fn (_ k) (not (= k n))) (%get st %midi-held)))
    (when (if (null? (%get st %midi-held)) (if (config-get (%get st %config) (lit midi-off)) (%pattern-keyed? st) #f) #f)
      (%put-cell! st "-"))))

; A message of the MIDI keyboard, (midi note-on CH NOTE VEL) and the
; rest x/sys/midi decodes; a note-on of velocity 0 is a note-off.  While
; a line is typed the keyboard is heard only.
(def %midi!
  (fn (_ st m)
    (def kind (List ref 1 m))
    (match
      ((not (List includes? kind (list (lit note-on) (lit note-off)))) ())
      ((if (eq? kind (lit note-on)) (< 0 (List ref 4 m)) #f)
        (%midi-on! st (List ref 3 m) (List ref 4 m)))
      (#t (%midi-off! st (List ref 3 m))))))

; --- the mouse --------------------------------------------------------------------
;
; Schism Tracker's mouse: a click picks what is under it, a drag marks a
; block on the pattern or moves an envelope's point or a loop's end, the
; wheel scrolls.  What is where is read from the screen last drawn
; (%target!), so a click is taken as what is seen.  A click on the line
; already picked in a list does what Enter does there.

(def %t-top (fn (_ t) (List ref 1 t)))
(def %t-left (fn (_ t) (List ref 3 t)))
(def %t-data (fn (_ t) (rest (rest (rest (rest (rest t)))))))

; The target under ROW and COL, the last drawn of those there, or nil.
(def %target-at
  (fn (_ st row col)
    (List find (fn (_ t) (if (if (<= (List ref 1 t) row) (< row (List ref 2 t)) #f) (if (<= (List ref 3 t) col) (< col (List ref 4 t)) #f) #f))
      (%get st %targets))))

; The target of KIND last drawn, or nil.
(def %target-of (fn (_ st kind) (List find (fn (_ t) (eq? (first t) kind)) (%get st %targets))))

; The place of the grid G at screen ROW and COL: (ROW CHANNEL FIELD
; HEADING), HEADING whether it is the channels' heading.  A row past the
; grid's top or bottom is the row there, kept within the pattern.
(def %grid-place
  (fn (_ st g y x)
    (def d (%t-data g))
    (def x0 (List ref 3 d))
    (def width (List ref 4 d))
    (def k (%max 0 (%min (- (List ref 2 d) 1) (if (< x x0) 0 (int/ (- x x0) width)))))
    (def o (if (< x x0) 0 (- (- x x0) (* k width))))
    (list (%max 0 (%min (- (%rows st) 1) (+ (first d) (- y (+ (%t-top g) 1)))))
          (%max 0 (%min (- (List length (%channels st)) 1) (+ (List ref 1 d) k)))
          (List fold (fn (_ f i) (if (<= (List ref i (List ref 5 d)) o) i f)) 0 (List range 0 4))
          (= y (%t-top g)))))

; The line of the list of KIND the page keeps, and whether the list has
; the keys: on F4 the envelope can have them, on F3 the settings.
(def %list-at
  (fn (_ st kind)
    (match ((eq? kind (lit orders)) (if (null? (%get st %order-at)) 0 (%get st %order-at)))
           ((eq? kind (lit song)) (%get st %setting-at))
           ((eq? kind (lit instruments)) (%get st %inst-at))
           ((eq? kind (lit samples)) (%get st %sample-at))
           ((eq? kind (lit sample-field)) (if (null? (%get st %sample-field)) 0 (%get st %sample-field)))
           (#t (%get st %chan)))))

(def %list-keyed?
  (fn (_ st kind)
    (match ((eq? kind (lit instruments)) (null? (%get st %env-at)))
           ((eq? kind (lit samples)) (null? (%get st %sample-field)))
           ((eq? kind (lit sample-field)) (not (null? (%get st %sample-field))))
           (#t #t))))

; The line picked in the list of KIND, or nil while the list has not the keys.
(def %list-picked (fn (_ st kind) (if (%list-keyed? st kind) (%list-at st kind) ())))

(def %list-pick!
  (fn (_ st kind i)
    (match ((eq? kind (lit orders)) (%put! st %order-at i))
           ((eq? kind (lit song)) (%put! st %setting-at i))
           ((eq? kind (lit instruments)) (do (%put! st %inst-at i) (%put! st %env-at ()) (%put! st %env-held #f)))
           ((eq? kind (lit samples)) (do (%put! st %sample-at i) (%put! st %sample-field ()) (%put! st %sample-peaks ())))
           ((eq? kind (lit sample-field)) (%put! st %sample-field i))
           (#t (%put! st %chan i)))))

; The point of POINTS nearest column C of the envelope drawn with DATA,
; (LAST-MS WIDTH HIGH).
(def %nearest-point
  (fn (_ points data c)
    (def col-of (fn (_ ms) (int/ (* ms (- (List ref 1 data) 1)) (first data))))
    (first (List fold (fn (_ best i) (def dist ((fn (_ v) (if (< v 0) (- 0 v) v)) (- c (col-of (first (List ref i points))))))
                                     (if (if (null? best) #t (< dist (rest best))) (pair i dist) best))
             () (List range 0 (List length points))))))

; The envelope's point picked put where screen ROW and COL are in the
; envelope drawn E.
(def %drag-point!
  (fn (_ st e y x)
    (def d (%t-data e))
    (def name (%picked-instrument st))
    (def points (if (null? name) () (%envelope (%instrument-form st name))))
    (def h1 (%max 1 (- (List ref 2 d) 1)))
    (unless (null? points)
      (%put-point! st name points (%min (%get st %env-at) (- (List length points) 1))
        (int/ (* (%max 0 (- x (%t-left e))) (first d)) (%max 1 (- (List ref 1 d) 1)))
        (int/ (* (- h1 (%max 0 (%min h1 (- y (%t-top e))))) 100) h1)))))

; The frame of the sound drawn S at screen column COL.
(def %sound-frame
  (fn (_ s col)
    (def d (%t-data s))
    (%max 0 (%min (first d) (int/ (* (%max 0 (- col (%t-left s))) (first d)) (%max 1 (List ref 1 d)))))))

; The loop's end KEY, loop-start or loop-end, of the sample picked put at
; FRAME.
(def %drag-loop!
  (fn (_ st key frame)
    (def w (%picked-sample st))
    (def d (%sound st w))
    (unless (null? d) (%sample-form! st w (%field-set (%sample-args st w) (List ref 1 d) key frame)))))

; A change made while a button is dragged: the first kept to undo to,
; the rest made over it, so a drag is one step of undo.
(def %drag-change!
  (fn (_ st f)
    (def before (%get st %undo))
    (f)
    (if (List ref 1 (%get st %drag))
      (unless (same? before (%get st %undo)) (%put! st %undo (rest (%get st %undo))))
      (%put! st %drag (List update 1 #t (%get st %drag))))))

(def %mouse-press!
  (fn (_ st button y x mods)
    (def t (%target-at st y x))
    (def kind (if (null? t) () (first t)))
    (def left (eq? button (lit left)))
    (%put! st %drag ())
    (match
      ((null? t) ())
      ((eq? kind (lit panel))
        ((fn (_ d)
           (def i (+ (List ref 2 d) (+ (* (int/ x (List ref 1 d)) (first d)) (- y (%t-top t)))))
           (if (if (null? (%get st %pick)) #t (not (< i (List ref 3 d)))) (%put! st %help #f)
             (do (%put! st %pick i) (%pick-key! st (lit enter)))))
         (%t-data t)))
      ((eq? kind (lit help)) (if (null? (%get st %pick)) (%put! st %help #f) (%pick-key! st (lit escape))))
      ((not left) (when (if (eq? kind (lit sound)) (eq? button (lit right)) #f) (do (%put! st %drag (list (lit loop-end) #f)) (%drag-change! st (fn (_) (%drag-loop! st (lit loop-end) (%sound-frame t x)))))))
      ((eq? kind (lit page)) (if (eq? (%t-data t) (lit help)) (%browse! st 0 0) (%show-page! st (%t-data t))))
      ((eq? kind (lit order))
        (if (null? (%get st %order-at)) (do (%goto-at! st (%t-data t)) (%show-page! st (lit pattern))) (%put! st %order-at (%t-data t))))
      ((eq? kind (lit grid))
        ((fn (_ p)
           (%put! st %order-at ())
           (if (List ref 3 p) (do (%put! st %chan (List ref 1 p)) (%put! st %field 0))
             (do (if (List includes? (lit shift) mods)
                   (when (null? (%get st %mark)) (do (%put! st %mark (%mark-at! st)) (%put! st %mark-end ())))
                   (unless (null? (%get st %mark)) (do (%put! st %mark ()) (%put! st %mark-end ()))))
                 (%put! st %row (first p)) (%put! st %chan (List ref 1 p)) (%put! st %field (List ref 2 p))
                 (if (null? (%get st %mark)) (%put! st %drag (list (lit grid) (pair (first p) (List ref 1 p)))) (%block-said! st)))))
         (%grid-place st t y x)))
      ((eq? kind (lit list))
        ((fn (_ d)
           (def i (+ (List ref 1 d) (- y (%t-top t))))
           (when (< i (List ref 2 d))
             (if (%same? i (%list-picked st (first d))) (%page-key! st (lit enter)) (%list-pick! st (first d) i))))
         (%t-data t)))
      ((eq? kind (lit envelope))
        ((fn (_ name)
           (def points (if (null? name) () (%envelope (%instrument-form st name))))
           (unless (null? points)
             (do (%put! st %env-at (%nearest-point points (%t-data t) (- x (%t-left t))))
                 (%put! st %env-held #t)
                 (%put! st %drag (list (lit envelope) #f))
                 (%drag-change! st (fn (_) (%drag-point! st t y x))))))
         (%picked-instrument st)))
      ((eq? kind (lit sound))
        ((fn (_ frame w)
           (def loop (%sample-loop-of (%sample-args st w) (%sound st w)))
           (def key (if (null? loop) (lit loop-start)
                      (if (< (- frame (first loop)) (- (List ref 1 loop) frame)) (lit loop-start) (lit loop-end))))
           (%put! st %drag (list key #f))
           (%drag-change! st (fn (_) (%drag-loop! st key frame)))
           (when (null? loop) (%put! st %drag (list (lit loop-end) #t))))
         (%sound-frame t x) (%picked-sample st)))
      (#t ()))))

(def %mouse-drag!
  (fn (_ st y x)
    (def d (%get st %drag))
    (def kind (first d))
    (def t (%target-of st (if (List includes? kind (list (lit loop-start) (lit loop-end))) (lit sound) kind)))
    (match
      ((null? t) ())
      ((eq? kind (lit grid))
        ((fn (_ p)
           (def from (List ref 1 d))
           (unless (if (null? (%get st %mark)) (if (= (first p) (first from)) (= (List ref 1 p) (rest from)) #f) #f)
             (do (when (null? (%get st %mark)) (do (%put! st %mark from) (%put! st %mark-end ())))
                 (%put! st %row (first p)) (%put! st %chan (List ref 1 p))
                 (%block-said! st))))
         (%grid-place st t y x)))
      ((eq? kind (lit envelope)) (%drag-change! st (fn (_) (%drag-point! st t y x))))
      (#t (%drag-change! st (fn (_) (%drag-loop! st kind (%sound-frame t x))))))))

(def %mouse-wheel!
  (fn (_ st button y x)
    (def t (%target-at st y x))
    (def kind (if (null? t) () (first t)))
    (def up (eq? button (lit up)))
    (def three (fn (_ f) (f) (f) (f)))
    (match
      ((not (List includes? button (list (lit up) (lit down)))) ())
      ((null? (%get st %pick)) 
        (match
          ((not (null? (%get st %browse))) (three (fn (_) (%browse-key! st (if up (lit up) (lit down))))))
          ((null? t) ())
          ((eq? kind (lit grid)) (%put! st %row (%max 0 (%min (- (%rows st) 1) (+ (%get st %row) (if up -3 3))))))
          ((eq? kind (lit order)) (%goto-at! st (+ (if (null? (%get st %at)) 0 (%get st %at)) (if up -1 1))))
          ((if (eq? kind (lit list)) (eq? (first (%t-data t)) (lit sample-field)) #f)
            (do (%put! st %sample-field (%min (- (List ref 2 (%t-data t)) 1) (+ (List ref 1 (%t-data t)) (- y (%t-top t)))))
                (%samples-key! st (if up (lit right) (lit left)))))
          ((eq? kind (lit list))
            (do (when (null? (%list-picked st (first (%t-data t)))) (%list-pick! st (first (%t-data t)) (%list-at st (first (%t-data t)))))
                (%page-key! st (if up (lit up) (lit down)))))
          (#t ())))
      (#t (%pick-key! st (if up (lit up) (lit down)))))))

; A report of the mouse, (mouse ACTION BUTTON ROW COL MODS) as Term key
; answers it.  While a line is typed the mouse is not taken.
(def %mouse!
  (fn (_ st m)
    (def action (List ref 1 m))
    (match
      ((not (null? (%get st %input))) ())
      ((eq? action (lit release))
        (do (when (if (null? (%get st %drag)) #f (eq? (first (%get st %drag)) (lit envelope))) (%put! st %env-held #f))
            (%put! st %drag ())))
      ((eq? action (lit drag)) (unless (null? (%get st %drag)) (%mouse-drag! st (List ref 3 m) (List ref 4 m))))
      ((eq? action (lit wheel)) (%mouse-wheel! st (List ref 2 m) (List ref 3 m) (List ref 4 m)))
      ((eq? action (lit press))
        (if (%get st %help) (if (null? (%get st %browse)) (%mouse-press! st (List ref 2 m) (List ref 3 m) (List ref 4 m) (List ref 5 m))
                              (%browse-key! st (lit escape)))
          (%mouse-press! st (List ref 2 m) (List ref 3 m) (List ref 4 m) (List ref 5 m))))
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
      ((eq? kind (lit effects))
        (%parts-change! st (fn (_ p) (list (first p) (List ref 1 p) (List filter (fn (_ e) (not (str=? e ""))) (Str8 split "/" (Str8 trim text))))) #t))
      ((pair? kind)
        (%try! st "not an effect" (fn (_) (%change! st (song-set-effect (edit-song st) (rest kind) (Str8 trim text))) ())))
      (#t ((fn (_ e) (unless (null? e) (edit-message! st e)))
           (guard (e (if (Err err? e) (e msg) "not an instrument"))
             (do (%change! st (song-set-instrument (edit-song st) text)) ())))))))

; The field the line typed is edited in (tracker/field): the one opened
; for it, or a new one when the line was opened since, carrying the
; lines of its kind typed before.
(def %input-field
  (fn (_ st)
    (def input (%get st %input))
    (def c (%get st %input-at))
    (if (if (pair? c) (same? (first c) input) #f) (rest c)
      ((fn (_ f) (%put! st %input-at (pair input f)) f)
       (field-make (first input) (rest input) (history-of (%get st %history) (history-kind (first input))))))))

(def %input-close! (fn (_ st) (%put! st %input ()) (%put! st %input-at ())))

; The lines typed before read from PATH, the file each line entered is
; added to; nil keeps them for the session only.
(def edit-history-open!
  (fn (_ st path)
    (%put! st %history-path path)
    (%put! st %history (history-read path))
    st))

; A key while a line is typed, as x-lang's own lines take it
; (tracker/field): Enter enters it, kept in the history of its kind;
; Escape, or Backspace on an empty line, leaves it.
(def %input-key!
  (fn (_ st key)
    (def f (%input-field st))
    ((fn (_ r)
       (match
         ((eq? r (lit enter))
           (do (def kind (history-kind (field-kind f)))
               (field-remember! f)
               (%put! st %history (history-put (%get st %history) kind (field-history f)))
               (history-add! (%get st %history-path) kind (field-line f))
               (%put! st %input (pair (field-kind f) (field-line f)))
               (%put! st %input-at ())
               (%input-done! st)))
         ((eq? r (lit cancel)) (%input-close! st))
         (#t ())))
     (field-key! f key))))

; An instrument's text on one line, for editing.
(def %one-line
  (fn (_ text) (Str8 join " " (List filter (fn (_ w) (not (str=? w ""))) (Str8 split " " (Str8 replace "\n" " " text))))))

; A key pressed: taken as the key of the action it is bound to, but in a
; line being typed (tracker/config).
(def edit-key!
  (fn (_ st typed)
    (def key (match ((pair? typed) typed) ((null? (%get st %input)) (config-key (%get st %config) typed)) (#t typed)))
    (match
      ((null? key) ())
      ((pair? key) (match ((eq? (first key) (lit mouse)) (%mouse! st key)) ((eq? (first key) (lit midi)) (%midi! st key)) (#t ())))
      ((not (null? (%get st %input))) (%input-key! st key))
      ((not (null? (%get st %pick))) (%pick-key! st key))
      ((not (null? (%get st %browse))) (%browse-key! st key))
      ((%get st %help) (%put! st %help #f))
      ((%global-key! st key) ())
      ((not (eq? (%get st %page) (lit pattern))) (%page-key! st key))
      ((not (null? (%get st %order-at))) (%order-key! st key))
      ((%field-key! st key) ())
      ((%is? key "O")
        (do (%put! st %order-at (if (null? (%get st %at)) 0 (%get st %at)))
            (edit-message! st "Order: left right pick, up down its pattern, i copy, d drop, [ ] move, Enter edit, Escape done")))
      ((eq? key (lit interrupt)) (%quit! st #f))
      ((%is? key ":") (%put! st %input (pair (lit command) "")))
      ((%is? key "?") (%browse! st 0 0))
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
      ((%is? key ";") (%nudge! st "Tension" -10 0 100))
      ((%is? key "'") (%nudge! st "Tension" 10 0 100))
      ((%is? key "_") (%nudge! st "Pace" -10 10 400))
      ((%is? key "+") (%nudge! st "Pace" 10 10 400))
      ((%is? key "9") (%nudge! st "Volume" -10 0 100))
      ((%is? key "0") (%nudge! st "Volume" 10 0 100))
      ((if (eq? key (lit escape)) (not (null? (%get st %loop-at))) #f) (do (%put! st %loop-at ()) (edit-message! st "")))
      ((null? (%get st %pattern)) (edit-message! st "The song has no pattern: :pattern NAME makes one."))
      ((%is? key "G") (%play-here! st))
      ((%is? key "L") (%loop-key! st))
      ((%is? key "M") (%hush! st (lit channel) (%get st %chan) #f))
      ((%is? key "S") (%hush! st (lit channel) (%get st %chan) #t))
      ((%is? key "H") (%hush! st (lit instrument) (first (List ref (%get st %chan) (%channels st))) #f))
      ((%is? key "A") (%hush! st (lit instrument) (first (List ref (%get st %chan) (%channels st))) #t))
      ((eq? key (lit up)) (%move! st -1))
      ((eq? key (lit down)) (%move! st 1))
      ((eq? key (lit page-up)) (%put! st %row (%max 0 (- (%get st %row) 16))))
      ((eq? key (lit page-down)) (%put! st %row (%min (- (%rows st) 1) (+ (%get st %row) 16))))
      ((eq? key (lit home)) (%put! st %row 0))
      ((eq? key (lit end)) (%put! st %row (- (%rows st) 1)))
      ((eq? key (lit left)) (%field-move! st -1))
      ((eq? key (lit right)) (%field-move! st 1))
      ((eq? key (lit alt-left)) (%put! st %chan (%max 0 (- (%get st %chan) 1))))
      ((eq? key (lit alt-right)) (%put! st %chan (%min (- (List length (%channels st)) 1) (+ (%get st %chan) 1))))
      ((eq? key (lit complete))
        (do (%put! st %chan (int% (+ (%get st %chan) 1) (List length (%channels st)))) (%put! st %field 0)))
      ((eq? key (lit shift-tab))
        (do (%put! st %chan (int% (+ (%get st %chan) (- (List length (%channels st)) 1)) (List length (%channels st))))
            (%put! st %field 0)))
      ((eq? key (lit shift-up)) (%shift-move! st (fn (_) (%put! st %row (%max 0 (- (%get st %row) 1))))))
      ((eq? key (lit shift-down)) (%shift-move! st (fn (_) (%put! st %row (%min (- (%rows st) 1) (+ (%get st %row) 1))))))
      ((eq? key (lit shift-left)) (%shift-move! st (fn (_) (%put! st %chan (%max 0 (- (%get st %chan) 1))))))
      ((eq? key (lit shift-right)) (%shift-move! st (fn (_) (%put! st %chan (%min (- (List length (%channels st)) 1) (+ (%get st %chan) 1))))))
      ((eq? key (lit ctrl-page-up)) (%put! st %row 0))
      ((eq? key (lit ctrl-page-down)) (%put! st %row (- (%rows st) 1)))
      ((eq? key (lit alt-b)) (%block-begin! st))
      ((eq? key (lit alt-e)) (%block-end! st))
      ((eq? key (lit alt-l)) (%mark-column! st))
      ((eq? key (lit alt-d)) (%quick-mark! st))
      ((eq? key (lit alt-u)) (%unmark! st))
      ((eq? key (lit alt-c)) (do (%copy-block! st) (edit-message! st (Str8 append (edit-message st) "  Alt-P paste, Alt-O over, Alt-M mix"))))
      ((eq? key (lit alt-z)) (do (%copy-block! st) (%map-block! st (fn (_ c) ".")) (%unmark! st)))
      ((eq? key (lit alt-p)) (%paste! st (lit insert)))
      ((eq? key (lit alt-o)) (%paste! st (lit over)))
      ((eq? key (lit alt-m)) (%paste! st (lit mix)))
      ((eq? key (lit alt-q)) (%map-block! st (fn (_ c) (cell-transpose c 1))))
      ((eq? key (lit alt-a)) (%map-block! st (fn (_ c) (cell-transpose c -1))))
      ((eq? key (lit alt-Q)) (%map-block! st (fn (_ c) (cell-transpose c 12))))
      ((eq? key (lit alt-A)) (%map-block! st (fn (_ c) (cell-transpose c -12))))
      ((eq? key (lit alt-k)) (%try! st "not a slide" (fn (_) (%interpolate! st (lit gain)) ())))
      ((eq? key (lit alt-x)) (%try! st "not a slide" (fn (_) (%interpolate! st (lit effect)) ())))
      ((eq? key (lit alt-w)) (%map-block! st (fn (_ c) (cell-gain c 100))))
      ((eq? key (lit alt-v)) (%put! st %input (pair (lit command) "gain ")))
      ((eq? key (lit alt-j)) (%put! st %input (pair (lit command) "amplify ")))
      ((eq? key (lit alt-s)) (%put! st %input (pair (lit command) "channel-instrument ")))
      ((eq? key (lit alt-f)) (%stretch! st #t))
      ((eq? key (lit alt-g)) (%stretch! st #f))
      ((eq? key (lit insert)) (%set-channels! st (pattern-insert-rows (%channels st) (%get st %chan) (%get st %chan) (%get st %row) 1)))
      ((eq? key (lit shift-delete)) (%set-channels! st (pattern-delete-rows (%channels st) (%get st %chan) (%get st %chan) (%get st %row) 1)))
      ((eq? key (lit alt-insert)) (%set-channels! st (pattern-insert-row (%channels st) (%get st %row))))
      ((eq? key (lit alt-delete)) (%set-channels! st (pattern-delete-row (%channels st) (%get st %row))))
      ((%is? key "4") (%hear-cells! st (list (%get st %chan))))
      ((%is? key "8") (%hear-cells! st (List range 0 (List length (%channels st)))))
      ((%is? key "1") (%parts-change! st (fn (_ p) (list "." () (pair "c0" (List filter (fn (_ e) (not (str=? e "c0"))) (List ref 2 p))))) #t))
      ((%is? key "`") (%put-cell! st "-"))
      ((eq? key (lit enter)) (%put! st %input (pair (lit cell) (%cell st))))
      ((%is? key "E")
        (%put! st %input (pair (lit instrument)
                           (%one-line (song-instrument-text (edit-song st) (first (List ref (%get st %chan) (%channels st))))))))
      ((%is? key "V")
        (if (null? (%get st %mark))
          (do (%put! st %mark (pair (%get st %row) (%get st %chan))) (%put! st %mark-end ())
              (edit-message! st "Marking: move to the block's other corner; Y copy, X cut, P paste, Delete clear, :transpose N, :gain PCT"))
          (%unmark! st)))
      ((eq? key (lit escape)) (do (%put! st %mark ()) (%put! st %mark-end ())))
      ((%is? key "Y") (do (%copy-block! st) (%put! st %mark ()) (%put! st %mark-end ())))
      ((%is? key "X") (do (%copy-block! st) (%map-block! st (fn (_ c) ".")) (%put! st %mark ()) (%put! st %mark-end ())))
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
        (do (%map-block! st (fn (_ c) ".")) (%put! st %mark ()) (%put! st %mark-end ())))
      ((%is? key "I") (%set-channels! st (pattern-insert-row (%channels st) (%get st %row))))
      ((%is? key "D") (%set-channels! st (pattern-delete-row (%channels st) (%get st %row))))
      ((if (%is? key ".") #t (if (eq? key (lit backspace)) #t (eq? key (lit delete)))) (%put-cell! st "."))
      ((%is? key "-") (%put-cell! st "-"))
      ((if (str? key) (not (null? (%str-entry key %piano))) #f) (%note! st (rest (%str-entry key %piano))))
      (#t ()))))

; --- the help ------------------------------------------------------------------

; The help's pages: the index, then each topic (tracker/help).
(def %browse-pages (fn (_) (+ 1 (List length (help-topics)))))


; The help's page I from row ROW: page 0 the index, the rest the topics.
(def %browse!
  (fn (_ st i row)
    (def n (%browse-pages))
    (def page (int% (+ (int% i n) n) n))
    (def lines (if (= page 0) (help-index) (help-topic (List ref (- page 1) (help-topics)))))
    (%put! st %browse (pair page (%max 0 (%min row (- (List length lines) 2)))))
    (%put! st %help lines)
    (edit-message! st %browse-hint)))

; :help shows the index, :help TOPIC that topic's page, :help WORD every
; entry named WORD on a page of its own.
(def %help-cmd!
  (fn (_ st args)
    (def word (if (null? args) () (first args)))
    (def i (if (null? word) () (List index-of word (help-topics))))
    (match
      ((null? word) (%browse! st 0 0))
      ((not (null? i)) (%browse! st (+ i 1) 0))
      (#t ((fn (_ lines)
             (if (null? lines) (edit-message! st (Str8 append "No help on " word "; :help lists the topics."))
               (do (%put! st %browse (pair () 0)) (%put! st %help lines) (edit-message! st %browse-hint))))
           (help-on word))))))

; A key while the help is shown: up and down, PgUp and PgDn, Space, Home
; and End scroll it; right, left, Tab, n and p turn to the next topic or
; the one before; any other key closes it.
(def %browse-key!
  (fn (_ st key)
    (def page (first (%get st %browse)))
    (def row (rest (%get st %browse)))
    (def at (if (null? page) 0 page))
    (def scroll! (fn (_ r) (if (null? page) (%put! st %browse (pair () (%max 0 (%min r (- (List length (%get st %help)) 2)))))
                             (%browse! st page r))))
    (match
      ((eq? key (lit up)) (scroll! (- row 1)))
      ((eq? key (lit down)) (scroll! (+ row 1)))
      ((eq? key (lit page-up)) (scroll! (- row 16)))
      ((if (eq? key (lit page-down)) #t (%is? key " ")) (scroll! (+ row 16)))
      ((eq? key (lit home)) (scroll! 0))
      ((eq? key (lit end)) (scroll! (List length (%get st %help))))
      ((if (eq? key (lit right)) #t (if (eq? key (lit complete)) #t (%is? key "n"))) (%browse! st (+ at 1) 0))
      ((if (eq? key (lit left)) #t (%is? key "p")) (%browse! st (- at 1) 0))
      (#t (do (%put! st %browse ()) (%put! st %help #f) (edit-message! st ""))))))

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


(provide tracker/edit edit-make edit-feed! edit-settle! edit-tick! edit-key! edit-history-open!
  %page-hints %song-settings %samples %envelope %instrument-form %picked-instrument %write-form %wave-name
  %picked-sample %sample-args %sound %sample-fields %field-value %heard-pattern %struck %input-field)
