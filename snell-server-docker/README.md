# 部署指南

> 使用前请确保你的 docker 已经正确运行，如果没有安装可使用这个两个命令安装：
>
> ```shell
> apt update && apt upgrade -y && apt install curl -y
> curl -fsSL 'get.docker.com' | bash
> ```
>
> 执行`docker -v`输出版本号就是安装好了。

### 1. 支持的 environment

- PORT=自定义使用的端口，仅`host`模式下生效，不写则随机。
- PSK=节点密码，不写则随机。
- IPV6=true/false，不写默认为 false。
- DNS=8.8.8.8,1.1.1.1，不写为系统默认
- VERSION=v4.1.1，自定义二进制文件版本，不写则默认最新版
- OBFS=http,默认为空,写此条必须配置 HOST
- HOST=icloud.com,默认为空
- NIC=eth0,指定网卡，仅Snell-V5支持

### 2. 使用 docker 方式

```shell
docker run -d --name snell-server --network host -e PORT=1111 -e PSK=your_password -e IVP6=false/true vocrx/snell-server:latest
```

### 3. 使用 docker compose 方式

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
      - IPV6=false/true
```

### 4. 其他

- 使用随机密码或者端口可以使用`docker logs snell-server`查看配置信息。
- Docker 非 HOST 模式下使用 IPV6 需要额外配置，详情 GPT
- 想好再写，反正也没人看。
