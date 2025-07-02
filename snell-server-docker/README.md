# Snell Server Docker

快速部署 Snell Server 的 Docker 镜像，支持多架构。

## 环境准备

确保系统已安装 Docker。如果未安装，可以使用以下命令进行安装：

```shell
apt update && apt upgrade -y && apt install curl -y
curl -fsSL 'get.docker.com' | bash
```

执行 `docker -v` 确认安装成功。

## 支持的环境变量

| 环境变量 | 说明 | 默认值 | 示例 |
|---------|------|--------|------|
| PORT    | 服务端口号 | 随机 (1024-65535) | `PORT=1111` |
| PSK     | 节点密码 | 随机生成 | `PSK=password123` |
| IPV6    | 是否启用 IPv6 | false | `IPV6=true` |
| DNS     | 自定义 DNS | 系统默认 | `DNS=8.8.8.8,1.1.1.1` |
| VERSION | Snell 版本号 | v5.0.0b1 | `VERSION=v4.1.1` |
| OBFS    | 混淆方式 | 无 | `OBFS=http` |
| HOST    | 混淆域名 | 无 | `HOST=www.apple.com` |
| NIC     | 指定网卡 (仅 V5) | 无 | `NIC=eth0` |

> 注意：启用 OBFS 时必须同时配置 HOST

## 部署方式

### Docker 命令行

```shell
docker run -d \
  --name snell-server \
  --network host \
  --restart always \
  -e PORT=1111 \
  -e PSK=your_password \
  -e IPV6=false \
  vocrx/snell-server:latest
```

### Docker Compose

```yaml
services:
  snell-server:
    image: vocrx/snell-server:latest
    container_name: snell-server
    restart: always
    network_mode: host
    environment:
      - PORT=1111
      - PSK=your_password
      - IPV6=false
```

## 使用说明

1. 使用随机配置时，可通过以下命令查看实际配置：
   ```shell
   docker logs snell-server
   ```

2. 非 HOST 网络模式下使用 IPv6 需要额外配置 Docker daemon 设置

3. 支持的架构：
   - linux/amd64
   - linux/arm64
   - linux/386
   - linux/arm/v7

## 注意事项

- 推荐使用 HOST 网络模式以获得最佳性能
- 容器首次启动时会下载对应版本的二进制文件
- 如遇端口冲突，请修改 PORT 环境变量
