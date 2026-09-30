# Shadowsocks Rust 安装脚本

[`ss-rust.sh`](ss-rust.sh) 用于在 Linux 上安装、更新和卸载 Shadowsocks Rust。每次安装、重装或更新时自动获取 GitHub 的 **latest 正式版**，无需手动维护版本号。安装完成后输出一行 Surge 节点配置。

## 环境要求

- 使用 **Bash** 执行，安装、更新和卸载需要 root 权限。
- 架构：`x86_64` 或 `aarch64`。
- 服务管理：正在运行的 systemd 或 OpenRC。
- 缺少依赖时，支持通过 `apt-get`、`dnf`、`yum` 或 `apk` 安装。
- 使用 `curl` 查询 GitHub API、`jq` 解析版本及下载地址；缺少时自动安装。
- Alpine 使用 musl 发行包，其他系统使用 GNU 发行包。下载后会执行新版的 `--version`，提前发现二进制与运行环境不兼容的问题。

Alpine 如果尚未安装 Bash，请先以 root 执行 `apk add bash`。其他系统也需要预先具备 Bash，不能使用 `sh ss-rust.sh` 替代。

## 安装

以下命令均在仓库根目录执行，以 root 运行；普通用户可在命令前添加 `sudo`。

重复执行安装命令会覆盖原程序和服务定义，并重新生成配置。未指定端口或密钥时会重新随机生成；如需沿用原来的值，请通过 `-p` 和 `-psk` 显式传入。只升级程序、保留配置时使用 `update`。

```bash
# 随机选择空闲端口，并自动生成密钥
bash Scripts/ss-rust.sh

# 指定端口，自动生成密钥
bash Scripts/ss-rust.sh install -p 8388

# 指定端口和密钥；将占位符换成真实密钥
bash Scripts/ss-rust.sh install -p 8388 -psk '<Base64 密钥>'

# 查看帮助，无需 root
bash Scripts/ss-rust.sh --help
```

| 参数 | 说明 |
| --- | --- |
| `install` | 安装，可省略；已有安装时直接重装，并按本次参数重新生成配置 |
| `-p` | TCP/UDP 监听端口，范围为 1–65535；省略时从 1000–65535 中随机选取空闲端口 |
| `-psk` | 16 字节随机密钥的标准 Base64 编码，包含末尾 `==` |
| `-passwd` | `-psk` 的兼容别名，仍须传入有效密钥 |
| `update` | 下载并更新到 GitHub latest 正式版，保留配置，不接受安装参数 |
| `uninstall` | 删除程序、配置和对应服务定义，不接受安装参数 |

固定使用 `2022-blake3-aes-128-gcm`，同时启用 TCP 和 UDP。密钥不能是普通密码，可用以下命令生成：

```bash
openssl rand -base64 16
```

脚本在修改安装前检查参数，包括端口范围、密钥格式、缺少参数值及重复参数。密钥要求见 [Shadowsocks 2022 官方规范](https://shadowsocks.org/doc/sip022.html)。

## 更新与失败恢复

```bash
bash Scripts/ss-rust.sh update
```

每次执行 `update` 都会查询 GitHub latest 正式版，排除草稿和预发布版本；不提供指定版本的参数，也不会在查询失败时改用某个固定版本。端口、密钥、配置内容和已有服务定义均保留，配置文件权限会收紧为 `600`。脚本不会在后台定时更新，需主动执行命令；即使已经安装相同版本，也会重新下载并替换程序。

版本信息通过 [GitHub latest release API](https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest) 获取。查询失败、返回异常、缺少当前平台的压缩包或校验文件时直接退出，保留旧安装。

安装和更新共用以下下载流程：

1. 在 `/opt` 下创建权限受限的临时目录，查询 latest，根据架构及 GNU/musl 匹配发行包和官方 `.sha256` 文件。本次下载固定使用同一次查询返回的版本及附件地址，避免 latest 在下载期间变化造成版本不一致。
2. 校验 SHA-256，仅解压 `ssserver`，检查可执行性及版本。
3. 验证通过后才安装或替换程序；更新前备份旧程序，并通过同一文件系统中的重命名替换二进制。重装会先备份整个旧安装目录、服务定义和服务状态，再停止旧服务、检查端口并替换安装。
4. 重启服务，连续检查三次运行状态。检查通过才报告成功。

更新在替换或启动阶段失败时，自动恢复旧程序；原服务运行时尝试重新启动，原服务停止时恢复停止状态。即使回退成功，本次更新也会返回非零退出码。若恢复文件失败，会保留备份目录并输出路径；若旧程序恢复后仍无法启动，会输出错误及日志。

重装下载或校验失败时，旧安装继续保留；停止旧服务后的重装失败会尝试恢复旧安装目录（包括原配置及额外文件）、服务定义、原来的运行状态和开机启动设置。恢复不完整时保留备份目录并输出路径。成功重装会替换原安装目录中的文件，临时备份随清理删除。

重装可通过 `-p` 指定原服务使用的端口：脚本会先准备好新版程序，再停止旧服务检查端口是否释放；若仍被其他进程占用，则中止重装并恢复旧安装。OpenRC 的开机启动恢复针对本脚本管理的 `default` runlevel。

首次安装失败会尝试删除本次创建的服务和安装目录。如果停止服务或清理失败，会保留相关文件并提示手动检查。自动安装的系统依赖不会随失败回退。

正常退出及可捕获的 HUP/INT/TERM 信号会触发清理；断电或 `kill -9` 无法保证自动恢复。安装锁位于 `/run/ss-rust-installer.lock`，防止多个脚本实例同时修改安装；异常中断遗留锁时，先确认没有其他安装进程，再手动删除该空目录。

服务状态检查用于发现启动阶段的错误，不代表已经通过客户端连接或公网连通性测试。

## 文件、权限与服务管理

| 路径 | 用途 |
| --- | --- |
| `/opt/ss-rust/ssserver` | 服务端程序 |
| `/opt/ss-rust/config.json` | 配置和密钥，权限为 `600` |
| `/etc/systemd/system/ss-rust.service` | systemd 服务定义 |
| `/etc/init.d/ss-rust` | OpenRC 服务定义 |
| `/var/log/ss-rust.log` | OpenRC 标准输出日志 |
| `/var/log/ss-rust-error.log` | OpenRC 错误日志 |

延续原脚本，以 root 运行服务，支持低于 1024 的端口；本次没有引入专用服务账户。若自行修改服务运行用户，需要同步调整配置所有权，确保该用户能读取权限为 `600` 的配置。

systemd：

```bash
systemctl status ss-rust
systemctl restart ss-rust
journalctl -u ss-rust -n 50 --no-pager
```

OpenRC：

```bash
rc-service ss-rust status
rc-service ss-rust restart
tail -n 50 /var/log/ss-rust-error.log
```

脚本不修改系统防火墙或云安全组；需要自行放行所选端口的 TCP/UDP。监听地址保留原来的 `::`，需保证目标系统支持相应的 IPv6 监听。

## Surge 输出

安装成功后输出如下格式：

```text
主机名 = ss, 公网IP, 端口, encrypt-method=2022-blake3-aes-128-gcm, password=密钥, udp-relay=true
```

公网 IP 获取保留原有的 `curl -s http://ipv4.icanhazip.com`，仅用于方便输出。它没有增加超时、重试或多 IP/代理判断；获取失败不回滚已经成功的安装。多 IP、代理或其他复杂网络环境下，请自行修改节点地址。更新不重新输出节点信息。

## 卸载与重装

```bash
bash Scripts/ss-rust.sh uninstall
```

卸载先停止服务、移除开机启动和服务定义，再删除 `/opt/ss-rust`，其中包含密钥和配置。系统依赖及 OpenRC 日志保留。

重装无需先卸载，直接重复执行安装命令即可：

```bash
# 重装并重新随机生成端口和密钥
bash Scripts/ss-rust.sh

# 重装，使用指定端口并重新生成密钥
bash Scripts/ss-rust.sh -p 8388
```

成功后使用新输出的 Surge 节点配置；如需长期保留旧配置，请在重装前另行备份。
