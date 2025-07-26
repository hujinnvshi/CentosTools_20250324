#!/bin/bash

# MongoDB 连接工具安装与测试脚本
# 安装 mongosh 和 MongoDB 工具包，并进行连接测试
# 创建时间：2023年
# 作者：DeepSeek AI

# 参数配置
MONGO_TOOLS_URL="https://downloads.mongodb.com/compass/mongodb-mongosh-1.10.6.x86_64.rpm"
SERVER_IP="127.0.0.1"  # 默认本地连接
ADMIN_USER="admin"
ADMIN_PASSWORD="Secsmart#612"  # 默认密码
PORT="27017"

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：必须使用root权限运行此脚本"
  exit 1
fi

# 步骤1：安装依赖
echo -e "\n\033[32m[1/4] 安装系统依赖...\033[0m"
yum install -y epel-release
yum install -y cyrus-sasl cyrus-sasl-gssapi cyrus-sasl-plain libcurl openssl xz-compat-libs

# 步骤2：安装MongoDB连接工具
echo -e "\n\033[32m[2/4] 安装MongoDB连接工具...\033[0m"

# 安装mongosh
if [ ! -f "/tmp/mongosh.rpm" ]; then
    echo "下载 mongosh 安装包..."
    wget ${MONGO_TOOLS_URL} -O /tmp/mongosh.rpm
    
    # 检查下载是否成功
    if [ ! -f "/tmp/mongosh.rpm" ]; then
        echo -e "\n\033[31m错误：下载 mongosh 失败！\033[0m"
        exit 1
    fi
else
    echo "mongosh 安装包已存在，跳过下载"
fi

# 安装 mongosh
yum install -y /tmp/mongosh.rpm
rm -f /tmp/mongosh.rpm

# 安装MongoDB工具包
cat > /etc/yum.repos.d/mongodb-org-6.0.repo << EOF
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOF

yum install -y mongodb-org-tools

echo -e "\n\033[32m连接工具已安装:\033[0m"
echo "mongosh: $(mongosh --version | head -1)"
echo "mongodump: $(mongodump --version | head -1)"

# 步骤3：配置连接参数
echo -e "\n\033[32m[3/4] 配置连接参数...\033[0m"

# 获取用户输入
read -p "输入MongoDB服务器IP地址 [默认: ${SERVER_IP}]: " input_ip
SERVER_IP=${input_ip:-$SERVER_IP}

read -p "输入管理员用户名 [默认: ${ADMIN_USER}]: " input_user
ADMIN_USER=${input_user:-$ADMIN_USER}

read -p "输入管理员密码 [默认: ${ADMIN_PASSWORD}]: " -s input_pass
echo  # 换行
ADMIN_PASSWORD=${input_pass:-$ADMIN_PASSWORD}

read -p "输入MongoDB端口 [默认: ${PORT}]: " input_port
PORT=${input_port:-$PORT}

# 步骤4：连接测试
echo -e "\n\033[32m[4/4] 执行连接测试...\033[0m"

# 本地连接测试
echo -e "\n\033[32m连接测试命令:\033[0m"
echo "mongosh --host ${SERVER_IP} --port ${PORT} -u ${ADMIN_USER} -p '${ADMIN_PASSWORD}' --authenticationDatabase admin --eval \"db.runCommand({connectionStatus: 1})\""

echo -e "\n\033[32m测试结果:\033[0m"
mongosh --host ${SERVER_IP} --port ${PORT} -u ${ADMIN_USER} -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "db.runCommand({connectionStatus: 1})"

# 检查连接是否成功
if [ $? -eq 0 ]; then
    echo -e "\n\033[32m连接测试成功！\033[0m"
    echo "您可以使用以下命令连接MongoDB:"
    echo "mongosh --host ${SERVER_IP} --port ${PORT} -u ${ADMIN_USER} -p '${ADMIN_PASSWORD}' --authenticationDatabase admin"
else
    echo -e "\n\033[31m错误：连接测试失败！\033[0m"
    echo "可能原因："
    echo "1. MongoDB服务未运行"
    echo "2. 防火墙阻止连接"
    echo "3. 认证信息错误"
    echo "4. 网络不可达"
    exit 1
fi

echo -e "\n\033[32m脚本执行完成！\033[0m"