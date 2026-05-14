#!/usr/bin/env bash
# install.sh — XSG-Online 一键部署脚本（裸 IP + ws:// 方案）
# 用法：
#   bash install.sh --repo https://github.com/<you>/xiaoshagua.git [--branch main] [--port 3000] [--root /srv/xsg]
#
# 测试环境：Ubuntu 22.04 LTS（其他 Debian 系略改 apt 包名）

set -euo pipefail

# ---------- 默认参数 ----------
REPO=""
BRANCH="main"
PORT="3000"
ROOT="/srv/xsg"
NODE_VERSION="20"

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --port)   PORT="$2"; shift 2 ;;
    --root)   ROOT="$2"; shift 2 ;;
    --node)   NODE_VERSION="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
用法：bash install.sh --repo <git-url> [--branch <main>] [--port <3000>] [--root </srv/xsg>] [--node <20>]
必填：
  --repo    存放 xiaoshagua/server 的 git 仓库地址
可选：
  --branch  默认 main
  --port    默认 3000
  --root    默认 /srv/xsg
  --node    默认 20
EOF
      exit 0
      ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "错误：必须传 --repo，例如 --repo https://github.com/you/xiaoshagua.git"
  exit 1
fi

# ---------- 工具 ----------
say() { echo -e "\033[1;36m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m[warn] $*\033[0m"; }
err()  { echo -e "\033[1;31m[err]  $*\033[0m"; }

if [[ "$EUID" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

# ---------- 0. 系统检测 ----------
say "0/7 检测系统"
if ! command -v apt >/dev/null 2>&1; then
  err "脚本只支持 Debian / Ubuntu 系（apt）"
  exit 1
fi
echo "    OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo unknown)"
echo "    Repo: $REPO"
echo "    Branch: $BRANCH"
echo "    Port: $PORT"
echo "    Root: $ROOT"

# ---------- 1. 系统依赖 ----------
say "1/7 安装系统依赖"
$SUDO apt update -y
$SUDO apt install -y git curl build-essential python3 sqlite3 ca-certificates

# ---------- 2. 安装 Node.js ----------
say "2/7 安装 Node.js $NODE_VERSION（nvm 方式）"
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
  curl -fsSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
fi
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install "$NODE_VERSION"
nvm alias default "$NODE_VERSION"
NODE_BIN="$(which node)"
NPM_BIN="$(which npm)"
echo "    node: $NODE_BIN ($(node -v))"
echo "    npm:  $NPM_BIN ($(npm -v))"

# ---------- 3. pm2 ----------
say "3/7 安装 pm2"
npm i -g pm2 >/dev/null
echo "    pm2: $(which pm2) ($(pm2 -v))"

# ---------- 4. 克隆仓库 ----------
say "4/7 克隆仓库到 $ROOT"
$SUDO mkdir -p "$ROOT"
$SUDO chown -R "$USER:$USER" "$ROOT"
if [[ -d "$ROOT/.git" ]]; then
  warn "$ROOT 已经是一个仓库，跳过 clone，改为 fetch + reset"
  cd "$ROOT"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  git clone --branch "$BRANCH" "$REPO" "$ROOT"
fi

if [[ ! -d "$ROOT/server" ]]; then
  err "$ROOT/server 不存在，仓库结构不对（期望仓库根有 server/ 子目录）"
  exit 1
fi

# ---------- 5. 编译 ----------
say "5/7 编译服务端"
cd "$ROOT/server"

if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
  else
    touch .env
  fi
  cat > .env <<EOF
NODE_ENV=production
PORT=${PORT}
HOST=0.0.0.0
DB_PATH=${ROOT}/data/xsg.db
LOG_LEVEL=info
MAX_MESSAGES_PER_SEC=20
MAX_PLAYERS_PER_MAP=50
WORLD_TICK_MS=200
TOKEN_TTL_SEC=86400
EOF
  echo "    生成 .env"
else
  warn ".env 已存在，未覆盖"
fi

mkdir -p "$ROOT/data" "$ROOT/backup" "$ROOT/server/logs"

npm ci
npm run build
say "    跑数据库迁移"
npm run migrate || warn "migrate 失败（如果是 idempotent 表已存在可忽略）"

# ---------- 6. pm2 起进程 ----------
say "6/7 用 pm2 启动 xsg-server"
pm2 delete xsg-server >/dev/null 2>&1 || true
pm2 start pm2.config.js --env production
pm2 save

PM2_STARTUP_CMD=$(pm2 startup systemd -u "$USER" --hp "$HOME" | tail -n 1 || true)
if [[ -n "$PM2_STARTUP_CMD" && "$PM2_STARTUP_CMD" == sudo* ]]; then
  warn "下面这一行需要 root 跑一次以启用开机自启："
  echo "  $PM2_STARTUP_CMD"
fi

# ---------- 7. 健康检查 ----------
say "7/7 健康检查"
sleep 2
PUB_IP="$(curl -fsS https://api.ipify.org 2>/dev/null || echo "<your-public-ip>")"
HEALTH_LOCAL="$(curl -fsS "http://127.0.0.1:${PORT}/healthz" 2>/dev/null || echo 'FAIL')"
echo "    本机 healthz: $HEALTH_LOCAL"
echo "    公网 IP：$PUB_IP"
echo ""
echo -e "\033[1;32m========================================\033[0m"
echo -e "\033[1;32m部署完成。\033[0m"
echo -e "\033[1;32m========================================\033[0m"
cat <<EOF

接下来需要：

  1) 把云服安全组的 ${PORT} 端口开放给 0.0.0.0/0
     （否则朋友连不进来）

  2) 客户端 RMMZ 插件管理器：
     XdRs_Online_Net.serverUrl  →  ws://${PUB_IP}:${PORT}

  3) 备份脚本：
     bash ~/xsg-deploy/backup.sh             # 手动备份一次
     crontab -e 然后粘贴 cron.txt 内容       # 每日自动备份

  4) 常用命令：
     pm2 status                              # 看进程
     pm2 logs xsg-server                     # 看日志
     pm2 monit                               # 实时监控
     curl http://127.0.0.1:${PORT}/stats     # 看在线、地图、内存

EOF
