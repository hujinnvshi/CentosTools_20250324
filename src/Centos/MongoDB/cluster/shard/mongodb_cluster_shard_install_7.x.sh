#!/bin/bash
# MongoDB 7.0.12 单机 Sharding 集群部署脚本
# 优化点：
# - 添加详细的错误处理和日志输出
# - 优化端口检测逻辑
# - 增强副本集初始化流程
# - 添加管理员账户创建验证
# - 改进目录结构和权限管理

# ====== 颜色定义 ======
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# ====== 变量定义 ======
MONGO_VERSION="7.0.12"
BASE_DIR="/data/mongo_cluster_${MONGO_VERSION}"
TARBALL="/tmp/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}.tgz"
BIN_DIR="${BASE_DIR}/bin"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
KEYFILE="${BASE_DIR}/keyfile"

ADMIN_USER="admin"
ADMIN_PASS="Secsmart#612"

# ====== 函数定义 ======

# 打印带颜色的消息
log() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${RESET}"
}

# 检查端口是否可用
check_port() {
    local port=$1
    local original_port=$port
    
    # 检查端口是否被占用
    while lsof -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1; do
        log $YELLOW "⚠ 端口 ${port} 已被占用，尝试使用下一个端口..."
        port=$((port+1))
    done
    
    # 如果端口被替换，记录信息
    if [[ "$port" != "$original_port" ]]; then
        log $YELLOW "端口从 ${original_port} 替换为 ${port}"
    fi
    
    echo $port
}

# 生成配置文件
make_conf() {
    local path=$1
    local port=$2
    local repl=$3
    local role=$4
    local logfile=$5

    cat > "$path/mongod.conf" <<EOF
systemLog:
  destination: file
  path: $logfile
  logAppend: true
storage:
  dbPath: $path
  journal:
    enabled: true
net:
  bindIp: 0.0.0.0
  port: $port
replication:
  replSetName: $repl
sharding:
  clusterRole: $role
security:
  keyFile: $KEYFILE
EOF
}

# 启动 MongoDB 实例并检查状态
start_mongod() {
    local conf=$1
    local name=$2
    
    log $GREEN "✅ 启动 ${name}..."
    $BIN_DIR/mongod -f "$conf" --fork
    
    # 检查进程是否启动成功
    if ! pgrep -f "$conf" >/dev/null; then
        log $RED "❌ ${name} 启动失败，请检查日志: ${conf}"
        exit 1
    fi
}

# 初始化副本集
init_replica_set() {
    local port=$1
    local repl_name=$2
    local members=$3
    
    log $GREEN "✅ 初始化副本集 ${repl_name}..."
    $BIN_DIR/mongosh --quiet --port $port --eval "rs.initiate($members)"
    
    # 等待副本集选举完成
    log $GREEN "等待副本集选举完成（最多 30 秒）..."
    for i in {1..30}; do
        state=$($BIN_DIR/mongosh --quiet --port $port --eval "rs.status().myState" 2>/dev/null)
        if [[ "$state" == "1" ]]; then
            log $GREEN "节点 ${port} 成为 PRIMARY"
            return 0
        fi
        sleep 1
    done
    
    log $RED "❌ 副本集 ${repl_name} 选举超时"
    exit 1
}

# ====== 主流程 ======

# 检查 root 权限
if [[ "$(id -u)" -ne 0 ]]; then
    log $RED "请以 root 身份运行脚本"
    exit 1
fi

# 检查安装包是否存在
if [[ ! -f "$TARBALL" ]]; then
    log $RED "找不到 MongoDB 安装包: $TARBALL"
    exit 1
fi

log $GREEN "✅ 开始部署 MongoDB ${MONGO_VERSION} 分片集群..."
log $GREEN "基准目录: $BASE_DIR"

# ====== 检测并分配端口 ======
log $GREEN "✅ 检测可用端口..."
PORT_MONGOS=$(check_port 27017)
PORT_CONFIG=$(check_port 27019)
PORT_SHARD1=$(check_port 27018)
PORT_SHARD2=$(check_port 27020)

log $GREEN "端口分配:"
log $CYAN "  Mongos:       ${PORT_MONGOS}"
log $CYAN "  ConfigServer: ${PORT_CONFIG}"
log $CYAN "  Shard1:       ${PORT_SHARD1}"
log $CYAN "  Shard2:       ${PORT_SHARD2}"

# ====== 创建目录结构 ======
log $GREEN "✅ 创建目录结构..."
mkdir -p "$BASE_DIR" "$BIN_DIR" "$DATA_DIR" "$LOG_DIR"
mkdir -p "$DATA_DIR/config1" "$DATA_DIR/shard1" "$DATA_DIR/shard2"

# 设置目录权限
chmod 755 "$BASE_DIR"
chown -R $(whoami) "$BASE_DIR"

# ====== 解压安装包 ======
log $GREEN "✅ 解压 MongoDB 安装包..."
tar -xzf "$TARBALL" -C "$BASE_DIR"
cp -avf "$BASE_DIR"/mongodb-linux-*-${MONGO_VERSION}/*  "$BASE_DIR"

# ====== 创建 KeyFile ======
log $GREEN "✅ 创建 KeyFile..."
openssl rand -base64 756 > "$KEYFILE"
chmod 600 "$KEYFILE"

# ====== 生成配置文件 ======
log $GREEN "✅ 生成配置文件..."
make_conf "$DATA_DIR/config1" $PORT_CONFIG "configRepl" "configsvr" "$LOG_DIR/config1.log"
make_conf "$DATA_DIR/shard1" $PORT_SHARD1 "shard1Repl" "shardsvr" "$LOG_DIR/shard1.log"
make_conf "$DATA_DIR/shard2" $PORT_SHARD2 "shard2Repl" "shardsvr" "$LOG_DIR/shard2.log"

# ====== 启动所有节点 ======
start_mongod "$DATA_DIR/config1/mongod.conf" "ConfigServer"
start_mongod "$DATA_DIR/shard1/mongod.conf" "Shard1"
start_mongod "$DATA_DIR/shard2/mongod.conf" "Shard2"

# ====== 启动 Mongos ======
log $GREEN "✅ 启动 Mongos..."
cat > "$BASE_DIR/mongos.conf" <<EOF
systemLog:
  destination: file
  path: $LOG_DIR/mongos.log
  logAppend: true
net:
  bindIp: 0.0.0.0
  port: $PORT_MONGOS
sharding:
  configDB: configRepl/127.0.0.1:$PORT_CONFIG
security:
  keyFile: $KEYFILE
EOF

$BIN_DIR/mongos -f "$BASE_DIR/mongos.conf" --fork

# 检查 mongos 是否启动成功
if ! pgrep -f "$BASE_DIR/mongos.conf" >/dev/null; then
    log $RED "❌ Mongos 启动失败，请检查日志: $LOG_DIR/mongos.log"
    exit 1
fi

# ====== 初始化副本集 ======
init_replica_set $PORT_CONFIG "configRepl" "{_id: 'configRepl', configsvr: true, members: [{_id: 0, host: '127.0.0.1:$PORT_CONFIG'}]}"
init_replica_set $PORT_SHARD1 "shard1Repl" "{_id: 'shard1Repl', members: [{_id: 0, host: '127.0.0.1:$PORT_SHARD1'}]}"
init_replica_set $PORT_SHARD2 "shard2Repl" "{_id: 'shard2Repl', members: [{_id: 0, host: '127.0.0.1:$PORT_SHARD2'}]}"

# ====== 添加分片 ======
log $GREEN "✅ 添加分片到集群..."
$BIN_DIR/mongosh --quiet --port $PORT_MONGOS --eval "sh.addShard('shard1Repl/127.0.0.1:$PORT_SHARD1')"
$BIN_DIR/mongosh --quiet --port $PORT_MONGOS --eval "sh.addShard('shard2Repl/127.0.0.1:$PORT_SHARD2')"

# 验证分片添加
shard_count=$($BIN_DIR/mongosh --quiet --port $PORT_MONGOS --eval "sh.status().shards.length" 2>/dev/null)
if [[ "$shard_count" -ne 2 ]]; then
    log $RED "❌ 分片添加失败，当前分片数量: ${shard_count}"
    exit 1
fi

# ====== 创建管理员账号 ======
log $GREEN "✅ 创建管理员账户..."
$BIN_DIR/mongosh --quiet --port $PORT_MONGOS <<EOF
use admin
db.createUser({
  user: "$ADMIN_USER",
  pwd: "$ADMIN_PASS",
  roles: [
    {role: "root", db: "admin"},
    {role: "clusterAdmin", db: "admin"}
  ]
})
EOF

# 验证管理员账户
auth_result=$($BIN_DIR/mongosh --quiet --port $PORT_MONGOS -u "$ADMIN_USER" -p "$ADMIN_PASS" --authenticationDatabase admin --eval "db.runCommand({connectionStatus:1})" 2>/dev/null)
if ! echo "$auth_result" | grep -q "authenticatedUsers"; then
    log $RED "❌ 管理员账户创建失败"
    exit 1
fi

# ====== 完成部署 ======
log $GREEN "🎉 MongoDB Sharding 集群部署完成！"
log $CYAN "连接命令:"
log $CYAN "  $BIN_DIR/mongosh --port $PORT_MONGOS -u $ADMIN_USER -p '$ADMIN_PASS' --authenticationDatabase admin"
log $CYAN "集群状态检查:"
log $CYAN "  $BIN_DIR/mongosh --port $PORT_MONGOS -u $ADMIN_USER -p '$ADMIN_PASS' --authenticationDatabase admin --eval \"sh.status()\""
log $CYAN "分片信息:"
log $CYAN "  $BIN_DIR/mongosh --port $PORT_MONGOS -u $ADMIN_USER -p '$ADMIN_PASS' --authenticationDatabase admin --eval \"db.adminCommand({listShards:1})\""