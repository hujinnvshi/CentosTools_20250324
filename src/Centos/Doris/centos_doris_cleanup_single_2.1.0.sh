#!/bin/bash
# 重要：先安装JDK8,再安装MySQL5.x,最后安装Doris2.1.0
# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
fi

# 设置变量
DORIS_HOME="/data/Doris2.1.0"
FE_HOME="${DORIS_HOME}/fe"
BE_HOME="${DORIS_HOME}/be"
INSTALL_DIR="/tmp/apache-doris-2.1.0-bin-x64"

# 停止 FE 和 BE 服务
print_message "停止 Doris FE 和 BE 服务..."
if [ -f "${FE_HOME}/bin/stop_fe.sh" ]; then
    ${FE_HOME}/bin/stop_fe.sh || print_message "停止 FE 服务失败，继续清理..."
fi
if [ -f "${BE_HOME}/bin/stop_be.sh" ]; then
    ${BE_HOME}/bin/stop_be.sh || print_message "停止 BE 服务失败，继续清理..."
fi

# 删除安装目录
print_message "删除 Doris 安装目录..."
if [ -d "${DORIS_HOME}" ]; then
    rm -rf ${DORIS_HOME} || print_error "删除 Doris 安装目录失败"
else
    print_message "Doris 安装目录不存在，跳过删除"
fi

# 删除解压目录
print_message "删除解压目录..."
if [ -d "${INSTALL_DIR}" ]; then
    rm -rf ${INSTALL_DIR} || print_error "删除解压目录失败"
else
    print_message "解压目录不存在，跳过删除"
fi

# 完成
print_message "Doris 单节点环境清理完成！"