#!/usr/bin/env bash
# Read-only digest builder for the daily in-session wiki ingest.
#
# Lists Claude Code sessions touched SINCE the last ingest watermark, so the
# in-session agent can mine them for new wiki-worthy areas. Watermark-based, not
# a fixed window: if the job did not run for several days (machine off / Claude
# closed), the next run still covers every missed day. Read-only — it never
# writes the wiki; the agent does the ingest, then calls `mark`.
#
#   wiki-ingest-digest.sh          # build + print the digest of sessions since the watermark
#   wiki-ingest-digest.sh mark     # advance the watermark to now (call after a successful ingest)
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"

PROJECTS="$HOME/.claude/projects"
STATEDIR="$HOME/.agents/state/wiki-ingest"
WATERMARK="$STATEDIR/watermark"
OUTDIR="$HOME/.agents/logs/wiki-ingest"
mkdir -p "$STATEDIR" "$OUTDIR"

if [ "${1:-}" = "mark" ]; then
  touch "$WATERMARK"
  echo "[wiki-ingest] watermark advanced to $(date '+%Y-%m-%d %H:%M:%S')"
  exit 0
fi

STAMP="$(date +%Y-%m-%d_%H%M%S)"
DIGEST="$OUTDIR/$STAMP.digest.tsv"

if [ -f "$WATERMARK" ]; then
  FIND=(find "$PROJECTS" -name '*.jsonl' -newer "$WATERMARK")
  SINCE="$(date -r "$WATERMARK" '+%Y-%m-%d %H:%M:%S')"
else
  FIND=(find "$PROJECTS" -name '*.jsonl' -mtime -4)
  SINCE="(no watermark yet; falling back to last 4 days)"
fi

: > "$DIGEST"
while IFS= read -r f; do
  d=$(stat -f '%Sm' -t '%Y-%m-%d' "$f" 2>/dev/null)
  proj=$(basename "$(dirname "$f")")
  h=$(jq -r 'select(.type=="queue-operation" and .operation=="enqueue") | .content' "$f" 2>/dev/null | head -1 || true)
  if [ -z "$h" ]; then
    h=$(jq -r 'select(.type=="user") | (.message.content | if type=="string" then . elif type=="array" then (map(select(.type=="text").text)//[]|join(" ")) else "" end)' "$f" 2>/dev/null | grep -v '^$' | head -1 || true)
  fi
  h=$(printf '%s' "$h" | tr '\n\t' '  ' | cut -c1-200)
  printf '%s\t%s\t%s\t%s\n' "$d" "$proj" "$f" "$h" >> "$DIGEST"
done < <("${FIND[@]}" 2>/dev/null)

echo "[wiki-ingest] sessions since: $SINCE"
echo "[wiki-ingest] rows: $(wc -l < "$DIGEST")"
echo "[wiki-ingest] DIGEST: $DIGEST"
