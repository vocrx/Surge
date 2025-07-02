# syntax=docker/dockerfile:1
FROM debian:stable-slim

ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}

COPY entrypoint.sh /

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y wget unzip curl tini && \
    chmod +x /entrypoint.sh && \
    mkdir /snell && \
    chmod -R 777 /snell && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /snell

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
