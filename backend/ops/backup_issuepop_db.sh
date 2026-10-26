#!/bin/bash
# Issue Pop DB 일일 백업 (2026-10-26). 크론이 매일 04:10 KST(= 19:10 UTC)에 실행함.
# - 서비스가 쓰는 중에도 안전하게 복사(sqlite3 온라인 백업 API) → 무결성 검사 → gzip → 7일 지난 것 삭제.
# - 결과는 /home/ubuntu/backups/backup.log 에 한 줄씩 남음(실패하면 FAIL 줄).
# 복구: gunzip -c news_trend-YYYYMMDD-HHMM.db.gz > news_trend.db  (서비스를 멈춘 뒤 교체, 8~10분 점검 안내가 나감)
set -uo pipefail

SRC=/home/ubuntu/backend/news_trend.db
DIR=/home/ubuntu/backups/daily
LOG=/home/ubuntu/backups/backup.log
KEEP_DAYS=7
STAMP=$(date +%Y%m%d-%H%M)
TMP="$DIR/.tmp-$STAMP.db"

mkdir -p "$DIR"

fail() {
  echo "$(date -Is) FAIL $1" >> "$LOG"
  rm -f "$TMP" "$TMP.gz"
  exit 1
}

python3 - "$SRC" "$TMP" <<'PY' || fail "백업 복사 또는 무결성 검사 실패"
import sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=120)
dst = sqlite3.connect(sys.argv[2])
src.backup(dst)
dst.close()
src.close()
check = sqlite3.connect(sys.argv[2])
result = check.execute("pragma integrity_check").fetchone()[0]
issues = check.execute("select count(*) from issues").fetchone()[0]
devices = check.execute("select count(*) from devices").fetchone()[0]
check.close()
assert result == "ok", result
assert devices >= 0 and issues >= 0
PY

gzip -9 "$TMP" || fail "압축 실패"
mv "$TMP.gz" "$DIR/news_trend-$STAMP.db.gz" || fail "이동 실패"
find "$DIR" -name 'news_trend-*.db.gz' -mtime +"$KEEP_DAYS" -delete

COUNT=$(ls "$DIR"/news_trend-*.db.gz 2>/dev/null | wc -l)
echo "$(date -Is) ok $(du -h "$DIR/news_trend-$STAMP.db.gz" | cut -f1) (보관 ${COUNT}개)" >> "$LOG"
