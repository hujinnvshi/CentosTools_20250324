#!/bin/bash

# MongoDB 6.0.4 单机一键安装脚本 for CentOS 7.9
# 使用本地安装包：/tmp/mongodb-linux-x86_64-rhel70-6.0.4.tgz
# 安装路径：/data/mongodb604
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
echo -e "\n\033[32m[1/6] 安装系统依赖...\033[0m"
yum install -y epel-release
yum install -y cyrus-sasl cyrus-sasl-gssapi cyrus-sasl-plain libcurl openssl xz-compat-libs

# 步骤2：创建专用用户和目录结构
echo -e "\n\033[32m[2/6] 创建安装目录和环境...\033[0m"

# 创建系统用户
if ! id ${SYSTEM_USER} &>/dev/null; then
    useradd -M -s /sbin/nologin ${SYSTEM_USER}
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
echo -e "\n\033[32m[3/6] 解压安装包...\033[0m"
tar -zxvf ${MONGO_PACKAGE} -C /tmp
cp -r /tmp/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}/bin/* ${MONGO_BASE_DIR}/bin/
chmod +x ${MONGO_BASE_DIR}/bin/*

# 创建符号链接
ln -sf ${MONGO_BASE_DIR}/bin/mongo /usr/bin/mongo
ln -sf ${MONGO_BASE_DIR}/bin/mongod /usr/bin/mongod
ln -sf ${MONGO_BASE_DIR}/bin/mongos /usr/bin/mongos

# 清理临时文件
rm -rf /tmp/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}

# 步骤4：配置MongoDB
echo -e "\n\033[32m[4/6] 配置MongoDB服务...\033[0m"

# 生成配置文件
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
  bindIp: 0.0.0.0
  maxIncomingConnections: 1000

security:
  authorization: enabled

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
echo -e "\n\033[32m[5/6] 启动MongoDB服务...\033[0m"
systemctl daemon-reload
systemctl enable mongod
systemctl start mongod

# 步骤6：验证安装
echo -e "\n\033[32m[6/6] 验证安装...\033[0m"
sleep 3
STATUS=$(systemctl is-active mongod)

if [ "${STATUS}" = "active" ]; then
    echo -e "\n\033[32mMongoDB ${MONGO_VERSION} 已成功安装并启动！\033[0m"
    echo -e "\n服务状态:"
    systemctl status mongod --no-pager
    
    echo -e "\n\033[34m安装信息:\033[0m"
    echo "安装目录: ${MONGO_BASE_DIR}"
    echo "数据目录: ${MONGO_DATA_DIR}/db"
    echo "日志目录: ${MONGO_LOG_DIR}"
    echo "配置文件: ${MONGO_CONF}"
    echo "连接命令: ${MONGO_BASE_DIR}/bin/mongo --host 127.0.0.1:27017"
    
    # 创建管理员用户
    echo -e "\n\033[34m正在创建管理员账户...\033[0m"
    ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9!@#$%^&*')
    ${MONGO_BASE_DIR}/bin/mongo --quiet --eval "db = db.getSiblingDB('admin'); db.createUser({user: 'admin', pwd: '${ADMIN_PASS}', roles: ['root']})"
    
    echo -e "\n\033[32m管理员账户已创建:\033[0m"
    echo "用户名: admin"
    echo "密码: ${ADMIN_PASS}"
    echo -e "\n\033[31m请务必保存此密码！\033[0m"
    
    echo -e "\n\033[32m安装完成！MongoDB 6.0.4 已在 ${MONGO_BASE_DIR} 成功安装并运行。\033[0m"
else
    echo -e "\n\033[31m错误：MongoDB 启动失败！\033[0m"
    echo "查看日志：journalctl -u mongod"
    echo "或查看日志文件：${MONGO_LOG_DIR}/mongod.log"
    exit 1
fi