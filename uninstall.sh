#!/usr/bin/env bash
# uninstall.sh — 卸载 pm2 进程；按需保留/清除数据
# 默认保留数据；要清数据加 --purge

set -euo pipefail

ROOT="${ROOT:-/srv/xsg}"
PURGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)  ROOT="$2"; shift 2 ;;
    --purge) PURGE=true; shift ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

echo "==> 停止并删除 pm2 进程 xsg-server"
pm2 delete xsg-server || true
pm2 save || true

if [[ "$PURGE" == "true" ]]; then
  echo "==> --purge：彻底删除 $ROOT（含数据库和备份）"
  read -p "确定要彻底删除 ${ROOT} 吗？（y/N）" yn
  if [[ "${yn:-N}" == "y" || "${yn:-N}" == "Y" ]]; then
    rm -rf "$ROOT"
    echo "已删除 $ROOT"
  else
    echo "取消"
  fi
else
  echo "==> 保留数据目录 ${ROOT}（要彻底删请加 --purge）"
fi

echo "==> 完成"
