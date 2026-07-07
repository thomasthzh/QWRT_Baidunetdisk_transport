# 百度-Alist本地转发 备份说明

本目录备份了京东云 AX1800 Pro 路由器上 Alist 相关的 LuCI 页面、API 代理、启动脚本及配置文件。

## 文件清单

| 本地路径 | 路由器目标路径 | 说明 |
|----------|----------------|------|
| `usr/lib/lua/luci/controller/alist.lua` | `/usr/lib/lua/luci/controller/alist.lua` | LuCI 控制器，定义页面路由和 API 接口 |
| `usr/lib/lua/luci/model/cbi/alist.lua` | `/usr/lib/lua/luci/model/cbi/alist.lua` | CBI 模型，让页面融入 QWRT 主题 |
| `usr/lib/lua/luci/view/alist_*.htm` | `/usr/lib/lua/luci/view/` | 四个页面模板：状态、分享、限速、管理员面板 |
| `usr/lib/lua/luci/alistapi.lua` | `/usr/lib/lua/luci/alistapi.lua` | Alist API 代理模块（登录、token 缓存、请求转发） |
| `etc/init.d/alist` | `/etc/init.d/alist` | Alist 启动脚本，启动时自动应用 tc 限速 |
| `etc/config/alist` | `/etc/config/alist` | LuCI 占位配置，保存 admin 用户名/密码供 API 代理使用 |
| `mnt/usbdata/alist/tc_apply.sh` | `/mnt/usbdata/alist/tc_apply.sh` | tc 限速规则应用脚本 |

## 未包含的敏感文件

- `/mnt/usbdata/alist/data/data.db`：包含百度网盘/123盘/夸克 TV 的 token、密码等凭据，未自动备份到此目录。如需备份请手动复制并妥善保管。

## 更新记录

- 2026-07-07：重构为 CBI 页面，集成分享创建、用户/连接/IP 封禁、按 IP tc 限速。
