#!/usr/bin/env bash
# Antebet backfill: step 3 (rounds, day by day) and step 4 (report, 7 days at a time).
#
# Usage:
#   export CH_HOST=hyxzs78gz1.europe-west4.gcp.clickhouse.cloud CH_USER=... CH_PASSWORD=...
#   ./run_backfill.sh '2026-10-05 22:00:00' [2026-08-20]
#     $1 = CUTOFF (UTC), the same as in 02_incremental_mvs.sql
#     $2 = first day of history (default 2026-08-20)
#
# Requires: clickhouse client (curl https://clickhouse.com/ | sh), GNU date.
# Step 3 runs in chunks = Warsaw days and is NOT idempotent (a repeat doubles the sums).
# If chunk D fails: DELETE FROM adam_sandbox.bi_antebet_rounds WHERE action_date = 'D'
# and start again from that day: ./run_backfill.sh '<CUTOFF>' D
# (CUTOFF = a Warsaw midnight, so no day is shared by the backfill and the MV).
set -euo pipefail

CUTOFF="${1:?CUTOFF (UTC), e.g. '2026-10-05 22:00:00'}"
START="${2:-2026-08-20}"
DIR="$(cd "$(dirname "$0")" && pwd)"

ch() {
  clickhouse client --host "$CH_HOST" --secure --port 9440 \
    --user "$CH_USER" --password "$CH_PASSWORD" "$@"
}

now_s=$(date -u +%s)
cut_s=$(date -u -d "$CUTOFF" +%s)
if (( now_s < cut_s + 900 )); then
  echo "Too early: wait until $CUTOFF UTC + 15 min (MVs must already be writing, PeerDB lag)." >&2
  exit 1
fi

# Warsaw midnight of day $1 as a UTC timestamp
waw_midnight_utc() { date -u -d "TZ=\"Europe/Warsaw\" $1 00:00:00" '+%F %T'; }

echo "== Step 3: rounds from $START (Warsaw) to $CUTOFF (UTC) =="
d="$START"
while [[ "$(date -u -d "$(waw_midnight_utc "$d")" +%s)" -lt "$cut_s" ]]; do
  next="$(date -u -d "$d + 1 day" +%F)"
  ts_from="$(waw_midnight_utc "$d")"
  ts_to="$(waw_midnight_utc "$next")"
  if (( $(date -u -d "$ts_to" +%s) > cut_s )); then ts_to="$CUTOFF"; fi
  echo "  [$d Warsaw] $ts_from -> $ts_to UTC"
  ch --param_ts_from="$ts_from" --param_ts_to="$ts_to" --param_cutoff="$CUTOFF" \
     --queries-file "$DIR/03_backfill_rounds.sql"
  d="$next"
done

echo "== Step 4: report for closed days =="
last="$(TZ=Europe/Warsaw date -d '2 days ago' +%F)"   # today-2 by the Warsaw clock
d="$START"
while [[ "$d" < "$last" || "$d" == "$last" ]]; do
  to="$(date -u -d "$d + 6 days" +%F)"
  [[ "$to" > "$last" ]] && to="$last"
  echo "  $d -> $to"
  ch --param_date_from="$d" --param_date_to="$to" \
     --queries-file "$DIR/04_backfill_report.sql"
  d="$(date -u -d "$to + 1 day" +%F)"
done

echo "Done. Next: 05_refreshable_mvs_and_view.sql"
