#!/bin/sh
# # x-tracker -- a music tracker on x-lang
#
# ## tests/spec-gate.sh -- shim onto the lang kit's gate
#
# @description Sources the platform's spec-gate; vendors nothing.  Runs the
#   suite and compares its failures to tests/contract/known-failures.txt.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# The platform ships the gate; a bundle does not vendor it. The gate lives in
# the platform's tools/bundle-kit/. This file only says where the bundle is and
# which x to ask for the kit.
#
# Set X to point at a particular x; X_BUNDLE_KIT overrides the kit location.
#
# X_COMPILED_REPORT is on: a compiled loop that fails to build (the mixer's,
# a codec's) says so on stderr instead of running its pure-x version in
# silence.  Every host the gate runs on has an assembler backend, so a line
# there is a defect.  Set it to the empty string to quiet it.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"
X_COMPILED_REPORT="${X_COMPILED_REPORT-1}"
if [ -n "$X_COMPILED_REPORT" ]; then export X_COMPILED_REPORT; else unset X_COMPILED_REPORT; fi

KIT="${X_BUNDLE_KIT:-$("$X" --share-dir)/tools/bundle-kit}"
[ -f "$KIT/spec-gate.sh" ] || {
	echo "x-tracker: no bundle kit at $KIT -- set X_BUNDLE_KIT or upgrade x" >&2
	exit 2
}

BUNDLE="$BUNDLE" X="$X" . "$KIT/spec-gate.sh"
