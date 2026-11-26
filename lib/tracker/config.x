; # x-tracker -- a music tracker on x-lang
;
; ## tracker/config.x -- the settings, from the user's file and :set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The user's file is $X_TRACKER_CONFIG, else $XDG_CONFIG_HOME/x/tracker.xon,
; else ~/.config/x/tracker.xon, and an empty X_TRACKER_CONFIG reads none:
; where x/tool/syntax.x finds its theme and syntax files.  It is data, read
; and never evaluated.  Each form is a setting, (NAME VALUE ...), and :set
; NAME VALUE ... in the editor is the same form typed:
;
;   (octave 4)  (step 1)  (follow on)  (backup on)  (undo 200)  (sound on)  (mouse on)
;   (midi on|off|"DEVICE")  (midi-off off)
;   (waves "sounds.xon" ...)
;   (colour NAME ATTRIBUTES FOREGROUND BACKGROUND)
;   (key ACTION KEY ...)
;
; A form that is not a setting is one line on stderr and left out, the
; rest still read; a file that does not read is one line and the
; defaults.
;
; Settings are a Vector: the file read from, the values, the colours as
; styles, the keys bound, the problems the file had, and the paths
; written a backup of this session.

(module tracker/config)

(import x/type/vector)
(import x/sys/file)
(import x/tui/style)
(import x/codec/xon)

(def %cf-file 0)
(def %cf-values 1)    ; ((NAME . VALUE) ...)
(def %cf-colours 2)   ; ((NAME ATTRIBUTES FOREGROUND BACKGROUND STYLE) ...)
(def %cf-keys 3)      ; ((ACTION KEY ...) ...): the actions bound to other keys
(def %cf-problems 4)
(def %cf-backed 5)    ; the paths a backup was written of
(def %cf-slots 6)

(def %cf-get (fn (_ cfg i) (Vector ref i cfg)))
(def %cf-put! (fn (_ cfg i x) (Vector set! i x cfg)))

; --- what there is to set ------------------------------------------------------

; Each setting of one value: (NAME KIND DEFAULT LEAST MOST), KIND number,
; switch, files or device (on, off or a name); START when it is read only as
; the editor starts.
(def %cf-settings
  (list (list (lit octave) (lit number) 4 0 8)
        (list (lit step) (lit number) 1 0 64)
        (list (lit follow) (lit switch) #t)
        (list (lit backup) (lit switch) #t)
        (list (lit undo) (lit number) 200 1 10000)
        (list (lit sound) (lit start-switch) #t)
        (list (lit mouse) (lit switch) #t)
        (list (lit midi) (lit start-device) #t)
        (list (lit midi-off) (lit switch) #f)
        (list (lit waves) (lit files) ())))

; The colours the editor draws with, (NAME ATTRIBUTES FOREGROUND
; BACKGROUND) as Style make takes them.
(def %cf-colour-defaults
  (list (list (lit title) (list (lit reverse)) () ())
        (list (lit empty) (list (lit dim)) () ())
        (list (lit heading) (list (lit bold)) () ())
        (list (lit beat) () 3 ())
        (list (lit off) () 1 ())
        (list (lit effect) () 6 ())
        (list (lit instrument) () 5 ())
        (list (lit volume) () 2 ())
        (list (lit cursor) (list (lit reverse)) () ())
        (list (lit playing) (list (lit bold)) 2 ())
        (list (lit block) () 0 6)))

(def %cf-colour-names
  (list (lit black) (lit red) (lit green) (lit yellow) (lit blue) (lit magenta) (lit cyan) (lit white)))

; The actions keys do, each with the key that does it unbound.  A key
; bound to an action is taken as that key.
(def %cf-actions
  (list (pair (lit command) ":") (pair (lit help) "?") (pair (lit undo) "U") (pair (lit redo) "R")
        (pair (lit play) " ") (pair (lit play-pattern) "p") (pair (lit follow) "F")
        (pair (lit previous) "[") (pair (lit next) "]")
        (pair (lit octave-down) "<") (pair (lit octave-up) ">") (pair (lit step-down) "{") (pair (lit step-up) "}")
        (pair (lit up) (lit up)) (pair (lit down) (lit down)) (pair (lit left) (lit left)) (pair (lit right) (lit right))
        (pair (lit page-up) (lit page-up)) (pair (lit page-down) (lit page-down))
        (pair (lit top) (lit home)) (pair (lit bottom) (lit end)) (pair (lit next-channel) (lit complete))
        (pair (lit edit-cell) (lit enter)) (pair (lit edit-instrument) "E")
        (pair (lit insert-row) "I") (pair (lit delete-row) "D")
        (pair (lit hold) ".") (pair (lit let-go) "-") (pair (lit quit) (lit interrupt))
        (pair (lit order) "O") (pair (lit channel-left) "(") (pair (lit channel-right) ")")
        (pair (lit mark) "V") (pair (lit copy) "Y") (pair (lit cut) "X") (pair (lit paste) "P")
        (pair (lit play-here) "G") (pair (lit loop) "L")
        (pair (lit mute-channel) "M") (pair (lit solo-channel) "S") (pair (lit mute-instrument) "H") (pair (lit solo-instrument) "A")
        (pair (lit tension-down) ";") (pair (lit tension-up) "'") (pair (lit pace-down) "_") (pair (lit pace-up) "+")
        (pair (lit volume-down) "9") (pair (lit volume-up) "0")))

(def %cf-find (fn (_ name alist) (List find (fn (_ e) (eq? (first e) name)) alist)))

; --- making and reading ----------------------------------------------------------

(def %cf-style
  (fn (_ c) (Style make (List ref 1 c) (List ref 2 c) (List ref 3 c))))

; The settings as they are with no file.
(def config-default
  (fn (_)
    (def cfg (Vector make %cf-slots ()))
    (%cf-put! cfg %cf-values (List map (fn (_ s) (pair (first s) (List ref 2 s))) %cf-settings))
    (%cf-put! cfg %cf-colours (List map (fn (_ c) (List append c (list (%cf-style c)))) %cf-colour-defaults))
    cfg))

; The user's file: $X_TRACKER_CONFIG, else $XDG_CONFIG_HOME/x/tracker.xon,
; else ~/.config/x/tracker.xon; nil for an empty X_TRACKER_CONFIG or no
; home.  The file need not exist.
(def config-file
  (fn (_)
    (def o (Sys getenv "X_TRACKER_CONFIG"))
    (def c (Sys getenv "XDG_CONFIG_HOME"))
    (def h (Sys getenv "HOME"))
    (match ((not (null? o)) (if (str=? o "") () o))
           ((not (null? c)) (Str8 append c "/x/tracker.xon"))
           ((null? h) ())
           (#t (Str8 append h "/.config/x/tracker.xon")))))

(def %cf-word
  (fn (_ v)
    (match ((str? v) (Str8 append "\"" v "\""))
           ((symbol? v) (symbol->str v))
           ((null? v) "()")
           ((eq? v #t) "on")
           ((eq? v #f) "off")
           ((pair? v) (Str8 append "(" (Str8 join " " (List map %cf-word v)) ")"))
           (#t (Str8 str v)))))

(def %cf-switch
  (fn (_ v)
    (match ((List includes? v (list #t (lit on) (lit yes) (lit true))) #t)
           ((List includes? v (list #f (lit off) (lit no) (lit false))) #f)
           (#t (lit bad)))))

; A file named in the config file, from its directory; ~/ is the home.
(def %cf-path
  (fn (_ cfg p)
    (def f (%cf-get cfg %cf-file))
    (def slash (if (null? f) () (List find (fn (_ i) (str=? (Str8 sub i 1 f) "/")) (List reverse (List range 0 (Str8 length f))))))
    (def dir (if (null? slash) () (Str8 sub 0 slash f)))
    (match ((Str8 starts? "~/" p) ((fn (_ h) (if (null? h) p (Str8 append h (Str8 sub 1 (- (Str8 length p) 1) p)))) (Sys getenv "HOME")))
           ((Str8 starts? "/" p) p)
           ((null? dir) p)
           (#t (Str8 append dir "/" p)))))

; A colour as Style make takes it: a number, a name, bright-NAME or nil;
; or the symbol bad.
(def %cf-colour
  (fn (_ v)
    (def names (List map symbol->str %cf-colour-names))
    (def plain (if (symbol? v) (List index-of (symbol->str v) names) ()))
    (def bright (if (symbol? v) (List index-of (symbol->str v) (List map (fn (_ n) (Str8 append "bright-" n)) names)) ()))
    (match ((null? v) ())
           ((number? v) (if (if (< v 0) #t (< 255 v)) (lit bad) v))
           ((not (null? plain)) plain)
           ((not (null? bright)) (+ 8 bright))
           (#t (lit bad)))))

; The colour form's ARGS, (NAME ATTRIBUTES [FOREGROUND [BACKGROUND]]), as
; (NAME ATTRIBUTES FOREGROUND BACKGROUND STYLE), or why not.
(def %cf-colour-row
  (fn (_ args)
    (def n (List length args))
    (def name (if (null? args) () (first args)))
    (def attrs (if (< n 2) () (List ref 1 args)))
    (def fg (if (< n 3) () (%cf-colour (List ref 2 args))))
    (def bg (if (< n 4) () (%cf-colour (List ref 3 args))))
    (match
      ((if (null? name) #t (null? (%cf-find name %cf-colour-defaults)))
        (Str8 append "colour NAME ATTRIBUTES FOREGROUND BACKGROUND, NAME one of "
          (Str8 join " " (List map (fn (_ c) (symbol->str (first c))) %cf-colour-defaults))))
      ((if (< n 2) #t (< 4 n)) "colour NAME ATTRIBUTES FOREGROUND BACKGROUND")
      ((not (if (null? attrs) #t (if (pair? attrs) (List all? symbol? attrs) #f)))
        "the attributes are a list of bold dim italic underline reverse strike: (bold), ()")
      ((if (eq? fg (lit bad)) #t (eq? bg (lit bad))) "a colour is 0 to 255, a name (red, bright-blue ...), or ()")
      (#t ((fn (_ style)
             (if (null? style) "the attributes are a list of bold dim italic underline reverse strike: (bold), ()"
               (list name attrs fg bg style)))
           (guard (e ()) (Style make attrs fg bg)))))))

(def %cf-key? (fn (_ k) (if (symbol? k) #t (if (str? k) (= (Str8 length k) 1) #f))))

(def %cf-set-value!
  (fn (_ cfg name v)
    (%cf-put! cfg %cf-values
      (List map (fn (_ e) (if (eq? (first e) name) (pair name v) e)) (%cf-get cfg %cf-values)))))

; The setting FORM, (NAME VALUE ...), made in CFG.  LIVE when the editor
; is running, so a setting read only at the start is refused.  Answers
; nil, or why the form is not a setting.
(def config-set!
  (fn (_ cfg form live)
    (def name (if (pair? form) (first form) ()))
    (def args (if (pair? form) (rest form) ()))
    (def s (%cf-find name %cf-settings))
    (match
      ((not (symbol? name)) "a setting is (NAME VALUE ...)")
      ((eq? name (lit colour))
        ((fn (_ row)
           (if (str? row) row
             (do (%cf-put! cfg %cf-colours
                   (List map (fn (_ e) (if (eq? (first e) (first row)) row e)) (%cf-get cfg %cf-colours)))
                 ())))
         (%cf-colour-row args)))
      ((eq? name (lit key))
        (match ((null? args) "key ACTION KEY ...")
               ((null? (%cf-find (first args) %cf-actions))
                 (Str8 append "no action " (%cf-word (first args)) ": :set lists them"))
               ((not (List all? %cf-key? (rest args))) "a key is one character, \"u\", or a key's name: enter, up, home ...")
               (#t (do (%cf-put! cfg %cf-keys
                         ((fn (_ kept) (if (null? (rest args)) kept (pair args kept)))
                          (List filter (fn (_ b) (not (eq? (first b) (first args))))
                            (List map (fn (_ b) (pair (first b) (List filter (fn (_ k) (not (List includes? k (rest args)))) (rest b))))
                              (%cf-get cfg %cf-keys)))))
                       ()))))
      ((null? s) (Str8 append "no setting " (symbol->str name)))
      ((if live (List includes? (List ref 1 s) (list (lit start-switch) (lit start-device) (lit files))) #f)
        (Str8 append (symbol->str name) " is read as the editor starts: the config file"
          (match ((eq? name (lit waves)) " or -w") ((eq? name (lit sound)) " or -n") (#t ""))))
      ((eq? (List ref 1 s) (lit start-device))
        ((fn (_ v) (if (if (= (List length args) 1) (not (eq? v (lit bad))) #f) (do (%cf-set-value! cfg name v) ())
                     (Str8 append (symbol->str name) " on, off, or a device's name, \"Keystation 49\"")))
         (match ((null? args) (lit bad)) ((str? (first args)) (first args)) (#t (%cf-switch (first args))))))
      ((List includes? (List ref 1 s) (list (lit switch) (lit start-switch)))
        ((fn (_ v) (if (if (= (List length args) 1) (not (eq? v (lit bad))) #f) (do (%cf-set-value! cfg name v) ())
                     (Str8 append (symbol->str name) " on, or off")))
         (if (null? args) (lit bad) (%cf-switch (first args)))))
      ((eq? (List ref 1 s) (lit files))
        (if (List all? str? args) (do (%cf-set-value! cfg name (List map (fn (_ p) (%cf-path cfg p)) args)) ())
          "waves \"FILE\" ...: each file a string"))
      (#t
        (if (if (= (List length args) 1) (if (number? (first args)) (not (if (< (first args) (List ref 3 s)) #t (< (List ref 4 s) (first args)))) #f) #f)
          (do (%cf-set-value! cfg name (first args)) ())
          (Str8 append (symbol->str name) " is a number from " (Str8 str (List ref 3 s)) " to " (Str8 str (List ref 4 s))))))))

; TEXT, a :set line after the word, as a setting: answers nil, or why not.
(def config-set-text!
  (fn (_ cfg text)
    ((fn (_ forms) (if (null? forms) "a setting does not read: :set NAME VALUE ..." (config-set! cfg forms #t)))
     (guard (e ()) (Xon parse text)))))

; The settings in the file at PATH, over the defaults: each form that is
; not a setting left out and why kept as a problem.  No file is the
; defaults.
(def config-read
  (fn (_ path)
    (def cfg (config-default))
    (%cf-put! cfg %cf-file path)
    (unless (if (null? path) #t (not (File exists? path)))
      ((fn (_ forms)
         (if (eq? forms (lit bad))
           (%cf-put! cfg %cf-problems (list (Str8 append path ": unreadable -- the defaults are used")))
           (List for-each
             (fn (_ f) ((fn (_ why) (unless (null? why)
                                      (%cf-put! cfg %cf-problems
                                        (List append (%cf-get cfg %cf-problems) (list (Str8 append path ": " (%cf-word f) ": " why))))))
                        (config-set! cfg f #f)))
             forms)))
       (guard (e (lit bad)) (Xon parse (File read-all path)))))
    cfg))

; The user's settings: config-read of config-file.
(def config-load (fn (_) (config-read (config-file))))

; --- asking ----------------------------------------------------------------------

; The value of the setting NAME, a symbol.
(def config-get (fn (_ cfg name) (rest (%cf-find name (%cf-get cfg %cf-values)))))

; CFG with the setting NAME made V, unchecked: what the editor's own keys
; changed, so :set lists it.
(def config-put! (fn (_ cfg name v) (%cf-set-value! cfg name v) cfg))

(def config-problems (fn (_ cfg) (%cf-get cfg %cf-problems)))

; The style the editor draws NAME in, a symbol: title, empty, heading,
; beat, off, effect, cursor, playing or block.
(def config-style (fn (_ cfg name) (List ref 4 (%cf-find name (%cf-get cfg %cf-colours)))))

; KEY as the editor takes it: the key of the action it is bound to; nil
; when it is the own key of an action bound to others; else itself.
(def config-key
  (fn (_ cfg key)
    (def keys (%cf-get cfg %cf-keys))
    (if (null? keys) key
      ((fn (_ b)
         (match ((not (null? b)) (rest (%cf-find (first b) %cf-actions)))
                ((List any? (fn (_ b) (equal? key (rest (%cf-find (first b) %cf-actions)))) keys) ())
                (#t key)))
       (List find (fn (_ b) (List includes? key (rest b))) keys)))))

(def %cf-key-name
  (fn (_ k) (match ((symbol? k) (symbol->str k)) ((str=? k " ") "Space") ((str=? k "\"") "\"\\\"\"") (#t (Str8 append "\"" k "\"")))))

; The settings as lines to show: a heading, then each as it would be set.
(def config-lines
  (fn (_ cfg)
    (def file (%cf-get cfg %cf-file))
    (pair (Str8 append "Settings   :set NAME VALUE ... changes one for this session   "
            (if (null? file) "(no config file)" (Str8 append "file " file (if (File exists? file) "" " (none)"))))
      (List append
        (List map (fn (_ e) (Str8 append "  " (symbol->str (first e)) " "
                              (if (eq? (first e) (lit waves)) (Str8 join " " (List map %cf-word (rest e))) (%cf-word (rest e)))))
          (%cf-get cfg %cf-values))
        (List map (fn (_ c) (Str8 append "  colour " (symbol->str (first c)) " " (%cf-word (List ref 1 c)) " "
                              (%cf-word (List ref 2 c)) " " (%cf-word (List ref 3 c))))
          (%cf-get cfg %cf-colours))
        (List map (fn (_ a)
                    (def b (%cf-find (first a) (%cf-get cfg %cf-keys)))
                    (Str8 append "  key " (symbol->str (first a)) " "
                      (Str8 join " " (List map %cf-key-name (if (null? b) (list (rest a)) (rest b))))))
          %cf-actions)))))

; PATH backed up to PATH.bak before it is first written over this
; session, when the backup setting is on and there is a file there.
; Raises what File copy raises.
(def config-backup!
  (fn (_ cfg path)
    (unless (if (not (config-get cfg (lit backup))) #t
              (if (List includes? path (%cf-get cfg %cf-backed)) #t (not (File exists? path))))
      (do (File copy path (Str8 append path ".bak"))
          (%cf-put! cfg %cf-backed (pair path (%cf-get cfg %cf-backed)))))))

(provide tracker/config config-default config-file config-read config-load config-set! config-set-text! config-get
  config-put! config-problems config-style config-key config-lines config-backup!)
