#!/usr/bin/env bash
# backup.sh — SQLite 在线热备
# 默认每次备份保留 14 天，自动清理过期

set -euo pipefail

ROOT="${ROOT:-/srv/xsg}"
DB="${ROOT}/data/xsg.db"
DST="${ROOT}/backup"
KEEP_DAYS=14

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; DB="${ROOT}/data/xsg.db"; DST="${ROOT}/backup"; shift 2 ;;
    --db)   DB="$2"; shift 2 ;;
    --dst)  DST="$2"; shift 2 ;;
    --keep) KEEP_DAYS="$2"; shift 2 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

mkdir -p "$DST"

if [[ ! -f "$DB" ]]; then
  echo "数据库不存在：$DB"
  exit 1
fi

STAMP=$(date +%F_%H%M)
OUT="${DST}/xsg-${STAMP}.db"

echo "==> 在线热备份 $DB → $OUT"
sqlite3 "$DB" ".backup '${OUT}'"

SIZE=$(du -h "$OUT" | cut -f1)
echo "    完成，大小 ${SIZE}"

echo "==> 清理 ${KEEP_DAYS} 天前的旧备份"
find "$DST" -maxdepth 1 -type f -name 'xsg-*.db' -mtime "+${KEEP_DAYS}" -print -delete || true

echo "==> 当前备份列表："
ls -lhrt "$DST" | tail -n 10
