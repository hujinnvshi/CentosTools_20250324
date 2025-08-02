#!/bin/bash
# OceanBase 单机版一键安装脚本
# 支持 CentOS 7 系统
# 安装包：/tmp/oceanbase-all-in-one-4.3.5_bp3_20250721.el7.x86_64.tar.gz

set -euo pipefail

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 安装依赖
echo "安装系统依赖..."
yum install -y tar wget net-tools

# 检查安装包是否存在
INSTALL_PACKAGE="/tmp/oceanbase-all-in-one-4.3.5_bp3_20250721.el7.x86_64.tar.gz"
if [ ! -f "$INSTALL_PACKAGE" ]; then
    echo "安装包不存在，开始下载..."
    wget -O "$INSTALL_PACKAGE" \
        "https://obbusiness-private.oss-cn-shanghai.aliyuncs.com/download-center/opensource/oceanbase-all-in-one/7/x86_64/oceanbase-all-in-one-4.3.5_bp3_20250721.el7.x86_64.tar.gz"
    
    # 验证下载是否成功
    if [ ! -f "$INSTALL_PACKAGE" ]; then
        echo "下载安装包失败，请手动下载并放置到 /tmp 目录"
        exit 1
    fi
fi

# 解压安装包
echo "解压安装包..."
TMP_DIR="/tmp/oceanbase-install-$(date +%s)"
mkdir -p "$TMP_DIR"
tar -xzf "$INSTALL_PACKAGE" -C "$TMP_DIR"

# 安装OBD
echo "安装OBD..."
cd "$TMP_DIR/oceanbase-all-in-one/bin"
./install.sh

# 验证OBD安装
if ! command -v obd &> /dev/null; then
    echo "OBD安装失败，请检查日志"
    exit 1
fi

source ~/.oceanbase-all-in-one/bin/env.sh

# 部署OceanBase单机版（包含监控组件）
echo "部署OceanBase单机版..."
obd demo -c oceanbase-ce


# 获取连接信息
echo "获取连接信息..."
CONN_INFO=$(obd demo | grep "obclient -h")
if [ -z "$CONN_INFO" ]; then
    echo "部署成功，但未能获取连接信息，请手动运行 'obd demo' 查看"
else
    echo "=================================================="
    echo "✅ OceanBase部署成功！"
    echo "=================================================="
    echo "连接信息:"
    echo "$CONN_INFO"
    echo "=================================================="
    echo "监控组件访问:"
    echo "Grafana: http://$(hostname -I | awk '{print $1}'):3000 (默认账号: admin/admin)"
    echo "Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
    echo "=================================================="
fi

# 清理临时文件
echo "清理临时文件..."
rm -rf "$TMP_DIR"

echo "安装完成！"