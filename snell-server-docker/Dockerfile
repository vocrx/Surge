# syntax=docker/dockerfile:1

FROM debian:stable-slim AS base

ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}

# 创建 snell 目录
RUN mkdir -p /snell

# 复制 entrypoint 脚本
COPY entrypoint.sh /snell/

# 设置权限
RUN chmod +x /snell/entrypoint.sh

# 更新
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y wget unzip curl  && \
    rm -rf /var/lib/apt/lists/*

# 下载并解压对应平台的 snell-server
RUN case "${TARGETPLATFORM}" in \
        "linux/amd64")  SNELL_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip" ;; \
        "linux/386")    SNELL_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-i386.zip" ;; \
        "linux/arm64")  SNELL_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-aarch64.zip" ;; \
        "linux/arm/v7") SNELL_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-armv7l.zip" ;; \
        *) echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    wget -O snell.zip ${SNELL_URL} && \
    unzip snell.zip -d /snell && \
    rm snell.zip && \
    chmod +x /snell/snell-server

# 设置工作目录
WORKDIR /snell

# 设置 ENTRYPOINT
ENTRYPOINT ["/snell/entrypoint.sh"]
