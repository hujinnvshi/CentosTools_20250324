# ====== 变量定义 ======
MONGO_VERSION="7.0.12"
BASE_DIR="/data/mongo_cluster_${MONGO_VERSION}"
TARBALL="/tmp/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}.tgz"
BIN_DIR="${BASE_DIR}/bin"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
KEYFILE="${BASE_DIR}/keyfile"
CONFIG_DIR="${BASE_DIR}/config"

# 启动 MongoDB 实例
start_service() {
    local bin=$1
    local conf=$2
    local name=$3
    local logfile=$4
    
    # 检查配置文件是否存在
    if [[ ! -f "$conf" ]]; then
        return 1
    fi
    
    # 启动服务
    "$bin" -f "$conf" --fork >/dev/null 2>&1
    
    return 0
}

# ====== 启动所有节点 ======
echo "" > "$LOG_DIR/config1.log"
echo "" > "$LOG_DIR/shard1.log"
echo "" > "$LOG_DIR/shard2.log"
echo "" > "$LOG_DIR/mongos.log"

start_service "$BIN_DIR/mongod" "$DATA_DIR/config1/mongod.conf" "ConfigServer" "$LOG_DIR/config1.log" || exit 1
start_service "$BIN_DIR/mongod" "$DATA_DIR/shard1/mongod.conf" "Shard1" "$LOG_DIR/shard1.log" || exit 1
start_service "$BIN_DIR/mongod" "$DATA_DIR/shard2/mongod.conf" "Shard2" "$LOG_DIR/shard2.log" || exit 1
start_service "$BIN_DIR/mongos" "$CONFIG_DIR/mongos.conf" "Mongos" "$LOG_DIR/mongos.log" || exit 1

/data/mongo_cluster_7.0.12/bin/mongod -f /data/mongo_cluster_7.0.12/data/config1/mongod.conf
/data/mongo_cluster_7.0.12/bin/mongod -f /data/mongo_cluster_7.0.12/data/shard1/mongod.conf
/data/mongo_cluster_7.0.12/bin/mongod -f /data/mongo_cluster_7.0.12/data/shard2/mongod.conf
/data/mongo_cluster_7.0.12/bin/mongod -f /data/mongo_cluster_7.0.12/config/mongos.conf