#!/bin/sh
# # x-tracker -- a music tracker on x-lang
#
# ## tests/spec-runner.sh -- the bundle's runner
#
# @description Sources the platform's spec runner; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# No path reaches into an x-lang source tree; everything comes from x itself:
# --share-dir says which tree x reads from (repo root in a checkout, share/x
# when installed) and --engine-path says where the engine is.
#
# Set X to point at a particular x; otherwise the one on PATH is used.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

command -v "$X" >/dev/null 2>&1 || {
	echo "x-tracker: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

X_ROOT="$("$X" --share-dir)"
X_BIN="${X_BIN:-$("$X" --engine-path)}"

# The platform runner locates its harness relative to the engine binary, which
# sits beside tests/ only in a checkout; a sourced script cannot portably find
# its own path, so the caller sets this.
SPEC_RUNNER_DIR="$X_ROOT/tests"
export SPEC_RUNNER_DIR

# The harness is GENERATED, never committed: it embeds two absolute paths
# that are facts of this machine, not of the bundle.
sh "$BUNDLE/tests/gen-harness.sh" "$X_ROOT" "$BUNDLE"

LANG_LIB="$BUNDLE/tests/lib/harness.gen.x"

# SPEC_PATH is env-overridable so a single spec file can be run in isolation.
SPEC_PATH="${SPEC_PATH:-$BUNDLE/tests/specs}"

# The suite boots from a state image of the harness when the platform can write
# one, keyed on what it depends on (the harness, the platform's lib/, its
# engine, and tracker/).  IMG=0 runs the same suite from source.
if [ "${IMG:-1}" = 0 ]; then
	SPEC_BATCH="${SPEC_BATCH:-1}"; export SPEC_BATCH
else
	_builder="$X_ROOT/tools/dev/image-build.sh"
	if [ ! -f "$_builder" ]; then
		echo "x-tracker: no image writer at $_builder (not a checkout) -- the suite boots from source" >&2
	elif X_BIN="$X_BIN" sh "$_builder" "$LANG_LIB" "$BUNDLE/tests/lib/.images" "$BUNDLE/tracker"; then
		X_IMG_DIR="$BUNDLE/tests/lib/.images"; export X_IMG_DIR
	else
		echo "x-tracker: no state image -- the suite boots from source" >&2
	fi
fi

# No collect at the snippet seam (x-lang#568/#572), and one spec file per
# process, as the other bundles set them.
export SPEC_SEAM_COLLECT=0
export SPEC_BATCH="${SPEC_BATCH:-1}"

. "$X_ROOT/tests/spec-runner.sh"
