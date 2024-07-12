# 如何使用
1. ### 使用随机密码和随机端口一键部署。
> 1. 这个方式部署会使用随机端口+随机密码，IPV6默认为false  
> 2. 重启容器后端口和密码会重新生成！！！
- 使用docker直接运行

    `docker run -d --network host --name snell-server vocrx/snell-server:latest`

    部署完成后用这个命令查看节点:

    `docker logs snell-server`

- 使用docker compose运行

    创建一个你用来放docker compose文件的目录，进入到目录创建`docker-compose.yaml`文件,文件内容如下：
    
    ```yaml
    services:
      snell-server:
        image: vocrx/snell-server:latest
        container_name: snell-server
        restart: always
        network_mode: host
    ```
    创建好之后在文件所在目录下运行命令：

    `docker compose up -d`

    然后使用这个命令查看节点：

    `docker compose logs`
2. ### 固定密码或者端口
> 适用于下面两种情况:  
> 1. 想固定某个端口或者密码。
> 2. 不想使用host模式。  
- 使用docker直接运行

    `docker run -d --name snell-server -p 8888:6666 -e PORT=6666 -e PSK=your_password -e IPV6=false vocrx/snell-server:latest`
    > 1.更改`your_password`为你想设置的密码。  
    > 2.此时应该使用8888端口，你可以更改`-p 8888:6666`左边的`8888`为你想要的端口，右边的`6666`需要与后面的`-e PORT=6666`的端口相同。  
    > 3.将`-p 8888:6666`替换为`--network host`，则端口与后面的`-e PORT=6666`一致。  
    > 4.如果想固定端口，密码随机，删除`-e PSK=your_password`即可。  
    > 5.如果想固定密码，端口随机，参考第三点，并删除`-e PORT=6666`即可。  
    > 6.开启IPV6需要你的VPS有V6地址并且docker需要额外配置，如果不开启V6可直接删除`-e IPV6=false`。

- 使用docker compose运行

    创建一个你用来放docker compose文件的目录，进入到目录创建`docker-compose.yaml`文件,文件内容如下：
    
    ```yaml
    services:
      snell-server:
        image: vocrx/snell-server:latest
        container_name: snell-server
        restart: always
        ports:
          - "8888:6666"
        environment:
          - PORT=6666
          - PSK=your_password
          - IPV6=false
    ```

    > 1.如果需要随机密码删除`environment`中的`- PSK=your_password`即可。  
    > 2.如果需要随机端口，将
    >```yaml
    >ports:
    >  - "8888:6666"
    >```
    >改为`network_mode: host`并删掉`environment`中的`- PORT=6666`即可。  
    > 3.开启IPV6需要你的VPS有V6地址并且docker需要额外配置，如果不开启V6可直接删除`- IPV6=false`。
