; # x-tracker -- a music tracker on x-lang
;
; ## tracker/node.x -- .xon text as nodes that keep every byte
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Text is read by a Lexer whose rules claim every byte: strings, comments,
; parentheses, blanks and atoms.  The tokens' texts put end to end are the
; text, so a form's text is the tokens between its parentheses and a file
; can be written back as it was read.  A node is a token, (TAG TEXT) with
; TAG str, comment, space or atom, or a form, (list NODES).

(module tracker/node)

(import x/reader/lexer)
(import x/codec/xon)
(import x/core/doors int+ int- int* int< int= str-byte-len str-byte-ref str-byte-sub str->sym)

(def %nd-fail (fn (_ what) (Err raise (lit value) (Str8 append "x-tracker: " what) ())))

; Every byte but a blank, a parenthesis, a quote or a semicolon.
(def %nd-atom (list 33 (pair 35 39) (pair 42 58) (pair 60 255)))

(def %nd-lexer-made ())
(def %nd-lexer
  (fn (_)
    (when (null? %nd-lexer-made)
      (set! %nd-lexer-made
        (Lexer make (list (Lexer quoted (lit str) 34 34 92)
                          (Lexer until (lit comment) ";" "\n" (lit to-end))
                          (Lexer table (lit paren) (list "(" ")"))
                          (Lexer run (lit space) " \t\r\n" " \t\r\n")
                          (Lexer run (lit atom) %nd-atom %nd-atom)
                          (Lexer any (lit bad))))))
    %nd-lexer-made))

; The work per token and per node is first, rest and the byte doors, no
; class send: a send is some two hundred objects, and a song file is
; thousands of tokens.

(def %nd-text (fn (_ t) (first (rest t))))

; The tokens of TEXT, (TAG TEXT) each, their texts the whole of TEXT: the
; space the Lexer adds at the end is taken off again.  A newline at the
; very end comes back unclaimed, as the any rule's token: it is a blank
; like any other.  Raises a label 'value for a string never closed.
(def node-tokens
  (fn (_ text)
    (def blank? (fn (self s i) (if (int< i (str-byte-len s)) (if (int< 32 (str-byte-ref s i)) #f (self s (int+ i 1))) #t)))
    ; The tokens with the blanks mended, reversed, and their length.
    (def walk
      (fn (self ts acc n)
        (if (null? ts) (pair acc n)
          ((fn (_ t)
             (self (rest ts) (pair (if (if (eq? (first t) (lit bad)) (blank? (%nd-text t) 0) #f) (list (lit space) (%nd-text t)) t) acc)
                   (int+ n (str-byte-len (%nd-text t)))))
           (first ts)))))
    (def r (walk (if (int= 0 (str-byte-len text)) () ((%nd-lexer) read-str text)) () 0))
    (def size (str-byte-len text))
    (match ((int= (rest r) size) (List reverse (first r)))
           ((int= (rest r) (int+ size 1))
             ((fn (_ last)
                (def cut (str-byte-sub (%nd-text last) 0 (int- (str-byte-len (%nd-text last)) 1)))
                (List reverse (if (int= 0 (str-byte-len cut)) (rest (first r)) (pair (list (first last) cut) (rest (first r))))))
              (first (first r))))
           (#t (%nd-fail "a string is never closed")))))

(def %nd-reverse (fn (self xs acc) (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))

; Nodes from TOKS up to a ")" or the end: (NODES . REST), REST starting
; at that ")" or nil.
(def %nd-nodes
  (fn (self toks acc)
    (if (null? toks) (pair (%nd-reverse acc ()) ())
      ((fn (_ t)
         (match ((eq? (first t) (lit bad))
                  (%nd-fail (if (str=? (%nd-text t) "\"") "a string is never closed" (Str8 append "a stray " (%nd-text t)))))
                ((not (eq? (first t) (lit paren))) (self (rest toks) (pair t acc)))
                ((str=? (%nd-text t) ")") (pair (%nd-reverse acc ()) toks))
                (#t ((fn (_ inner)
                       (when (null? (rest inner)) (%nd-fail "a ( is never closed"))
                       (self (rest (rest inner)) (pair (list (lit list) (first inner)) acc)))
                     (self (rest toks) ())))))
       (first toks)))))

; TEXT as nodes.  Raises a label 'value for parentheses that do not pair.
(def node-read
  (fn (_ text)
    (def r (%nd-nodes (node-tokens text) ()))
    (unless (null? (rest r)) (%nd-fail "a ) closes nothing"))
    (first r)))

(def node-form? (fn (_ n) (eq? (first n) (lit list))))

; A node's text: its pieces gathered, then put together once.
(def %nd-each (fn (loop f ns acc) (if (null? ns) acc (loop f (rest ns) (f (first ns) acc)))))
(def %nd-pieces
  (fn (self n acc)
    (if (node-form? n)
      (pair ")" (%nd-each self (%nd-text n) (pair "(" acc)))
      (pair (%nd-text n) acc))))

(def node-text (fn (_ n) (%str-concat (%nd-reverse (%nd-pieces n ()) ()))))

(def %nd-blank? (fn (_ c) (if (eq? (first c) (lit space)) #t (eq? (first c) (lit comment)))))

; A form node's children that are not blanks or comments.
(def node-parts
  (fn (_ n)
    ((fn (self cs acc) (if (null? cs) (%nd-reverse acc ()) (self (rest cs) (if (%nd-blank? (first cs)) acc (pair (first cs) acc)))))
     (%nd-text n) ())))

; The first atom of a form node, as a string, or "".
(def node-head
  (fn (_ n)
    (def parts (node-parts n))
    (if (if (null? parts) #f (eq? (first (first parts)) (lit atom))) (%nd-text (first parts)) "")))

(def %nd-digit? (fn (_ b) (if (int< b 48) #f (int< b 58))))

; Whether S from I on is digits, at least one.
(def %nd-digits?
  (fn (_ s i)
    ((fn (self k) (if (int< k (str-byte-len s)) (if (%nd-digit? (str-byte-ref s k)) (self (int+ k 1)) #f) #t))
     i)))

(def %nd-integer
  (fn (_ s i)
    ((fn (self k acc) (if (int< k (str-byte-len s)) (self (int+ k 1) (int+ (int* acc 10) (int- (str-byte-ref s k) 48))) acc))
     i 0)))

(def %nd-read (fn (_ text) (first (Xon parse text))))

; An atom's value: an integer, a symbol, or what the reader makes of the
; rest (a fraction, #t).
(def %nd-atom-value
  (fn (_ s)
    (def b (str-byte-ref s 0))
    (def signed (if (int= b 45) (int< 1 (str-byte-len s)) #f))
    (match ((if (%nd-digit? b) (%nd-digits? s 0) #f) (%nd-integer s 0))
           ((if signed (%nd-digits? s 1) #f) (int- 0 (%nd-integer s 1)))
           ((if (%nd-digit? b) #t (if (int= b 35) #t (if signed (%nd-digit? (str-byte-ref s 1)) #f))) (%nd-read s))
           (#t (str->sym s)))))

; A string token's value: its bytes between the quotes, read by the
; reader only when it holds an escape.
(def %nd-string-value
  (fn (_ s)
    (def inner (str-byte-sub s 1 (int- (str-byte-len s) 2)))
    (if ((fn (self k) (if (int< k (str-byte-len inner)) (if (int= (str-byte-ref inner k) 92) #t (self (int+ k 1))) #f)) 0)
      (%nd-read s)
      inner)))

; A node's value, as the reader would read its text: a form a list of
; its parts' values.
(def node-value
  (fn (self n)
    (match ((node-form? n) ((fn (walk ps acc) (if (null? ps) (%nd-reverse acc ()) (walk (rest ps) (pair (self (first ps)) acc))))
                            (node-parts n) ()))
           ((eq? (first n) (lit str)) (%nd-string-value (%nd-text n)))
           (#t (%nd-atom-value (%nd-text n))))))

(provide tracker/node node-tokens node-read node-form? node-text node-parts node-head node-value)
