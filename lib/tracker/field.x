; # x-tracker -- a music tracker on x-lang
;
; ## tracker/field.x -- a line typed: its editing, its history, its colours
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A line typed at the foot of the screen, a command, a cell, its effects
; or an instrument's text, edited as x-lang's own lines are: the buffer
; and its cursor are x/repl/edit's Edit, moved by character, by word and
; to either end, killed and yanked, and Up and Down walk the lines of its
; kind typed before.  ctrl-r and ctrl-s search them back and forward as
; each key is typed; Enter takes the match, ctrl-g leaves the search, and
; any other key takes the match for editing.
;
; The history is a list for each kind of line, newest first, kept in a
; file, each line KIND TEXT: read when the editor starts, a line added as
; each is entered.  The file is $XDG_STATE_HOME/x/tracker-history, else
; ~/.local/state/x/tracker-history.
;
; Nothing here reads or writes the terminal: a field is drawn on a Screen
; row, its text in the styles its spans give, the cursor's cell in the
; cursor's style, and the column of the cursor answered.

(module tracker/field)

(import x/type/vector)
(import x/sys/file)
(import x/repl/edit)
(import x/core/doors str->sym)

; The lines kept of each kind.
(def %fd-keep 500)

; --- a field -----------------------------------------------------------------

; A field: 0 its Edit, 1 its kind, 2 the search, (QUERY DIR HIT) or nil,
; HIT (INDEX . OFFSET) or nil.
(def field-make
  (fn (_ kind text hist)
    (def e (Edit make hist))
    (e set-text! text)
    (Vector of e kind ())))

(def field-kind (fn (_ f) (Vector ref 1 f)))

; The line in the buffer, a search's match aside.
(def field-line (fn (_ f) ((Vector ref 0 f) text)))
(def %fd-edit (fn (_ f) (Vector ref 0 f)))
(def %fd-search (fn (_ f) (Vector ref 2 f)))

; The text and the cursor shown: a search's match while one is found.
(def field-text
  (fn (_ f)
    (def s (%fd-search f))
    (def hit (if (null? s) () (List ref 2 s)))
    (if (null? hit) ((%fd-edit f) text) (List ref (first hit) ((%fd-edit f) hist)))))

(def field-point
  (fn (_ f)
    (def s (%fd-search f))
    (def hit (if (null? s) () (List ref 2 s)))
    (if (null? hit) ((%fd-edit f) point) (rest hit))))

; The lines of its kind, newest first, the one entered included once
; field-remember! has taken it.
(def field-history (fn (_ f) ((%fd-edit f) hist)))
(def field-remember! (fn (_ f) ((%fd-edit f) remember! ((%fd-edit f) text)) f))

; The search moved on, QUERY looked for walking DIR (back or forward)
; from the entry after the one found.
(def %fd-find!
  (fn (_ f query dir)
    (def e (%fd-edit f))
    (def s (%fd-search f))
    (def hit (if (null? s) () (List ref 2 s)))
    (def from (match ((null? hit) (if (eq? dir (lit back)) 0 (- (List length (e hist)) 1)))
                     ((eq? dir (lit back)) (+ (first hit) 1))
                     (#t (- (first hit) 1))))
    (def found (if (str=? query "") () (e search query from dir)))
    (Vector set! 2 (list query dir (if (null? found) hit found)) f)))

; The match taken into the buffer, the search left.
(def %fd-take!
  (fn (_ f)
    (def s (%fd-search f))
    (def hit (if (null? s) () (List ref 2 s)))
    (unless (null? hit) ((%fd-edit f) jump! (first hit) (rest hit)))
    (Vector set! 2 () f)))

; KEY to a search: answers what the field answers, or (lit again) for a
; key the search ended that the field is then to take.
(def %fd-search-key!
  (fn (_ f key)
    (def s (%fd-search f))
    (def query (first s))
    (match
      ((eq? key (lit search-back)) (do (%fd-find! f query (lit back)) ()))
      ((if (eq? key (lit search-forward)) #t (eq? key (lit ctrl-s))) (do (%fd-find! f query (lit forward)) ()))
      ((eq? key (lit abort)) (do (Vector set! 2 () f) ()))
      ((eq? key (lit enter)) (do (%fd-take! f) (lit enter)))
      ((eq? key (lit backspace))
        (do (Vector set! 2 (list "" (List ref 1 s) ()) f)
            (%fd-find! f (if (str=? query "") "" (Str8 sub 0 (- (Str8 length query) 1) query)) (List ref 1 s))
            ()))
      ((str? key) (do (Vector set! 2 (list (Str8 append query key) (List ref 1 s) (List ref 2 s)) f)
                      ; The entry found kept while it still matches.
                      ((fn (_ hit)
                         (unless (if (null? hit) #f (not (null? (Str8 index-of (Str8 append query key) (List ref (first hit) ((%fd-edit f) hist))))))
                           (do (Vector set! 2 (list (Str8 append query key) (List ref 1 s) ()) f)
                               (%fd-find! f (Str8 append query key) (List ref 1 s)))))
                       (List ref 2 s))
                      ()))
      (#t (do (%fd-take! f) (lit again))))))

; KEY taken by field F: answers (lit enter) when the line is entered,
; (lit cancel) when it is left, or nil.  Backspace on an empty line
; leaves it, as Escape does.
(def field-key!
  (fn (self f key)
    (def e (%fd-edit f))
    (if (not (null? (%fd-search f)))
      ((fn (_ r) (if (eq? r (lit again)) (self f key) r)) (%fd-search-key! f key))
      (match
        ((eq? key (lit enter)) (lit enter))
        ((List includes? key (list (lit escape) (lit interrupt) (lit abort))) (lit cancel))
        ((eq? key (lit backspace)) (if (e empty?) (lit cancel) (do (e del-back!) ())))
        ((eq? key (lit delete)) (do (e del!) ()))
        ((eq? key (lit left)) (do (e back!) ()))
        ((eq? key (lit right)) (do (e forward!) ()))
        ((eq? key (lit home)) (do (e bol!) ()))
        ((eq? key (lit end)) (do (e eol!) ()))
        ((List includes? key (list (lit word-left) (lit ctrl-left) (lit alt-b))) (do (e back-word!) ()))
        ((List includes? key (list (lit word-right) (lit ctrl-right) (lit alt-f))) (do (e forward-word!) ()))
        ((eq? key (lit kill-bol)) (do (e kill-bol!) ()))
        ((eq? key (lit kill-eol)) (do (e kill-eol!) ()))
        ((eq? key (lit kill-word)) (do (e kill-word-back!) ()))
        ((List includes? key (list (lit yank) (lit ctrl-y))) (do (e yank!) ()))
        ((eq? key (lit up)) (do (e earlier!) ()))
        ((eq? key (lit down)) (do (e later!) ()))
        ((eq? key (lit search-back)) (do (Vector set! 2 (list "" (lit back) ()) f) ()))
        ((if (eq? key (lit search-forward)) #t (eq? key (lit ctrl-s))) (do (Vector set! 2 (list "" (lit forward) ()) f) ()))
        ((str? key) (do (e insert! key) ()))
        (#t ())))))

; --- drawing -------------------------------------------------------------------

; F drawn on SCREEN at ROW from column 0, COLS wide: PROMPT in the style
; PROMPT-STYLE (a search's own prompt in its place), the text in the
; styles SPANS gives, (fn (_ text) ((OFFSET LENGTH STYLE) ...)), the
; cell at the cursor in CURSOR-STYLE.  A line too long for the screen
; shows the part about the cursor, ... for what is before it.  Answers
; the cursor's column.
(def field-draw!
  (fn (_ f screen row cols prompt prompt-style spans cursor-style)
    (def s (%fd-search f))
    (def head (if (null? s) prompt
                (Str8 append "(" (if (eq? (List ref 1 s) (lit back)) "search back" "search forward") " `" (first s) "'"
                  (if (if (null? (List ref 2 s)) (not (str=? (first s) "")) #f) " not found" "") "): ")))
    (def text (field-text f))
    (def n (Str8 length text))
    (def at (%fd-min (field-point f) n))
    (def room (%fd-max 4 (- (- cols 1) (Str8 length head))))
    (def from (if (< at (- room 1)) 0 (- at (- room 4))))
    (def shown-from (if (= from 0) 0 (+ from 0)))
    (def shown-n (if (= from 0) (%fd-min n room) (%fd-min (- n from) (- room 3))))
    (def left (+ (Str8 length head) (if (= from 0) 0 3)))
    (Screen put screen row 0 head prompt-style)
    (when (< 0 from) (Screen put screen row (Str8 length head) "..." 0))
    (Screen put screen row left (Str8 sub shown-from shown-n text) 0)
    (List for-each
      (fn (_ sp)
        (def o (%fd-max (first sp) shown-from))
        (def e (%fd-min (+ (first sp) (List ref 1 sp)) (+ shown-from shown-n)))
        (when (< o e) (Screen put screen row (+ left (- o shown-from)) (Str8 sub o (- e o) text) (List ref 2 sp))))
      (if (null? spans) () (spans text)))
    (def col (+ left (- at shown-from)))
    (Screen put screen row col (if (< at n) (Str8 sub at 1 text) " ") cursor-style)
    (%fd-min (- cols 1) col)))

(def %fd-min (fn (_ a b) (if (< a b) a b)))
(def %fd-max (fn (_ a b) (if (< a b) b a)))

; --- the history file ------------------------------------------------------------

; The file the history is kept in, or nil where there is no home.
(def history-path
  (fn (_)
    (def state (Sys getenv "XDG_STATE_HOME"))
    (def home (Sys getenv "HOME"))
    (match ((if (null? state) #f (not (str=? state ""))) (Str8 append state "/x/tracker-history"))
           ((null? home) ())
           (#t (Str8 append home "/.local/state/x/tracker-history")))))

; The kind a line's history is kept under: an effect of the song's mix
; with the others of its kind, an F4 prop's value with the props'.
(def history-kind (fn (_ kind) (if (pair? kind) (if (eq? (first kind) (lit prop)) (lit prop) (lit effect)) kind)))

; The history read from PATH: ((KIND LINE ...) ...), each kind's lines
; newest first, %fd-keep of them; nil for a file there is not.  A line
; not of the form KIND TEXT is passed over.
(def history-read
  (fn (_ path)
    (if (if (null? path) #t (not (File exists? path))) ()
      (List fold
        (fn (_ h line)
          ((fn (_ sp)
             (if (if (null? sp) #t (= sp 0)) h
               ((fn (_ kind text)
                  ((fn (_ e)
                     (if (null? e) (pair (list kind text) h)
                       (pair (pair kind (pair text (List take (- %fd-keep 1) (List filter (fn (_ t) (not (str=? t text))) (rest e)))))
                             (List filter (fn (_ x) (not (eq? (first x) kind))) h))))
                   (List find (fn (_ x) (eq? (first x) kind)) h)))
                (str->sym (Str8 sub 0 sp line)) (Str8 sub (+ sp 1) (- (Str8 length line) (+ sp 1)) line))))
           (Str8 index-of " " line)))
        () (guard (e ()) (File read-lines path))))))

; The lines of KIND in history H, newest first.
(def history-of
  (fn (_ h kind)
    ((fn (_ e) (if (null? e) () (rest e))) (List find (fn (_ x) (eq? (first x) kind)) h))))

; H with the lines of KIND made LINES.
(def history-put
  (fn (_ h kind lines)
    (pair (pair kind (List take %fd-keep lines)) (List filter (fn (_ x) (not (eq? (first x) kind))) h))))

; DIR and the directories above it made, where they are not.
(def %fd-mkdirs
  (fn (self dir)
    (unless (if (str=? dir "") #t (File exists? dir))
      (do ((fn (_ cut) (unless (null? cut) (self (Str8 sub 0 cut dir)))) (Str8 last-index-of "/" dir))
          (File mkdir dir)))))

; TEXT of KIND added to the file at PATH, its directory made first, the
; file read and written by its owner only; a file that cannot be written
; is let be.
(def history-add!
  (fn (_ path kind text)
    (unless (if (null? path) #t (str=? (Str8 trim text) ""))
      (guard (e ())
        (do (%fd-mkdirs (Str8 sub 0 (Str8 last-index-of "/" path) path))
            ((fn (_ fd line)
               (when (< -1 fd) (do (File write fd line (Str8 length line)) (File close fd))))
             (File open path (list (lit wronly) (lit creat) (lit append)) 384)
             (Str8 append (symbol->str kind) " " (Str8 replace "\n" " " text) "\n")))))))

(provide tracker/field field-make field-kind field-line field-text field-point field-history field-remember! field-key! field-draw!
  history-path history-kind history-read history-of history-put history-add!)
