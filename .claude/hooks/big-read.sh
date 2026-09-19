#!/bin/bash
# Cheap gate in front of big-read.mjs.
#
# The hook fires on every Read and every Bash call, and node costs about
# 115 ms to start. Measured over the fifty session transcripts: 11,428 Bash
# calls, of which only 1,330 read a file at all. Bash starts in about 3 ms, so
# letting it answer the other ten thousand saves roughly twenty minutes of
# waiting across a project's history. It matches loosely on purpose — a false
# match only starts node, which then decides properly.
IN=$(cat)
case "$IN" in
  *Read*|*cat*|*head*|*tail*|*less*|*more*|*bat*) ;;
  *) exit 0 ;;
esac
printf '%s' "$IN" | exec node "$(dirname "$0")/big-read.mjs"
