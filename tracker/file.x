; # x-tracker -- a music tracker on x-lang
;
; ## tracker/file.x -- a .xon file of songs, read and written back
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A file is read into a document: its top-level forms and the text
; between them (blanks and comments), each kept as the text it was
; (tracker/node).  A (song ...) form is also read into a song
; (tracker/song) the editor can change.  Written back, every piece is its
; own text again but a song that was changed, which is written from the
; song; so a file of songs and other forms, x-roguelike's music.xon among
; them, keeps its comments and layout everywhere the editor did not touch.
;
; A document is a list of pieces: (gap TEXT), (form TEXT HEAD) or (song
; TEXT SONG CHANGED), HEAD the form's first atom as a string.

(module tracker/file)

(import x/codec/xon)
(import x/sys/file)
(import tracker/node node-read node-form? node-text node-head)
(import tracker/song song-from-node song-text)

; TEXT as a document.  Raises a label 'value for text that is not forms,
; or a song that is not one.
(def file-parse
  (fn (_ text)
    (List reverse
      (List fold
        (fn (_ acc n)
          (match ((not (node-form? n))
                   (if (if (null? acc) #f (eq? (first (first acc)) (lit gap)))
                     (pair (list (lit gap) (Str8 append (List ref 1 (first acc)) (node-text n))) (rest acc))
                     (pair (list (lit gap) (node-text n)) acc)))
                 ((str=? (node-head n) "song") (pair (list (lit song) (node-text n) (song-from-node n) #f) acc))
                 (#t (pair (list (lit form) (node-text n) (node-head n)) acc))))
        () (node-read text)))))

; The document as text: each piece as it was read, a changed song as
; the song.
(def file-text
  (fn (_ doc)
    (Str8 join ""
      (List map (fn (_ p) (if (if (eq? (first p) (lit song)) (List ref 3 p) #f) (song-text (List ref 2 p)) (List ref 1 p)))
        doc))))

; The songs of DOC, in order.
(def file-songs
  (fn (_ doc) (List map (fn (_ p) (List ref 2 p)) (List filter (fn (_ p) (eq? (first p) (lit song))) doc))))

; DOC with its Ith song SONG, marked changed.
(def file-song!
  (fn (_ doc i song)
    ((fn (self ps k)
       (match ((null? ps) ())
              ((not (eq? (first (first ps)) (lit song))) (pair (first ps) (self (rest ps) k)))
              ((= k i) (pair (list (lit song) (List ref 1 (first ps)) song #t) (rest ps)))
              (#t (pair (first ps) (self (rest ps) (+ k 1))))))
     doc 0)))

; DOC with SONG added at its end, after a blank line.
(def file-add-song
  (fn (_ doc song)
    (def tail (if (null? doc) "" (List ref 1 (List last doc))))
    (def gap (match ((null? doc) "") ((Str8 ends? "\n\n" tail) "") ((Str8 ends? "\n" tail) "\n") (#t "\n\n")))
    (List append doc
      (if (str=? gap "") () (list (list (lit gap) gap)))
      (list (list (lit song) "" song #t) (list (lit gap) "\n")))))

; Whether piece P has been changed: a song changed, or a form made.
(def %fl-changed?
  (fn (_ p) (if (< (List length p) 4) #f (eq? (List ref 3 p) #t))))

; Whether any song or form of DOC has been changed.
(def file-changed?
  (fn (_ doc) (List any? %fl-changed? doc)))

; DOC with every song and form as written.
(def file-written
  (fn (_ doc)
    (List map (fn (_ p) (match ((not (%fl-changed? p)) p)
                               ((eq? (first p) (lit song)) (list (lit song) (song-text (List ref 2 p)) (List ref 2 p) #f))
                               (#t (List take 3 p))))
      doc)))

(def %fl-wave? (fn (_ p) (if (eq? (first p) (lit form)) (str=? (List ref 2 p) "wave") #f)))

; The (wave NAME AMP ...) forms of DOC.
(def file-waves
  (fn (_ doc)
    (List map (fn (_ p) (first (Xon parse (List ref 1 p)))) (List filter %fl-wave? doc))))

; The (wave NAME AMP ...) form of DOC named NAME, a string, or nil.
(def file-wave
  (fn (_ doc name) (List find (fn (_ w) (str=? (symbol->str (List ref 1 w)) name)) (file-waves doc))))

; DOC with the wave NAME made of the harmonics AMPS, numbers: in place of
; its form when it has one, or else on a line after its last wave, or
; else before its first song.
(def file-set-wave
  (fn (_ doc name amps)
    (def piece (list (lit form) (Str8 append "(wave " name (Str8 join "" (List map (fn (_ a) (Str8 append " " (Str8 str a))) amps)) ")") "wave" #t))
    (def named? (fn (_ p) (if (%fl-wave? p) (str=? (symbol->str (List ref 1 (first (Xon parse (List ref 1 p))))) name) #f)))
    (def last-wave (List fold (fn (_ at i) (if (%fl-wave? (List ref i doc)) i at)) () (List range 0 (List length doc))))
    (def first-song (List find-index (fn (_ p) (eq? (first p) (lit song))) doc))
    (match
      ((List any? named? doc) (List map (fn (_ p) (if (named? p) piece p)) doc))
      ((not (null? last-wave))
        (List append (List take (+ last-wave 1) doc) (list (list (lit gap) "\n") piece) (List drop (+ last-wave 1) doc)))
      ((not (null? first-song))
        (List append (List take first-song doc) (list piece (list (lit gap) "\n\n")) (List drop first-song doc)))
      (#t (List append doc (list piece (list (lit gap) "\n")))))))

; The document in the file at PATH, read whole as an editor does; an
; empty one when there is no file.
(def file-read
  (fn (_ path)
    (if (File exists? path) (file-parse (File read-all path)) ())))

; DOC written to PATH: answers the document with every song as written.
(def file-write!
  (fn (_ doc path)
    (File write-all path (file-text doc))
    (file-written doc)))

(provide tracker/file file-parse file-text file-songs file-song! file-add-song file-changed? file-written
  file-waves file-wave file-set-wave file-read file-write!)
