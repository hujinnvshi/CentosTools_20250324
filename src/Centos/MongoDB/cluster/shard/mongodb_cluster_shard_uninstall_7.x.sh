#!/bin/bash
# MongoDB 分片集群清理脚本
# 用于清理部署过程中创建的所有资源，但保留安装包
# 使用: sudo ./mongo_sharding_cleanup.sh

# ====== 颜色定义 ======
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# ====== 变量定义 ======
MONGO_VERSION="7.0.12"
BASE_DIR="/data/mongo_cluster_${MONGO_VERSION}"
SERVICE_PREFIX="mongod_multi_${MONGO_VERSION}"

# ====== 函数定义 ======
log() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${RESET}"
}

# ====== 主流程 ======
log $YELLOW "⚠️ 开始清理 MongoDB 分片集群环境..."

# 1. 停止所有服务
log $GREEN "✅ 停止所有 MongoDB 服务..."
for service_type in config1 shard1 shard2; do
    service_name="${SERVICE_PREFIX}-${service_type}"
    if systemctl is-active --quiet "$service_name"; then
        log $CYAN "停止服务: $service_name"
        systemctl stop "$service_name"
    fi
done

# 停止 Mongos
if pgrep -f "mongos" >/dev/null; then
    log $CYAN "停止 Mongos 进程"
    pkill -f "mongos"
fi

# 2. 禁用并删除服务
log $GREEN "✅ 删除系统服务..."
for service_type in config1 shard1 shard2; do
    service_name="${SERVICE_PREFIX}-${service_type}"
    service_file="/etc/systemd/system/${service_name}.service"
    
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log $CYAN "禁用服务: $service_name"
        systemctl disable "$service_name"
    fi
    
    if [ -f "$service_file" ]; then
        log $CYAN "删除服务文件: $service_file"
        rm -f "$service_file"
    fi
done

# 重新加载 systemd
systemctl daemon-reload
systemctl reset-failed

# 3. 删除数据目录
log $GREEN "✅ 删除数据目录..."
if [ -d "$BASE_DIR" ]; then
    log $CYAN "删除目录: $BASE_DIR"
    rm -rf "$BASE_DIR"
else
    log $CYAN "目录不存在: $BASE_DIR"
fi

# 4. 删除符号链接
log $GREEN "✅ 删除符号链接..."
links=("/usr/bin/mongod" "/usr/bin/mongos" "/usr/bin/mongosh")
for link in "${links[@]}"; do
    if [ -L "$link" ]; then
        log $CYAN "删除符号链接: $link"
        rm -f "$link"
    fi
done

# 5. 删除管理脚本
log $GREEN "✅ 删除管理脚本..."
scripts=(
    "${BASE_DIR}/mongo-cluster-start.sh"
    "${BASE_DIR}/mongo-cluster-stop.sh"
)
for script in "${scripts[@]}"; do
    if [ -f "$script" ]; then
        log $CYAN "删除脚本: $script"
        rm -f "$script"
    fi
done

# 6. 清理临时文件
log $GREEN "✅ 清理临时文件..."
rm -f /tmp/mongosh.rpm

log $GREEN "✅ 清理完成！"
log $YELLOW "注意: MongoDB 安装包 ($TARBALL) 已被保留"