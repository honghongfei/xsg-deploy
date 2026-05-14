#!/usr/bin/env bash
# update.sh — 拉最新代码 + 重编译 + pm2 热重启
# 用法：bash update.sh [--root /srv/xsg]

set -euo pipefail

ROOT="${ROOT:-/srv/xsg}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

say() { echo -e "\033[1;36m==> $*\033[0m"; }

export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

cd "$ROOT"

say "拉最新代码"
BEFORE=$(git rev-parse HEAD)
git pull --ff-only
AFTER=$(git rev-parse HEAD)

if [[ "$BEFORE" == "$AFTER" ]]; then
  say "已是最新，无需重新编译。"
  exit 0
fi

say "diff: $BEFORE → $AFTER"
git --no-pager log --oneline "$BEFORE..$AFTER" | head -n 20

cd "$ROOT/server"
say "重装依赖（若 lockfile 没变这一步很快）"
npm ci

say "重编译"
npm run build

say "跑数据库迁移（如有新表）"
npm run migrate || true

say "pm2 热重启"
pm2 reload xsg-server

sleep 1
PORT="$(grep '^PORT=' "$ROOT/server/.env" | cut -d= -f2 || echo 3000)"
say "健康检查"
curl -fsS "http://127.0.0.1:${PORT}/healthz" || echo "WARN: 健康检查未通过"
echo
say "升级完成。"
