#!/bin/bash

# MongoDB 6.0.4 卸载清理脚本 for CentOS 7.9
# 清理安装但保留安装包：/tmp/mongodb-linux-x86_64-rhel70-6.0.4.tgz
# 创建时间：2023年
# 作者：DeepSeek AI

# 安装参数配置（与安装脚本一致）
MONGO_VERSION="6.0.4"
MONGO_BASE_DIR="/data/mongodb604"
MONGO_SERVICE="/etc/systemd/system/mongod_${MONGO_VERSION}.service"
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
echo -e "\n\033[32m[1/6] 停止并禁用MongoDB服务...\033[0m"
systemctl stop $(basename ${MONGO_SERVICE}) 2>/dev/null
systemctl disable $(basename ${MONGO_SERVICE}) 2>/dev/null
systemctl daemon-reload

# 步骤2：删除系统服务文件
echo -e "\n\033[32m[2/6] 删除系统服务文件...\033[0m"
rm -f ${MONGO_SERVICE}

# 步骤3：删除安装目录
echo -e "\n\033[32m[3/6] 删除安装目录...\033[0m"
if [ -d "${MONGO_BASE_DIR}" ]; then
    echo "删除目录: ${MONGO_BASE_DIR}"
    rm -rf ${MONGO_BASE_DIR}
else
    echo "安装目录不存在: ${MONGO_BASE_DIR}"
fi

# 步骤4：删除符号链接
echo -e "\n\033[32m[4/6] 删除符号链接...\033[0m"
rm -f /usr/bin/mongod
rm -f /usr/bin/mongos

# 步骤5：删除系统用户
echo -e "\n\033[32m[5/6] 删除系统用户...\033[0m"
if id ${SYSTEM_USER} &>/dev/null; then
    echo "删除用户: ${SYSTEM_USER}"
    userdel -r ${SYSTEM_USER} 2>/dev/null
else
    echo "用户不存在: ${SYSTEM_USER}"
fi

# 步骤6：卸载安装的工具
echo -e "\n\033[32m[6/6] 卸载MongoDB工具...\033[0m"
# 卸载mongosh
rpm -e mongodb-mongosh 2>/dev/null

# 卸载MongoDB工具包
yum remove -y mongodb-org-tools 2>/dev/null

# 删除yum仓库文件
rm -f /etc/yum.repos.d/mongodb-org-6.0.repo

echo -e "\n\033[32m清理完成！系统已恢复到安装前的状态。\033[0m"
echo "注意：安装包 /tmp/mongodb-linux-x86_64-rhel70-6.0.4.tgz 已被保留"
echo "现在可以重新运行安装脚本进行全新安装。"