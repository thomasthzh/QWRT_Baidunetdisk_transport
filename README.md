# QWRT Alist 百度网盘本地转发面板

在 **京东云 AX1800 Pro（IPQ6018）** 等运行 **QWRT / OpenWrt** 的路由器上，把 [Alist](https://github.com/alist-org/alist) 作为本地百度网盘转发后端，并通过 LuCI 页面统一进行管理。

## 功能

- 风格与 QWRT LuCI 一致的 **Alist 管理页面**。
- **独立直链分享**：在路由器页面选择 `/THZH百度盘/` 下的文件/文件夹，直接生成 Alist 公开分享链接。
- **管理员面板**：
  - Alist 用户列表
  - 在线连接统计（5 秒自动刷新）
  - IP 封禁 / 解封（iptables）
  - 按 IP 限速（tc HTB / ingress police）
- **并发与单连接限速**：在页面设置 `max_connections`、`max_client_download_speed`、`max_client_upload_speed`。

## 环境示例

| 项目 | 示例 |
|------|------|
| 路由器 | 京东云 AX1800 Pro（IPQ6018） |
| 系统 | QWRT R24.5.1 / OpenWrt 19.07-SNAPSHOT，内核 4.4.60 |
| Alist | v3.60.0 `alist-linux-musl-arm64` |
| 安装路径 | `/mnt/usbdata/alist/alist` |
| 数据目录 | `/mnt/usbdata/alist/data` |
| 监听端口 | `0.0.0.0:5244` |

> 其他 aarch64 / arm64 平台通常只需替换 Alist 二进制即可。

## 文件结构

```
files/
├── etc/
│   ├── config/alist             # UCI 配置（账号密码，由 LuCI 读取）
│   ├── init.d/
│   │   ├── alist                # procd 启动脚本，启动后自动应用 tc 限速
│   │   ├── usb_swap             # USB swap 主脚本（带 eMMC fallback）
│   │   ├── usb_swap_run         # USB swap 工作脚本
│   │   └── cgroup_mem_limits    # 启动时给服务加 cgroup 内存硬限
│   ├── sysctl.d/
│   │   └── 99-memory.conf       # 内存调优参数
│   └── config/alist             # UCI 配置
├── mnt/usbdata/alist/
│   └── tc_apply.sh              # 按 IP 限速脚本
├── usr/
│   ├── bin/
│   │   └── cgroup-mem-limit.sh  # cgroup v1 内存限制工具
│   └── lib/lua/luci/
│       ├── alistapi.lua         # Alist API 代理（token 缓存、自动重登、超时）
│       ├── controller/alist.lua # LuCI 控制器（dashboard、share API、IP 管理等）
│       ├── model/cbi/alist.lua  # CBI 模型（四个标签页）
│       └── view/
│           ├── alist_status.htm   # 状态面板
│           ├── alist_shares.htm   # 分享创建/列表（客户端异步加载）
│           ├── alist_bandwidth.htm # 并发/限速设置
│           └── alist_admin.htm    # 管理员面板（合并 dashboard，客户端异步加载）
```

## 快速安装

1. **准备 Alist**
   - 把 `alist-linux-musl-arm64` 放到 `/mnt/usbdata/alist/alist`。
   - 创建数据目录 `/mnt/usbdata/alist/data`，运行一次 `alist admin` 设置初始密码，配置 `config.json`。
   - 确保 `/etc/config/alist` 中的 `username` / `password` 与 Alist 管理员一致：
     ```sh
     uci set alist.main.username='admin'
     uci set alist.main.password='你的密码'
     uci commit alist
     ```

2. **部署本仓库文件**
   ```sh
   cd files
   find . -type f -exec scp {} root@192.168.1.1:{} \;
   ```
   或手动复制到路由器对应路径。

3. **设置权限并启动**
   ```sh
   chmod +x /etc/init.d/alist /mnt/usbdata/alist/tc_apply.sh
   /etc/init.d/alist enable
   /etc/init.d/alist start
   rm -f /tmp/luci-indexcache /tmp/luci-modulecache/*
   ```

4. **访问**
   打开 QWRT 后台 → 网络存储 → Alist。

## tc / ss 说明

QWRT 21.02 软件源里的 `tc` 依赖新版 `libxtables`，与系统 iptables 1.4 不兼容。本方案使用从 OpenWrt 18.06 软件源提取的兼容 `tc` + `ss` 二进制：

```sh
opkg --add-arch aarch64_generic:5 install --nodeps tc_4.16.0-8_aarch64_generic.ipk
opkg --add-arch aarch64_generic:5 install --nodeps ss_4.16.0-8_aarch64_generic.ipk
```

安装后确认：

```sh
which tc ss
ss -Htn
```

## 安全提醒

- 仓库中 **不要** 上传 `data.db`、Alist token、密码、私钥等敏感文件。
- 分享链接默认暴露在局域网 `192.168.1.1:5244/s/xxx`；如需公网访问，请自行配置防火墙/NAT 并做好认证。
- IP 封禁/限速仅对 `br-lan` 方向的客户端生效，按实际需求修改 `tc_apply.sh` 中的 `IFACE`。

## 优化点

- **token 缓存**：`alistapi.lua` 把 token 缓存到 `/tmp/alist_token`，30 分钟内复用，401 时自动重登。
- **超时保护**：所有对 Alist 的 curl 请求增加 `--connect-timeout 3 --max-time 8`，避免后端卡死导致 LuCI 页面无响应。
- **dashboard 合并**：管理员面板原来需要 4 个 AJAX 请求，现在合并为 `/admin/nas/alist_dashboard`，用户/连接/封禁/限速一次返回。
- **客户端异步加载**：分享列表和管理员数据不再阻塞页面生成，由浏览器异步拉取；即使 Alist 后端卡死，LuCI 页面也能快速打开。

## 小内存 + 不稳定 USB 的维稳方案

京东云 AX1800 Pro 只有 **415 MB RAM**，且当前这枚 U 盘重启后可能掉盘，因此采用如下策略：

1. **`/overlay` 留在 eMMC**：U 盘掉盘不会导致路由器变砖。
2. **swap 优先放 U 盘，掉盘时自动回退 eMMC**：
   - `/etc/init.d/usb_swap` 开机检测 `/dev/sda1`。
   - U 盘存在 → 挂载 `/mnt/usbdata` 并使用 `/mnt/usbdata/.swap/swapfile`（优先级 10）。
   - U 盘不存在 → 自动启用 eMMC swap 分区 `/dev/mmcblk0p26` 作为兜底。
3. **cgroup 内存硬限**：给常见大内存服务设置上限，防止单个进程吃光内存导致系统卡死。
   - 已配置：`kaiplus_bin` 256 MB、`cloudflared` 128 MB、`homebox` 128 MB、`netdata` 128 MB、`alist` 192 MB、`dockerd` 192 MB。
   - `/etc/init.d/cgroup_mem_limits` 在启动末期执行，cron 每分钟再刷新一次，以覆盖 procd 自动重启产生的新进程。
4. **sysctl 内存调优**：`vm.swappiness=60`、`vm.oom_kill_allocating_task=1` 等。

> **当前状态**：U 盘未识别，系统正使用 eMMC swap 兜底。请检查 USB 接口是否松动或更换 U 盘后重启，`usb_swap` 会自动切换回 USB swap。

## 许可

MIT License。Alist 及其二进制版权归 [Alist 项目](https://github.com/alist-org/alist) 所有。
