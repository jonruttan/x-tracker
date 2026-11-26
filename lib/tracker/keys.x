; # x-tracker -- a music tracker on x-lang
;
; ## tracker/keys.x -- the keys a terminal sends, Alt, Shift and Ctrl among them
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; x/repl/term's Term key decodes what a line editor needs: a CSI key's
; modifiers are dropped but for Ctrl on the arrows, Escape and a letter
; is Escape, and Insert is not a key.  A tracker in the way of Impulse
; Tracker needs them: Alt and a letter, Shift and an arrow, Alt and a
; function key.  This reads the bytes those keys are sent as, and hands
; every other key to Term key as it was sent.
;
; A key with modifiers is a symbol of their names and the key's, in the
; order shift alt ctrl: 'shift-up, 'alt-f9, 'ctrl-page-up, 'shift-alt-q.
; Alt and a character is 'alt- and the character: 'alt-b, 'alt-B for Alt
; and Shift and b, 'alt-0.  Shift and Tab is 'shift-tab; Insert 'insert.
; Ctrl and S, Q and Z, which Term key leaves unbound or takes for a
; line's search, are 'ctrl-s, 'ctrl-q and 'ctrl-z.  The mouse, once
; Term mouse! asks for it, is a list: (mouse ACTION BUTTON ROW COL MODS).

(module tracker/keys)

(import x/repl/term)
(import x/core/doors int& str->sym)

; The name a CSI modifier parameter gives, M as the terminal sends it:
; one more than the sum of shift 1, alt 2 and ctrl 4.
(def %ky-mods
  (fn (_ m)
    (def bits (- m 1))
    (Str8 append (if (= 1 (int& bits 1)) "shift-" "") (if (= 2 (int& bits 2)) "alt-" "") (if (= 4 (int& bits 4)) "ctrl-" ""))))

; KEY, a symbol, with the modifier names PREFIX before its own.
(def %ky-named (fn (_ prefix key) (if (str=? prefix "") key (str->sym (Str8 append prefix (symbol->str key))))))

; The parameter bytes PARAMS split at their ';' into numbers: (1 5) for
; "1;5", () for none.
(def %ky-numbers
  (fn (_ params)
    ((fn (self ps n acc)
       (match ((null? ps) (List reverse (if (null? n) acc (pair n acc))))
              ((= (first ps) 59) (self (rest ps) () (pair (if (null? n) 0 n) acc)))
              ((if (< 47 (first ps)) (< (first ps) 58) #f)
                (self (rest ps) (+ (* 10 (if (null? n) 0 n)) (- (first ps) 48)) acc))
              (#t (self (rest ps) n acc))))
     params () ())))

; A CSI sequence's key, its final byte FINAL and parameters PARAMS: Term's
; name for the key, then the modifiers the second parameter gives.  A
; report of the mouse, ESC [ < and its numbers, is Term's (mouse ...).
(def %ky-csi
  (fn (_ final params)
    (if (if (pair? params) (= (first params) 60) #f) (Term %mouse final (rest params)) (%ky-csi-key final params))))

(def %ky-csi-key
  (fn (_ final params)
    (def ns (%ky-numbers params))
    (def m (if (< 1 (List length ns)) (List ref 1 ns) 1))
    (def key (match ((= final 90) (lit shift-tab))
                    ((= final 126) (if (if (pair? ns) (= (first ns) 2) #f) (lit insert) (Term %tilde (if (null? ns) 0 (first ns)))))
                    (#t (Term %csi-final final ()))))
    (if (eq? key (lit shift-tab)) key (%ky-named (%ky-mods m) key))))

; The rest of a CSI sequence from READ-BYTE: its parameters up to its
; final byte.
(def %ky-csi-read
  (fn (_ read-byte)
    ((fn (self params)
       ((fn (_ b)
          (match ((null? b) (lit escape))
                 ((if (< 47 b) (< b 64) #f) (self (pair b params)))
                 (#t (%ky-csi b (List reverse params)))))
        (read-byte)))
     ())))

; The key after an Escape from READ-BYTE.
(def %ky-escape
  (fn (_ read-byte)
    ((fn (_ b)
       (match ((null? b) (lit escape))
              ((= b 91) (%ky-csi-read read-byte))
              ((= b 79) (Term %ss3 read-byte))
              ((= b 127) (lit alt-backspace))
              ((= b 27) ((fn (_ k) (if (symbol? k) (%ky-named "alt-" k) k)) (%ky-escape read-byte)))
              ((if (< 31 b) (< b 127) #f) (str->sym (Str8 append "alt-" (bytes->str (list b)))))
              (#t (lit escape))))
     (read-byte))))

; One key from READ-BYTE, a function of no arguments answering a byte or
; nil, as Term key takes it: a string of text, a symbol naming a key, or
; nil at the end of input.
(def keys-read
  (fn (_ read-byte)
    ((fn (_ b)
       (match ((null? b) ())
              ((= b 27) (%ky-escape read-byte))
              ((= b 17) (lit ctrl-q))
              ((= b 19) (lit ctrl-s))
              ((= b 26) (lit ctrl-z))
              ; Any other byte is Term's, given back to it first.
              (#t ((fn (_ given) (Term key (fn (_) (if given (do (set! given #f) b) (read-byte))))) #t))))
     (read-byte))))

(provide tracker/keys keys-read)
