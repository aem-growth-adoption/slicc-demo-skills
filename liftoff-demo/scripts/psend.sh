#!/usr/bin/env bash
# psend.sh — one-call pipeline transition for the SLICC realm.
#
# In SLICC, node runs in a realm where child_process cannot spawn `sprinkle`,
# so pipeline.js can only update the persisted state, rewrite the .shtml, and
# record the send payload to .last-send.json. This wrapper runs pipeline.js to
# do exactly that, then issues the `sprinkle send` itself from the recorded
# payload — keeping "state + .shtml + live push" atomic in a single command.
#
# Usage: bash psend.sh <slug> <step> <status> [summary] [link]
set -euo pipefail

slug="${1:?usage: psend.sh <slug> <step> <status> [summary] [link]}"
here="$(cd "$(dirname "$0")" && pwd)"
root="${PIPELINE_SPRINKLE_DIR:-/shared/sprinkles}"
payload="$root/${slug}-pipeline/.last-send.json"

PIPELINE_DRY_RUN=1 node "$here/pipeline.js" send "$@" >/dev/null
if [ ! -f "$payload" ]; then
	echo "psend.sh: pipeline.js did not write $payload" >&2
	exit 1
fi
sprinkle send "${slug}-pipeline" "$(cat "$payload")"
