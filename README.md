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
| 安装路径 | `/usr/bin/alist` |
| 数据目录 | `/overlay/alist/data` |
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
│   │   ├── 99-memory.conf           # 内存与网络调优参数
│   │   └── 99-disable-ipv6.conf     # 关闭 IPv6 节省内存
│   ├── netdata/
│   │   └── netdata.conf             # 精简版 netdata 配置（降低内存）
│   └── config/alist                 # UCI 配置
├── overlay/alist/
│   └── tc_apply.sh                  # 按 IP 限速脚本
├── usr/
│   ├── bin/
│   │   ├── cgroup-mem-limit.sh           # cgroup v1 内存限制工具
│   │   ├── router-optimize.sh            # 一键深度优化内存脚本
│   │   ├── router-optimize-revert.sh     # 恢复脚本
│   │   ├── router-purge.sh               # 关闭 IPv6 + 卸载视频/IPTV/无用包
│   │   ├── enable-ipv6.sh                # 重新启用 IPv6
│   │   └── migrate-alist-to-overlay.sh   # Alist 从 USB 迁移到 eMMC overlay
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
   - 把 `alist-linux-musl-arm64` 放到 `/usr/bin/alist`。
   - 创建数据目录 `/overlay/alist/data`，运行一次 `alist admin` 设置初始密码，配置 `config.json`。
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
   chmod +x /etc/init.d/alist /overlay/alist/tc_apply.sh
   /etc/init.d/alist enable
   /etc/init.d/alist start
   rm -f /tmp/luci-indexcache /tmp/luci-modulecache/*
   ```

4. **访问**
   打开 QWRT 后台 → 网络存储 → Alist。

### 从 USB 迁移到 eMMC overlay

如果 Alist 原本装在 USB 上（`/mnt/usbdata/alist`），而 U 盘不稳定，可以一键迁到 eMMC：

```sh
chmod +x /usr/bin/migrate-alist-to-overlay.sh
/usr/bin/migrate-alist-to-overlay.sh
```

迁移后：
- 二进制位于 `/overlay/alist/alist`
- 数据位于 `/overlay/alist/data`
- `/usr/bin/alist` 会软链接到 `/overlay/alist/alist`
- 启动脚本、LuCI 控制器、限速脚本都会自动使用 `/overlay/alist`

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
   - 已配置：`kaiplus_bin` 256 MB、`cloudflared` 128 MB、`homebox` 128 MB、`netdata` 96 MB、`alist` 192 MB、`dockerd` 192 MB。
   - 代理/下载类（当前多数未启动，但已预限）：`clash/openclash` 128 MB、`qbittorrent` 256 MB、`zerotier` 96 MB、`frpc/openvpn/ssr` 64 MB。
   - `/etc/init.d/cgroup_mem_limits` 在启动末期执行，cron 每分钟再刷新一次，以覆盖 procd 自动重启产生的新进程。
4. **sysctl 内存调优**：`vm.swappiness=60`、`vm.oom_kill_allocating_task=1`、连接跟踪上限降低、TCP 内存收紧等。
5. **关闭 IPv6**：对于不需要 IPv6 的环境，关闭 `odhcpd`、IPv6 RA/DHCPv6，可显著降低内核内存占用。
6. **卸载视频/IPTV/无用 LuCI 应用**：Hermes、msd_lite、xupnpd、Samba、KMS、IPSec/OpenVPN 服务器、TTYD、FTP、USB 打印机等。
7. **zram/zswap 不可用**：当前内核未编译相关模块，无法启用压缩内存/交换。

> **当前状态**：U 盘未识别，系统正使用 eMMC swap 兜底。请检查 USB 接口是否松动或更换 U 盘后重启，`usb_swap` 会自动切换回 USB swap。

> 执行 `router-purge.sh` 后实际可用内存从约 170 MB 提升到约 **200 MB**。

## 内存升级可行性（预算不够时的参考）

京东云 AX1800 Pro 原装内存是 **NT52CB256M16DP-EK**（512 MB BGA96 DDR3L）。要真正解决“跑很多服务”，最治本的是 **硬改 1 GB 内存**：

- **可替换颗粒**：`NT52CB512M16DP`、`MT41K512M16HA-107`（D9STQ）、`H5TC8G63MFR` 等 BGA96 DDR3L 1 GB。
- **位置**：CPU 旁边那颗正方形 BGA 内存芯片。
- **工具**：热风枪（建议 850 热风台）、BGA 植球钢网、焊膏、显微镜/放大镜。
- **风险**：
  - BGA 引脚多、间距小，植球和焊接对新手不友好，容易虚焊/连锡。
  - 换颗粒后需要 **固件/DTB 支持 1 GB**，否则系统只认 512 MB 甚至不开机。
  - 没有备用机的话，焊坏了就砖。

**结论**：你有焊锡和热风枪基础，理论上能做，但 **BGA 内存是第一道坎，固件适配是第二道坎**。建议：
- 先找一台同型号坏机或便宜的二手同款练手；
- 或者先在当前机器上把服务优化/拆分做到极致，等预算够了再换 N100 小主机。

## 一键深度优化

如果还想进一步压榨内存，可以运行：

```sh
chmod +x /usr/bin/router-optimize.sh
/usr/bin/router-optimize.sh
```

该脚本会自动：

- 关闭明显用不到的服务（FTP、UPnP、Web 终端、Samba、KMS、链路聚合等）。
- 精简 netdata 配置（缩短历史、关闭 tc 插件）。
- 收紧 dnsmasq 缓存和系统日志。
- 应用更多 sysctl 调优（连接跟踪、TCP/UDP 内存、ARP 缓存）。
- 扩展 cgroup 内存限制到代理/下载类服务。
- 自动备份原配置到 `/root/router_opt_backup_时间戳`。

如果优化后某些功能异常，可用恢复脚本还原：

```sh
/usr/bin/router-optimize-revert.sh /root/router_opt_backup_xxx
```

### 更激进的清理：`router-purge.sh`

如果你确定 **不需要 IPv6、Hermes、IPTV/视频流、Samba、IPSec/OpenVPN 服务器、TTYD 等**，可以运行：

```sh
chmod +x /usr/bin/router-purge.sh
/usr/bin/router-purge.sh
```

该脚本会：

- 关闭 IPv6 并禁用 `odhcpd`。
- 卸载 Hermes、msd_lite、xupnpd、Samba、KMS、TTYD、FTP、USB 打印、IPSec 服务器、OpenVPN 服务器等。
- 自动清理残留依赖。

> ⚠️ 此操作会删除软件包，恢复时需要重新 `opkg install`。如果后悔了可以运行 `/usr/bin/enable-ipv6.sh` 恢复 IPv6，但已卸载的包需要手动装回。

## 许可

MIT License。Alist 及其二进制版权归 [Alist 项目](https://github.com/alist-org/alist) 所有。
