# xsg-deploy

《小傻瓜联机服》一键部署脚本（裸 IP + ws:// 方案）。

适用范围：朋友圈 ≤30 人在线、不要 HTTPS、不需要备案。

## 怎么用

### 0. 准备

- 一台云服务器（阿里云 / 腾讯云 / 华为云均可）
  - 配置：2C4G、Ubuntu 22.04 LTS、5Mbps 带宽
  - 安全组放行：22 (SSH)、3000 (游戏服务)
- 一个 Git 仓库存放游戏服务端代码（`xiaoshagua/server`）

### 1. 一行部署

SSH 进服务器后，复制粘贴这一行：

```bash
curl -fsSL https://raw.githubusercontent.com/<YOUR-USERNAME>/xsg-deploy/main/install.sh | bash -s -- --repo https://github.com/<YOU>/xiaoshagua.git
```

它会：

1. 装好 Node.js 20 + pm2 + 编译工具链
2. 把 `xiaoshagua` 仓库克隆到 `/srv/xsg`
3. 编译 `server/`、生成 `.env`、跑数据库迁移
4. 用 pm2 起进程，开机自启
5. 打印健康检查 URL 让你确认

### 2. 客户端改一处

打开 RMMZ 插件管理器 → `XdRs_Online_Net` → `serverUrl` 改成：

```
ws://<云服公网IP>:3000
```

打包游戏文件夹给朋友即可。

### 3. 日常运维

| 操作 | 命令 |
|---|---|
| 看进程 | `pm2 status` |
| 看日志 | `pm2 logs xsg-server --lines 200` |
| 实时监控 | `pm2 monit` |
| 在线人数 | `curl http://127.0.0.1:3000/stats` |
| 热重启 | `pm2 reload xsg-server` |
| 拉新代码后升级 | `cd /srv/xsg && bash ~/xsg-deploy/update.sh` |
| 备份 SQLite | `bash ~/xsg-deploy/backup.sh` |
| GM 加金币 | `cd /srv/xsg/server && npm run gm grant-gold <角色id> <金额>` |

## 脚本清单

- `install.sh` — 一键安装
- `update.sh` — 拉最新代码 + 重编译 + 热重启
- `backup.sh` — SQLite 在线热备
- `uninstall.sh` — 卸载 pm2 进程和数据
- `cron.txt` — crontab 模板（每日 4 点自动备份）
- `firewall.md` — 各家云服安全组配置示意

## 注意

- **裸 IP + ws:// 方案，账号密码明文传输**。朋友圈玩没事，别用重要密码。
- 公网 IP 变更后需要把 `XdRs_Online_Net.serverUrl` 重新改一遍并重发客户端给朋友。
- 数据库 `/srv/xsg/data/xsg.db`。重装服务但要保留数据 → 先 `bash backup.sh` 拿一份。

## 部署示意

```
[玩家1 NW.js] ─┐
[玩家2 NW.js] ─┼─ ws://1.2.3.4:3000 ──── [云服 pm2 → node dist/main.js]
[玩家3 NW.js] ─┘                              │
                                              └── SQLite WAL @ /srv/xsg/data/xsg.db
```
