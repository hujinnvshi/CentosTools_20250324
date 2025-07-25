#!/bin/bash

# MongoDB 6.0.4 清理脚本 for CentOS 7.9
# 用于清理之前安装的MongoDB，准备重新安装
# 创建时间：2023年
# 作者：DeepSeek AI

# 安装参数配置（与安装脚本一致）
MONGO_BASE_DIR="/data/mongodb604"
MONGO_SERVICE="/etc/systemd/system/mongod.service"
SYSTEM_USER="mongod"

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：必须使用root权限运行此脚本"
  exit 1
fi

echo -e "\n\033[31m[警告] 此操作将完全删除MongoDB安装，包括所有数据！\033[0m"
read -p "确定要清理MongoDB安装吗？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 0
fi

# 步骤1：停止并禁用服务
echo -e "\n\033[32m[1/5] 停止并禁用MongoDB服务...\033[0m"
systemctl stop mongod 2>/dev/null
systemctl disable mongod 2>/dev/null
systemctl daemon-reload

# 步骤2：删除系统服务文件
echo -e "\n\033[32m[2/5] 删除系统服务文件...\033[0m"
rm -f ${MONGO_SERVICE}
rm -f /usr/lib/systemd/system/mongod.service 2>/dev/null

# 步骤3：删除安装目录
echo -e "\n\033[32m[3/5] 删除安装目录...\033[0m"
if [ -d "${MONGO_BASE_DIR}" ]; then
    echo "删除目录: ${MONGO_BASE_DIR}"
    rm -rf ${MONGO_BASE_DIR}
else
    echo "安装目录不存在: ${MONGO_BASE_DIR}"
fi

# 步骤4：删除符号链接
echo -e "\n\033[32m[4/5] 删除符号链接...\033[0m"
rm -f /usr/bin/mongo
rm -f /usr/bin/mongod
rm -f /usr/bin/mongos

# 步骤5：删除系统用户
echo -e "\n\033[32m[5/5] 删除系统用户...\033[0m"
if id ${SYSTEM_USER} &>/dev/null; then
    echo "删除用户: ${SYSTEM_USER}"
    userdel -r ${SYSTEM_USER} 2>/dev/null
else
    echo "用户不存在: ${SYSTEM_USER}"
fi

# 清理临时文件
echo -e "\n\033[32m清理临时文件...\033[0m"
# rm -rf /tmp/mongodb-* 2>/dev/null

echo -e "\n\033[32m清理完成！系统已恢复到安装前的状态。\033[0m"
echo "现在可以重新运行安装脚本进行全新安装。"