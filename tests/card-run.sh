#!/bin/sh
# tests/card-run.sh FILE -- run one program of docs/card.md, for the bundle
# kit's card check.  X is the x under test.  A program is a song file, and
# running it is `list`: each song's name, how long it lasts, its patterns
# and its order, or why it does not play.
"${X:-x}" -l tracker -- list "$1" < /dev/null
