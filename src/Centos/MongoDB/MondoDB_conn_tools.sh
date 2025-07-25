#!/bin/bash

# 或者直接下载 RPM 包
# wget https://downloads.mongodb.com/compass/mongodb-mongosh-1.10.6.x86_64.rpm -O mongosh-1.10.6.rpm

# 或者直接下载 RPM 包
# wget https://repo.mongodb.org/yum/redhat/7/mongodb-org/6.0/x86_64/RPMS/mongodb-org-tools-6.0.4-1.el7.x86_64.rpm -O mongodb-tools.rpm

# MongoDB 客户端工具RPM安装脚本
# 创建时间：2023年
# 作者：DeepSeek AI

# RPM包位置
MONGO_SH_RPM="/tmp/mongosh-1.10.6.rpm"
MONGO_TOOLS_RPM="/tmp/mongodb-tools.rpm"

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：必须使用root权限运行此脚本"
  exit 1
fi

# 检查RPM包是否存在
if [ ! -f "$MONGO_SH_RPM" ]; then
  echo "错误：找不到MongoDB Shell RPM包 $MONGO_SH_RPM"
  exit 1
fi

if [ ! -f "$MONGO_TOOLS_RPM" ]; then
  echo "错误：找不到MongoDB工具RPM包 $MONGO_TOOLS_RPM"
  exit 1
fi

# 安装 MongoDB Shell
echo -e "\n\033[32m[1/2] 安装MongoDB Shell...\033[0m"
rpm -ivh ${MONGO_SH_RPM}

# 安装 MongoDB Database Tools
echo -e "\n\033[32m[2/2] 安装MongoDB数据库工具...\033[0m"
rpm -ivh ${MONGO_TOOLS_RPM}

# 验证安装
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "\n\033[34m版本信息:\033[0m"
mongosh --version
mongodump --version

echo -e "\n\033[32m可以使用以下命令连接MongoDB:\033[0m"
echo "mongosh 'mongodb://admin:Secsmart#612@服务器IP:27017' --authenticationDatabase admin"