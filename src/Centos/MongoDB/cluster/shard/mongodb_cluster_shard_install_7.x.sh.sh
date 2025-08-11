#!/bin/bash
set -e

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NC='\033[0m' # 无颜色

# === 基础变量 ===
BASE_DIR=/data/mongodb
PKG_PATH=/tmp/mongodb-linux-x86_64-rhel70-7.0.12.tgz
MONGO_HOME=$BASE_DIR/bin/bin
ADMIN_USER=admin
ADMIN_PWD='Secsmart#612'

# 初始端口
PORT_MONGOS=27017
PORT_CONFIG=27019
PORT_SHARD1=27018
PORT_SHARD2=27020

# === 端口检测函数 ===
check_port() {
  local PORT=$1
  while ss -lnt | awk '{print $4}' | grep -q ":$PORT$"; do
    echo -e "${RED}⚠ 端口 $PORT 已被占用，尝试使用下一个端口...${NC}"
    PORT=$((PORT+1))
  done
  echo $PORT
}

# 检查并更新端口
PORT_MONGOS=$(check_port $PORT_MONGOS)
PORT_CONFIG=$(check_port $PORT_CONFIG)
PORT_SHARD1=$(check_port $PORT_SHARD1)
PORT_SHARD2=$(check_port $PORT_SHARD2)

echo -e "${GREEN}✅ 使用端口:${NC}"
echo -e "  Mongos:       ${GREEN}$PORT_MONGOS${NC}"
echo -e "  Config server:${GREEN}$PORT_CONFIG${NC}"
echo -e "  Shard1:       ${GREEN}$PORT_SHARD1${NC}"
echo -e "  Shard2:       ${GREEN}$PORT_SHARD2${NC}"

# === 1. 目录准备 ===
echo -e "${BLUE}[1/6] 创建目录结构...${NC}"
mkdir -p $BASE_DIR/{config1,shard1,shard2,logs,scripts}
if [ ! -d "$BASE_DIR/bin" ]; then
  tar -xvf $PKG_PATH -C $BASE_DIR
  mv $BASE_DIR/mongodb-linux-x86_64-rhel70-7.0.12 $BASE_DIR/bin
fi

# === 2. 写配置文件 ===
echo -e "${BLUE}[2/6] 生成配置文件...${NC}"

# Config server
cat > $BASE_DIR/config1/mongod.conf <<EOF
systemLog:
  destination: file
  path: $BASE_DIR/logs/config1.log
  logAppend: true
storage:
  dbPath: $BASE_DIR/config1
net:
  bindIp: 0.0.0.0
  port: $PORT_CONFIG
replication:
  replSetName: configRepl
sharding:
  clusterRole: configsvr
EOF

# Shard1
cat > $BASE_DIR/shard1/mongod.conf <<EOF
systemLog:
  destination: file
  path: $BASE_DIR/logs/shard1.log
  logAppend: true
storage:
  dbPath: $BASE_DIR/shard1
net:
  bindIp: 0.0.0.0
  port: $PORT_SHARD1
replication:
  replSetName: shard1Repl
sharding:
  clusterRole: shardsvr
EOF

# Shard2
cat > $BASE_DIR/shard2/mongod.conf <<EOF
systemLog:
  destination: file
  path: $BASE_DIR/logs/shard2.log
  logAppend: true
storage:
  dbPath: $BASE_DIR/shard2
net:
  bindIp: 0.0.0.0
  port: $PORT_SHARD2
replication:
  replSetName: shard2Repl
sharding:
  clusterRole: shardsvr
EOF

# === 3. 启动所有实例 ===
echo -e "${BLUE}[3/6] 启动 MongoDB 实例...${NC}"
$MONGO_HOME/mongod -f $BASE_DIR/config1/mongod.conf --fork
$MONGO_HOME/mongod -f $BASE_DIR/shard1/mongod.conf --fork
$MONGO_HOME/mongod -f $BASE_DIR/shard2/mongod.conf --fork
$MONGO_HOME/mongos --configdb configRepl/127.0.0.1:$PORT_CONFIG \
                   --bind_ip 0.0.0.0 \
                   --port $PORT_MONGOS \
                   --logpath $BASE_DIR/logs/mongos.log \
                   --fork

sleep 3

# === 4. 初始化副本集 ===
echo -e "${BLUE}[4/6] 初始化副本集...${NC}"
$MONGO_HOME/mongosh --port $PORT_CONFIG --eval 'rs.initiate({_id: "configRepl", members: [{_id: 0, host: "127.0.0.1:'$PORT_CONFIG'"}]})'
$MONGO_HOME/mongosh --port $PORT_SHARD1 --eval 'rs.initiate({_id: "shard1Repl", members: [{_id: 0, host: "127.0.0.1:'$PORT_SHARD1'"}]})'
$MONGO_HOME/mongosh --port $PORT_SHARD2 --eval 'rs.initiate({_id: "shard2Repl", members: [{_id: 0, host: "127.0.0.1:'$PORT_SHARD2'"}]})'

sleep 3

# === 5. 配置分片 & 创建用户 ===
echo -e "${BLUE}[5/6] 配置分片并创建管理员账号...${NC}"
$MONGO_HOME/mongosh --port $PORT_MONGOS <<EOF
sh.addShard("shard1Repl/127.0.0.1:$PORT_SHARD1")
sh.addShard("shard2Repl/127.0.0.1:$PORT_SHARD2")
use admin
db.createUser({user: "$ADMIN_USER", pwd: "$ADMIN_PWD", roles: ["root"]})
EOF

# === 6. 测试连接 ===
echo -e "${BLUE}[6/6] 测试连接...${NC}"
$MONGO_HOME/mongosh --port $PORT_MONGOS -u $ADMIN_USER -p "$ADMIN_PWD" --authenticationDatabase admin --eval 'db.runCommand({ connectionStatus: 1 })'

echo -e "${GREEN}✅ MongoDB 单机路由集群部署完成！${NC}"
echo -e "连接命令：${GREEN}mongosh --port $PORT_MONGOS -u $ADMIN_USER -p '$ADMIN_PWD' --authenticationDatabase admin${NC}"