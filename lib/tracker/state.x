; # x-tracker -- a music tracker on x-lang
;
; ## tracker/state.x -- the editor's state, shared by its keys and its drawing
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The state is a Vector; the slots are named here, for tracker/edit,
; which changes it, and tracker/draw, which shows it.

(module tracker/state)

(import x/type/vector)
(import x/core/doors int- int< str-byte-len str-byte-sub)
(import tracker/song song-pattern pattern-rows)
(import tracker/file file-songs)
(import tracker/config config-style config-get)

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
(def %order-at 25)  ; the place picked in the order while O edits it, or nil
(def %mark 26)      ; (ROW . CHANNEL) where the block marked starts, or nil
(def %clip 27)      ; the cells copied, a list of columns, or nil
(def %loop-at 28)   ; the row L marked as a loop's first, or nil
(def %browse 29)    ; (TOPIC . ROW) while ? pages through the help: TOPIC 0 the index, nil none
(def %page 30)      ; the page shown: pattern, samples, instruments, info, orders or song
(def %field 31)     ; the column of the cursor's channel: 0 note, 1 instrument, 2 volume, 3 effect
(def %digit 32)     ; the tens of a number half typed in the instrument or volume column, or nil
(def %mark-end 33)  ; (ROW . CHANNEL) where the block ends, or nil while it follows the cursor
(def %inst-at 34)   ; the instrument picked on the instruments page, from 0
(def %env-at 35)    ; the envelope's point picked there, or nil while the list has the keys
(def %env-held 36)  ; whether that point is picked up, its arrows moving it
(def %setting-at 37) ; the line picked on the song page
(def %sample-at 38) ; the sample picked on the samples page
(def %sample-field 39) ; the setting picked on the samples page, or nil while the list has the keys
(def %sample-cache 40) ; (PATH . SOUND): the file of the sample last drawn, read
(def %sample-peaks 41) ; (PCM COLS PEAKS): its sound drawn, or nil
(def %paused 42) ; (MODE AT PATTERN ROW) where Shift-F8 stopped the playing, or nil
(def %targets 43) ; what the screen last drawn shows where: ((KIND TOP BOTTOM LEFT RIGHT . DATA) ...)
(def %drag 44) ; what a mouse button pressed holds while it is dragged, or nil
(def %input-at 45) ; (INPUT . FIELD): the line typed, INPUT as %input was when it opened, edited (tracker/field)
(def %midi-held 46) ; the MIDI keyboard's keys held down, their note numbers
(def %order-loop 47) ; the places of the order looped, (FROM . TO), or nil
(def %order-loop-at 48) ; the place L marked on F11 as a loop's first, or nil
(def %history 49) ; the lines typed before, ((KIND LINE ...) ...), each kind's newest first
(def %history-path 50) ; the file the history is kept in, or nil
(def %slots 51)

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
; Whether the mouse is to be reported: the setting (mouse on).
(def edit-mouse? (fn (_ st) (config-get (%get st %config) (lit mouse))))
; Whether a line is being typed: a command, a cell, effects or an instrument.
(def edit-typing? (fn (_ st) (not (null? (%get st %input)))))
; Setting NAME of the editor's settings (tracker/config).
(def edit-setting (fn (_ st name) (config-get (%get st %config) name)))

(def %channels
  (fn (_ st)
    (if (null? (%get st %pattern)) () (song-pattern (edit-song st) (%get st %pattern)))))

(def %rows (fn (_ st) (%max 1 (pattern-rows (%channels st)))))

; The rows and channels the block covers, (R0 R1 C0 C1), from the mark
; to its end, or the cursor while it has none; the cursor's cell alone
; when nothing is marked.
(def %block
  (fn (_ st)
    (def m (%get st %mark))
    (def e (%get st %mark-end))
    (def r (%min (if (null? e) (%get st %row) (first e)) (- (%rows st) 1)))
    (def c (%min (if (null? e) (%get st %chan) (rest e)) (- (List length (%channels st)) 1)))
    (if (null? m) (list (%get st %row) (%get st %row) (%get st %chan) (%get st %chan))
      ((fn (_ mr mc) (list (%min mr r) (%max mr r) (%min mc c) (%max mc c)))
       (%min (first m) (- (%rows st) 1)) (%min (rest m) (- (List length (%channels st)) 1))))))

; The style the setting colour NAME gives (tracker/config): looked up
; once a drawing, not once a cell.
(def %style (fn (_ st name) (config-style (%get st %config) name)))

; What the screen drawn shows from row TOP to BOTTOM and column LEFT to
; RIGHT, neither end included: KIND and DATA, as the mouse reads them
; (tracker/edit).  The last put is over those before it.
(def %target!
  (fn (_ st kind top bottom left right data)
    (%put! st %targets (pair (pair kind (pair top (pair bottom (pair left (pair right data))))) (%get st %targets)))))

(def %browse-hint "n p: the next topic, the one before   arrows PgUp PgDn: scroll   any other key: close")

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

(provide tracker/state
  %blanks %pad %doc %path %song %pattern %at %row %chan %top %left %octave %step %msg %input %undo %redo %player %quit %help %warned %heard %follow %pick %stale %borrowed %config %order-at %mark %clip %loop-at %browse %page %field %digit %mark-end %inst-at %env-at %env-held %setting-at %sample-at %sample-field %sample-cache %sample-peaks %paused %targets %drag %input-at %midi-held %order-loop %order-loop-at %history %history-path %slots %get %put! %max %min %same? %num edit-song edit-doc edit-quit? edit-message edit-message! edit-player edit-place edit-mouse? edit-typing? edit-setting %channels %rows %block %style %target! %browse-hint )
