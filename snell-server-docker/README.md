# 部署指南
>使用前请确保你的docker已经正确运行，如果没有安装可使用这个两个命令安装：
>```shell
>apt update && apt upgrade -y && apt install curl -y
>curl -fsSL 'get.docker.com' | bash
>```
>执行`docker -v`输出版本号就是安装好了。

### 1. 支持的environment：  
  - PORT=自定义使用的端口，仅`host`模式下生效，不写则随机。
  - PSK=节点密码，不写则随机。
  - IPV6=true/false，不写默认为false。
### 2. 使用docker方式：
```shell
docker run -d --name snell-server --network host -e PORT=1111 -e PSK=your_password -e IVP6=false/true vocrx/snell-server:latest
```
### 3. 使用docker compose方式：
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
- Docker使用IPV6需要额外配置，详情GPT
- 想好再写，反正也没人看。