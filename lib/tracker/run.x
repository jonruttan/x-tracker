; # x-tracker -- a music tracker on x-lang
;
; ## lib/tracker/run.x -- the entry
;
; @description `x -l tracker -- [OPTIONS] [edit | play | list] FILE`.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Importing this module sets the session up; main runs the command the
; operands name, or leaves the REPL to start when there are none.
(module tracker/run)
(import tracker/base tracker-main)

(set! %lang-name "tracker")
(set! %repl-prompt "tracker> ")

; The operands: what follows the "--" after the launcher's own options.
; x-os's launcher passes the engine's own flags ahead of them, with no
; "--" between; they are left out, so `x -l tracker` there is a REPL too.
(def %engine-flag?
  (fn (_ a) (List any? (fn (_ f) (str=? a f)) (list "--batch" "--quiet" "--no-color"))))
(def %operands
  (fn (self l) (if (if (null? l) #f (%engine-flag? (first l))) (self (rest l)) l)))

(def main
  (fn (_)
    (let ((ops (%operands (rest (Sys args (lit program))))))
      (unless (null? ops) (Sys exit (tracker-main ops))))))

(provide tracker/run main)
