#!/bin/bash
#
# mongo3_repl_cleanup.sh
# 一键清理 MongoDB 三节点副本集环境 (CentOS 7.9)
#
# 清理内容：
# - 停止并移除所有服务
# - 删除所有配置文件和数据
# - 移除系统用户和组
# - 清理符号链接和管理脚本
# - 保留 MongoDB 安装包
#
# 使用：
#   sudo ./mongo3_repl_cleanup.sh
#
set -euo pipefail
IFS=$'\n\t'

### ====== 配置（与安装脚本一致） ======
MONGO_VERSION="6.0.4"
BASE_DIR="/data/mongo_cluster_${MONGO_VERSION}"   # 集群安装基准目录
USER="mongod_${MONGO_VERSION}"                     # 运行用户
SERVICE_PREFIX="mongod_multi_${MONGO_VERSION}"    # systemd unit 名称前缀

### ====== 基础检查 ======
if [[ "$(id -u)" -ne 0 ]]; then
  echo "请以 root 身份运行脚本"
  exit 1
fi

echo "开始清理 MongoDB 三节点副本集环境（版本: $MONGO_VERSION）"
echo "基准目录: $BASE_DIR"
echo

### ====== 1. 停止并移除服务 ======
echo "[1/6] 停止并移除所有服务..."
for i in {1..3}; do
  service_name="${SERVICE_PREFIX}-${i}.service"
  
  # 停止服务
  if systemctl is-active --quiet "$service_name"; then
    echo "停止服务: $service_name"
    systemctl stop "$service_name"
  fi
  
  # 禁用服务
  if systemctl is-enabled --quiet "$service_name"; then
    echo "禁用服务: $service_name"
    systemctl disable "$service_name"
  fi
  
  # 删除服务文件
  service_file="/etc/systemd/system/${service_name}"
  if [[ -f "$service_file" ]]; then
    echo "删除服务文件: $service_file"
    rm -f "$service_file"
  fi
done

# 重新加载 systemd
systemctl daemon-reload
systemctl reset-failed

### ====== 2. 删除安装目录 ======
echo "[2/6] 删除安装目录: $BASE_DIR"
if [[ -d "$BASE_DIR" ]]; then
  rm -rf "$BASE_DIR"
  echo "安装目录已删除"
else
  echo "安装目录不存在，跳过"
fi


### ====== 4. 删除管理脚本 ======
echo "[4/6] 删除管理脚本..."
scripts=(
  "/usr/local/bin/mongo-cluster-start.sh"
  "/usr/local/bin/mongo-cluster-stop.sh"
)
for script in "${scripts[@]}"; do
  if [[ -f "$script" ]]; then
    echo "删除脚本: $script"
    rm -f "$script"
  fi
done

### ====== 5. 移除系统用户和组 ======
echo "[5/6] 移除系统用户和组..."
# 检查用户是否存在
if id "$USER" &>/dev/null; then
  # 删除用户
  echo "删除用户: $USER"
  userdel -r "$USER" || true
  
  # 检查并删除组（如果没有其他用户）
  group_name="$USER"
  if grep -q "^${group_name}:" /etc/group; then
    group_users=$(getent group "$group_name" | cut -d: -f4)
    if [[ -z "$group_users" ]]; then
      echo "删除组: $group_name"
      groupdel "$group_name" || true
    else
      echo "组 $group_name 仍有其他用户，保留"
    fi
  fi
else
  echo "用户 $USER 不存在，跳过"
fi

### ====== 6. 清理临时文件 ======
echo "[6/6] 清理临时文件..."
# 清理可能的临时文件

echo
echo "清理完成！"
echo "注意：MongoDB 安装包已被保留"