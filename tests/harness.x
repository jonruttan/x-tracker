; # x-tracker -- a music tracker on x-lang
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The lang kit's generator writes tests/lib/harness.gen.x: the dialect
; lang.xon declares, the bundle's root on the import path, then this file.
(import tracker/base)
(import x/sys/gc)

; Each line of TEXT written as a line of its own, so a spec's expected
; output can be the whole of it.
(def spec-lines
  (fn (_ text) (List for-each (fn (_ l) (display l) (display "\n")) (Str8 split "\n" text))))

; The editor's helpers: ROWS of SCREEN as text, right-trimmed and joined
; by newlines; ST drawn on SCREEN, the heap collected first, as the
; terminal's loop does; KEYS pressed in ST, a string's characters each a
; key, a symbol a key of its own.
(import x/tui/screen)
(import x/tui/style)
(import x/sys/file)
(import x/codec/xon)

(def spec-rows
  (fn (_ screen rows)
    (Str8 join "\n" (List map (fn (_ i) (Str8 trim-right (Screen row-text screen i))) rows))))

(def spec-draw!
  (fn (_ st screen)
    (Heap collect)
    (edit-draw! st screen)))

(def spec-keys!
  (fn (_ st keys)
    (List for-each
      (fn (_ k) (if (str? k) (List for-each (fn (_ i) (edit-key! st (Str8 sub i 1 k))) (List range 0 (Str8 length k)))
                  (edit-key! st k)))
      keys)))

; The song ST edits, as text.
(def spec-song (fn (_ st) (song-text (edit-song st))))

; A stand-in for Sdl's audio messages: a stream's bytes put on it and
; counted, played only as a spec says (spec-play!).
(import x/type/vector)
(import x/type/class)
(def spec-streams (Vector make 4 0))
(def spec-opened (Vector make 1 0))
(def-class SpecAudio ()
  (static
    (method audio-open (self rate chans)
      ((fn (_ n) (Vector set! 0 (+ n 1) spec-opened) n) (Vector ref 0 spec-opened)))
    (method audio-put! (self s buf n) (Vector set! s (+ (Vector ref s spec-streams) n) spec-streams) n)
    (method audio-queued (self s)
      (Vector ref s spec-streams))
    (method audio-clear! (self s) (Vector set! s 0 spec-streams) s)
    (method audio-close (self s) ())))
; The stand-in, its streams empty.
(def spec-front
  (fn (_)
    (Vector set! 0 0 spec-opened)
    (List for-each (fn (_ i) (Vector set! i 0 spec-streams)) (List range 0 4))
    SpecAudio))
(def spec-tune
  (song-parse "(song \"s\" (bpm 240) (rows 4)\n  (instrument a (wave sine) (env (0 0) (5 60) (100 0)) (release 20))\n  (pattern p (a \"C4 . E4 .\"))\n  (pattern q (a \"G4 . . .\"))\n  (order p q))"))

; N bytes of every stream of the stand-in played: the time a speaker
; takes over them passed.
(def spec-play!
  (fn (_ n)
    (List for-each (fn (_ i) (Vector set! i (if (< (Vector ref i spec-streams) n) 0 (- (Vector ref i spec-streams) n)) spec-streams))
      (List range 0 4))))
