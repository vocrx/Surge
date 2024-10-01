# syntax=docker/dockerfile:1
FROM debian:stable-slim

ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}

COPY entrypoint.sh /snell/

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y wget unzip curl tini && \
    chmod +x /snell/entrypoint.sh && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /snell

ENTRYPOINT ["/usr/bin/tini", "--", "/snell/entrypoint.sh"]
