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

; Whether any song of DOC has been changed.
(def file-changed?
  (fn (_ doc) (List any? (fn (_ p) (if (eq? (first p) (lit song)) (List ref 3 p) #f)) doc)))

; DOC with every song as written.
(def file-written
  (fn (_ doc)
    (List map (fn (_ p) (if (if (eq? (first p) (lit song)) (List ref 3 p) #f)
                          (list (lit song) (song-text (List ref 2 p)) (List ref 2 p) #f) p))
      doc)))

; The (wave NAME AMP ...) forms of DOC.
(def file-waves
  (fn (_ doc)
    (List map (fn (_ p) (first (Xon parse (List ref 1 p))))
      (List filter (fn (_ p) (if (eq? (first p) (lit form)) (str=? (List ref 2 p) "wave") #f)) doc))))

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
  file-waves file-read file-write!)
