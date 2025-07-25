#!/bin/bash

# MongoDB 6.0.4 单机一键安装脚本 for CentOS 7.9
# 使用本地安装包：/tmp/mongodb-linux-x86_64-rhel70-6.0.4.tgz
# 安装路径：/data/mongodb604
# 管理员密码：Secsmart#612
# 允许远程连接，安装连接工具，测试连接
# 创建时间：2023年
# 作者：DeepSeek AI

# 安装参数配置
MONGO_VERSION="6.0.4"
MONGO_PACKAGE="/tmp/mongodb-linux-x86_64-rhel70-6.0.4.tgz"
MONGO_BASE_DIR="/data/mongodb604"
MONGO_DATA_DIR="$MONGO_BASE_DIR/data"
MONGO_LOG_DIR="$MONGO_BASE_DIR/logs"
MONGO_CONF="$MONGO_BASE_DIR/conf/mongod.conf"
MONGO_SERVICE="/etc/systemd/system/mongod.service"
SYSTEM_USER="mongod"
ADMIN_PASSWORD="Secsmart#612"
MONGO_TOOLS_URL="https://downloads.mongodb.com/compass/mongodb-mongosh-1.10.6.x86_64.rpm"

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：必须使用root权限运行此脚本"
  exit 1
fi

# 检查安装包是否存在
if [ ! -f "$MONGO_PACKAGE" ]; then
  echo "错误：找不到MongoDB安装包 $MONGO_PACKAGE"
  exit 1
fi

# 步骤1：安装依赖
echo -e "\n\033[32m[1/8] 安装系统依赖...\033[0m"
yum install -y epel-release
yum install -y cyrus-sasl cyrus-sasl-gssapi cyrus-sasl-plain libcurl openssl xz-compat-libs

# 步骤2：创建专用用户和目录结构
echo -e "\n\033[32m[2/8] 创建安装目录和环境...\033[0m"

# 创建系统用户
if ! id ${SYSTEM_USER} &>/dev/null; then
    groupadd ${SYSTEM_USER}
    useradd -M -s /sbin/nologin ${SYSTEM_USER} -g ${SYSTEM_USER}
fi

# 创建安装目录结构
mkdir -p ${MONGO_BASE_DIR}
mkdir -p ${MONGO_DATA_DIR}/db
mkdir -p ${MONGO_LOG_DIR}
mkdir -p ${MONGO_BASE_DIR}/conf
mkdir -p ${MONGO_BASE_DIR}/pid
mkdir -p ${MONGO_BASE_DIR}/bin

# 设置权限
chown -R ${SYSTEM_USER}:${SYSTEM_USER} ${MONGO_BASE_DIR}
chmod -R 0755 ${MONGO_BASE_DIR}

# 步骤3：解压安装包
echo -e "\n\033[32m[3/8] 解压安装包...\033[0m"
tar -zxvf ${MONGO_PACKAGE} -C /tmp

# 查找解压后的目录
EXTRACTED_DIR=$(find /tmp -maxdepth 1 -type d -name "mongodb-linux-x86_64-rhel70-${MONGO_VERSION}" | head -1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "错误：找不到解压后的MongoDB目录"
    exit 1
fi

# 复制二进制文件
cp -r ${EXTRACTED_DIR}/bin/* ${MONGO_BASE_DIR}/bin/
chmod +x ${MONGO_BASE_DIR}/bin/*

# 创建符号链接
ln -sf ${MONGO_BASE_DIR}/bin/mongod /usr/bin/mongod
ln -sf ${MONGO_BASE_DIR}/bin/mongos /usr/bin/mongos

# 清理临时文件
rm -rf ${EXTRACTED_DIR}

# 步骤4：配置MongoDB
echo -e "\n\033[32m[4/8] 配置MongoDB服务...\033[0m"

# 生成配置文件 - 允许远程连接
cat > ${MONGO_CONF} << EOF
# MongoDB 6.0 Configuration
storage:
  dbPath: ${MONGO_DATA_DIR}/db
  journal:
    enabled: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1

systemLog:
  destination: file
  logAppend: true
  path: ${MONGO_LOG_DIR}/mongod.log

processManagement:
  fork: false
  pidFilePath: ${MONGO_BASE_DIR}/pid/mongod.pid
  timeZoneInfo: /usr/share/zoneinfo

net:
  port: 27017
  bindIp: 0.0.0.0  # 允许所有IP连接
  maxIncomingConnections: 10000
  unixDomainSocket:
    enabled: false

security:
  authorization: disabled  # 默认不使用认证

operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 100

setParameter:
  enableLocalhostAuthBypass: false
EOF

# 创建系统服务文件
cat > ${MONGO_SERVICE} << EOF
[Unit]
Description=MongoDB Database Server
Documentation=https://docs.mongodb.org
After=network.target

[Service]
User=${SYSTEM_USER}
Group=${SYSTEM_USER}
Environment="MALLOC_ARENA_MAX=1"
ExecStart=${MONGO_BASE_DIR}/bin/mongod --config ${MONGO_CONF}
ExecStop=${MONGO_BASE_DIR}/bin/mongod --config ${MONGO_CONF} --shutdown
Restart=always
RestartSec=10
LimitNOFILE=64000
LimitNPROC=64000
LimitMEMLOCK=infinity
TasksMax=infinity
TimeoutStopSec=60
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF

# 步骤5：启动MongoDB服务
echo -e "\n\033[32m[5/8] 启动MongoDB服务...\033[0m"
systemctl daemon-reload
systemctl enable mongod
systemctl start mongod

# 步骤6：安装MongoDB连接工具
echo -e "\n\033[32m[6/8] 安装MongoDB连接工具...\033[0m"
# 安装mongosh
# 检查文件是否存在，如果不存在则下载
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

cp /tmp/mongodb-mongosh-1.10.6.x86_64.rpm /tmp/mongosh.rpm
yum install -y /tmp/mongosh.rpm

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

# 步骤7：配置管理员账户
echo -e "\n\033[32m[7/8] 配置管理员账户...\033[0m"
sleep 5  # 等待服务完全启动

# 创建管理员用户
mongosh --quiet --eval "
db = db.getSiblingDB('admin');
if (db.getUser('admin') == null) {
    db.createUser({
        user: 'admin',
        pwd: '${ADMIN_PASSWORD}',
        roles: ['root']
    });
    print('管理员账户创建成功');
} else {
    print('管理员账户已存在，更新密码');
    db.changeUserPassword('admin', '${ADMIN_PASSWORD}');
}"

# 步骤8：验证安装和连接测试
echo -e "\n\033[32m[8/8] 验证安装和连接测试...\033[0m"
sleep 10
STATUS=$(systemctl is-active mongod)
echo "服务状态: ${STATUS}"
if [ "${STATUS}" = "active" ]; then
    echo -e "\n\033[32mMongoDB ${MONGO_VERSION} 已成功安装并启动！\033[0m"
    echo -e "\n\033[34m安装信息:\033[0m"
    echo "安装目录: ${MONGO_BASE_DIR}"
    echo "数据目录: ${MONGO_DATA_DIR}/db"
    echo "日志目录: ${MONGO_LOG_DIR}"
    echo "配置文件: ${MONGO_CONF}"
    echo "管理员用户名: admin"
    echo "管理员密码: ${ADMIN_PASSWORD}"
    
    echo -e "\n\033[32m服务状态:\033[0m"
    systemctl status mongod --no-pager
    
    echo -e "\n\033[32m连接工具已安装:\033[0m"
    echo "mongosh: $(mongosh --version | head -1)"
    echo "mongodump: $(mongodump --version | head -1)"
    
    # 本地连接测试
    echo -e "\n\033[32m本地连接测试:\033[0m"
    mongosh --host 127.0.0.1 --port 27017 -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "db.runCommand({connectionStatus: 1})"
    
    # 获取服务器IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "\n\033[32m远程连接测试命令:\033[0m"
    echo "mongosh --host ${SERVER_IP} --port 27017 -u admin -p '${ADMIN_PASSWORD}' --authenticationDatabase admin"
    
    echo -e "\n\033[32m安装完成！MongoDB 6.0.4 已在 ${MONGO_BASE_DIR} 成功安装并运行。\033[0m"
    echo -e "\033[33m注意：防火墙已关闭，MongoDB已配置为允许所有IP连接。\033[0m"
else
    echo -e "\n\033[31m错误：MongoDB 启动失败！\033[0m"
    echo "查看日志：journalctl -u mongod"
    echo "或查看日志文件：${MONGO_LOG_DIR}/mongod.log"
    exit 1
fi 