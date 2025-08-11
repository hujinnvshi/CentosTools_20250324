#!/bin/bash
# 一键安装 simple-obfs (适用于 CentOS 7/8)

set -e

echo "[1/5] 安装编译依赖..."
yum install -y epel-release
yum install -y gcc make autoconf libtool automake asciidoc xmlto git \
               libev-devel pcre pcre-devel zlib zlib-devel

echo "[2/5] 下载 simple-obfs 源码..."
cd /usr/local/src
if [ -d "simple-obfs" ]; then
    echo "simple-obfs 目录已存在，先删除..."
    rm -rf simple-obfs
fi
git clone https://github.com/shadowsocks/simple-obfs.git
cd simple-obfs
git submodule update --init --recursive

echo "[3/5] 编译安装..."
./configure
make
make install

echo "[4/5] 验证安装..."
if command -v obfs-local >/dev/null 2>&1; then
    echo "✅ simple-obfs 安装成功!"
    obfs-local --help | head -n 5
else
    echo "❌ 安装失败，请检查编译日志"
    exit 1
fi

echo "[5/5] 完成，可以在 Shadowsocks 中配置 plugin: obfs-local 使用"