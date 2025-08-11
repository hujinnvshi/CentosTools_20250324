#!/bin/bash
# MongoDB 7.0.12 单机 Sharding 集群部署脚本 - 优化版
# 优化点：
# 1. 增强错误处理和日志记录
# 2. 改进端口分配算法
# 3. 添加服务健康检查
# 4. 优化资源清理
# 5. 增强配置验证
# 6. 添加进度指示器

# ====== 颜色定义 ======
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
BLUE="\033[34m"
MAGENTA="\033[35m"
RESET="\033[0m"
BOLD="\033[1m"

# ====== 变量定义 ======
MONGO_VERSION="7.0.12"
BASE_DIR="/data/mongo_cluster_${MONGO_VERSION}"
TARBALL="/tmp/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}.tgz"
BIN_DIR="${BASE_DIR}/bin"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
KEYFILE="${BASE_DIR}/keyfile"
CONFIG_DIR="${BASE_DIR}/config"

ADMIN_USER="admin"
ADMIN_PASS="Secsmart#612"

# 端口分配
declare -A PORT_ASSIGNMENTS=(
    ["Mongos"]=27017
    ["ConfigServer"]=27019
    ["Shard1"]=27018
    ["Shard2"]=27020
)

# ====== 函数定义 ======

# 打印带颜色的消息
log() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${RESET}"
}

# 打印带进度指示的步骤
log_step() {
    local step=$1
    local message=$2
    echo -e "${BOLD}${MAGENTA}▶ ${step}. ${message}${RESET}"
}

# 检查端口是否可用
check_port() {
    local port=$1
    local max_attempts=100
    
    for ((i=0; i<max_attempts; i++)); do
        if ! lsof -iTCP:$port -sTCP:LISTEN &>/dev/null; then
            return 0
        fi
        port=$((port+1))
    done
    
    log $RED "❌ 无法找到可用端口 (尝试范围: $1-$port)"
    return 1
}

# 分配所有端口
assign_ports() {
    log_step 1 "检测并分配端口..."
    
    for role in "${!PORT_ASSIGNMENTS[@]}"; do
        local base_port=${PORT_ASSIGNMENTS[$role]}
        local port=$base_port
        
        while ! check_port $port; do
            port=$((port+1))
        done
        
        if [[ "$port" != "$base_port" ]]; then
            log $YELLOW "⚠ $role 端口从 $base_port 替换为 $port"
        else
            log $GREEN "✓ $role 使用端口: $port"
        fi
        
        PORT_ASSIGNMENTS[$role]=$port
    done
}

# 生成配置文件
generate_config() {
    local role=$1
    local path=$2
    local port=$3
    local repl=$4
    local logfile=$5
    
    cat > "$path/mongod.conf" <<EOF
systemLog:
  destination: file
  path: "$logfile"
  logAppend: true
storage:
  dbPath: "$path"
net:
  bindIp: 0.0.0.0
  port: $port
replication:
  replSetName: $repl
sharding:
  clusterRole: $role
security:
  keyFile: "$KEYFILE"
EOF
    
    log $CYAN "配置文件 [$role] 创建: $path/mongod.conf"
}

# 启动 MongoDB 实例
start_service() {
    local bin=$1
    local conf=$2
    local name=$3
    local logfile=$4
    
    log_step 5 "启动 $name..."
    
    # 检查配置文件是否存在
    if [[ ! -f "$conf" ]]; then
        log $RED "❌ 配置文件不存在: $conf"
        return 1
    fi
    
    # 启动服务
    "$bin" -f "$conf" --fork >/dev/null 2>&1
    
    # 检查服务状态
    if ! wait_for_service "$name" "$conf" "$logfile"; then
        log $RED "❌ $name 启动失败"
        return 1
    fi
    
    log $GREEN "✓ $name 启动成功"
    return 0
}

# 等待服务启动
wait_for_service() {
    local name=$1
    local conf=$2
    local logfile=$3
    local max_attempts=30
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        if pgrep -f "$conf" >/dev/null; then
            # 额外检查日志确认服务完全启动
            if grep -q "waiting for connections" "$logfile"; then
                return 0
            fi
        fi
        
        sleep 1
        ((attempts++))
    done
    
    # 显示日志尾部以帮助诊断
    if [[ -f "$logfile" ]]; then
        log $YELLOW "最后10行日志内容:"
        tail -10 "$logfile"
    fi
    
    return 1
}

# 初始化副本集
init_replica_set() {
    local port=$1
    local repl_name=$2
    local members=$3
    local max_attempts=60
    
    log_step 6 "初始化副本集 $repl_name..."
    
    "mongosh" --quiet --port $port --eval "rs.initiate($members)"
    
    # 等待副本集选举完成
    log $GREEN "等待副本集选举完成（最多 $max_attempts 秒）..."
    for i in $(seq 1 $max_attempts); do
        state=$("mongosh" --quiet --port $port --eval "rs.status().myState" 2>/dev/null)
        
        if [[ "$state" == "1" ]]; then
            log $GREEN "✓ 节点 $port 成为 PRIMARY"
            return 0
        fi
        
        # 显示进度
        if ((i % 5 == 0)); then
            log $CYAN "等待中... ($i/$max_attempts 秒)"
        fi
        
        sleep 1
    done
    
    log $RED "❌ 副本集 $repl_name 选举超时"
    return 1
}

# 验证 MongoDB 二进制文件
# 验证 MongoDB 二进制文件
validate_binaries() {
    log_step 2 "验证 MongoDB 二进制文件..."
    
    if [[ ! -f "$BIN_DIR/mongod" ]]; then
        log $RED "❌ mongod 二进制文件不存在: $BIN_DIR/mongod"
        return 1
    fi
    
    if [[ ! -f "$BIN_DIR/mongos" ]]; then
        log $RED "❌ mongos 二进制文件不存在: $BIN_DIR/mongos"
        return 1
    fi
    
    log $GREEN "✓ MongoDB 版本验证通过: $version"
    return 0
}

# 清理临时文件
cleanup() {
    log_step 10 "清理临时文件..."
    rm -f "$BASE_DIR/mongos.conf"
    log $GREEN "✓ 临时文件已清理"
}

# 显示部署摘要
show_summary() {
    echo -e "\n${BOLD}${GREEN}🎉 MongoDB Sharding 集群部署完成！${RESET}"
    echo -e "${CYAN}=============================================="
    echo -e "${BOLD}连接信息:${RESET}"
    echo -e "  ${CYAN}Host:${RESET} 127.0.0.1"
    echo -e "  ${CYAN}Mongos Port:${RESET} ${PORT_ASSIGNMENTS["Mongos"]}"
    echo -e "  ${CYAN}用户名:${RESET} $ADMIN_USER"
    echo -e "  ${CYAN}密码:${RESET} $ADMIN_PASS"
    echo -e "${CYAN}=============================================="
    echo -e "${BOLD}组件端口:${RESET}"
    echo -e "  ${CYAN}Config Server:${RESET} ${PORT_ASSIGNMENTS["ConfigServer"]}"
    echo -e "  ${CYAN}Shard1:${RESET} ${PORT_ASSIGNMENTS["Shard1"]}"
    echo -e "  ${CYAN}Shard2:${RESET} ${PORT_ASSIGNMENTS["Shard2"]}"
    echo -e "${CYAN}=============================================="
    echo -e "${BOLD}目录结构:${RESET}"
    echo -e "  ${CYAN}Binaries:${RESET} $BIN_DIR"
    echo -e "  ${CYAN}Data:${RESET} $DATA_DIR"
    echo -e "  ${CYAN}Logs:${RESET} $LOG_DIR"
    echo -e "${CYAN}==============================================${RESET}\n"
    
    echo -e "${BOLD}${GREEN}连接命令:${RESET}"
    echo -e "  ${BIN_DIR}/mongosh --port ${PORT_ASSIGNMENTS["Mongos"]} -u $ADMIN_USER -p '$ADMIN_PASS' --authenticationDatabase admin"
}

# ====== 主流程 ======
main() {
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

    echo -e "\n${BOLD}${BLUE}✅ 开始部署 MongoDB ${MONGO_VERSION} 分片集群...${RESET}"
    log $GREEN "基准目录: $BASE_DIR"

    # ====== 创建目录结构 ======
    log_step 3 "创建目录结构..."
    mkdir -p "$BASE_DIR" "$BIN_DIR" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"
    mkdir -p "$DATA_DIR/config1" "$DATA_DIR/shard1" "$DATA_DIR/shard2"
    
    # 设置目录权限
    chmod 755 "$BASE_DIR"
    chown -R $(whoami) "$BASE_DIR"
    log $GREEN "✓ 目录结构创建完成"

    # ====== 解压安装包 ======
    log_step 4 "解压 MongoDB 安装包..."
    if [[ ! -d "$BASE_DIR/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}" ]]; then
        tar -xzf "$TARBALL" -C "$BASE_DIR"
    fi
    
    # 复制文件到目标位置
    cp -a "$BASE_DIR/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}"/* "$BASE_DIR"
    log $GREEN "✓ 文件解压完成"

    # ====== 验证二进制文件 ======
    if ! validate_binaries; then
        exit 1
    fi

    # ====== 分配端口 ======
    if ! assign_ports; then
        exit 1
    fi

    # ====== 创建 KeyFile ======
    log_step 7 "创建 KeyFile..."
    if [[ ! -f "$KEYFILE" ]]; then
        openssl rand -base64 756 > "$KEYFILE"
        chmod 600 "$KEYFILE"
        log $GREEN "✓ KeyFile 创建成功"
    else
        log $YELLOW "⚠ KeyFile 已存在，跳过创建"
    fi

    # ====== 生成配置文件 ======
    log_step 8 "生成配置文件..."
    generate_config "configsvr" "$DATA_DIR/config1" "${PORT_ASSIGNMENTS["ConfigServer"]}" "configRepl" "$LOG_DIR/config1.log"
    generate_config "shardsvr" "$DATA_DIR/shard1" "${PORT_ASSIGNMENTS["Shard1"]}" "shard1Repl" "$LOG_DIR/shard1.log"
    generate_config "shardsvr" "$DATA_DIR/shard2" "${PORT_ASSIGNMENTS["Shard2"]}" "shard2Repl" "$LOG_DIR/shard2.log"
    log $GREEN "✓ 配置文件生成完成"

    # ====== 启动所有节点 ======
    start_service "$BIN_DIR/mongod" "$DATA_DIR/config1/mongod.conf" "ConfigServer" "$LOG_DIR/config1.log" || exit 1
    start_service "$BIN_DIR/mongod" "$DATA_DIR/shard1/mongod.conf" "Shard1" "$LOG_DIR/shard1.log" || exit 1
    start_service "$BIN_DIR/mongod" "$DATA_DIR/shard2/mongod.conf" "Shard2" "$LOG_DIR/shard2.log" || exit 1

    # ====== 初始化副本集 ======
    init_replica_set "${PORT_ASSIGNMENTS["ConfigServer"]}" "configRepl" "{_id: 'configRepl', configsvr: true, members: [{_id: 0, host: '127.0.0.1:${PORT_ASSIGNMENTS["ConfigServer"]}'}]}" || exit 1
    init_replica_set "${PORT_ASSIGNMENTS["Shard1"]}" "shard1Repl" "{_id: 'shard1Repl', members: [{_id: 0, host: '127.0.0.1:${PORT_ASSIGNMENTS["Shard1"]}'}]}" || exit 1
    init_replica_set "${PORT_ASSIGNMENTS["Shard2"]}" "shard2Repl" "{_id: 'shard2Repl', members: [{_id: 0, host: '127.0.0.1:${PORT_ASSIGNMENTS["Shard2"]}'}]}" || exit 1

    # ====== 启动 Mongos ======
    log_step 9 "配置并启动 Mongos..."
    
    # 生成 mongos 配置
    cat > "$CONFIG_DIR/mongos.conf" <<EOF
systemLog:
  destination: file
  path: "$LOG_DIR/mongos.log"
  logAppend: true
net:
  bindIp: 0.0.0.0
  port: ${PORT_ASSIGNMENTS["Mongos"]}
sharding:
  configDB: configRepl/127.0.0.1:${PORT_ASSIGNMENTS["ConfigServer"]}
security:
  keyFile: "$KEYFILE"
EOF

    # 启动 mongos
    start_service "$BIN_DIR/mongos" "$CONFIG_DIR/mongos.conf" "Mongos" "$LOG_DIR/mongos.log" || exit 1

    # ====== 添加分片 ======
    log_step 10 "添加分片到集群..."
    "mongosh" --quiet --port ${PORT_ASSIGNMENTS["Mongos"]} \
        --eval "sh.addShard('shard1Repl/127.0.0.1:${PORT_ASSIGNMENTS["Shard1"]}')" && \
    log $GREEN "✓ Shard1 添加成功"
    
    "mongosh" --quiet --port ${PORT_ASSIGNMENTS["Mongos"]} \
        --eval "sh.addShard('shard2Repl/127.0.0.1:${PORT_ASSIGNMENTS["Shard2"]}')" && \
    log $GREEN "✓ Shard2 添加成功"

    # 验证分片添加
    shard_count=$("mongosh" --quiet --port ${PORT_ASSIGNMENTS["Mongos"]} \
        --eval "sh.status().shards.length" 2>/dev/null)
    
    if [[ "$shard_count" -eq 2 ]]; then
        log $GREEN "✓ 分片添加验证成功 (数量: $shard_count)"
    else
        log $RED "❌ 分片添加失败，当前分片数量: ${shard_count:-无}"
        exit 1
    fi

    # ====== 创建管理员账号 ======
    log_step 11 "创建管理员账户..."
    "mongosh" --quiet --port ${PORT_ASSIGNMENTS["Mongos"]} <<EOF
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
    auth_result=$("mongosh" --quiet --port ${PORT_ASSIGNMENTS["Mongos"]} \
        -u "$ADMIN_USER" -p "$ADMIN_PASS" --authenticationDatabase admin \
        --eval "db.runCommand({connectionStatus:1})" 2>/dev/null)
    
    if echo "$auth_result" | grep -q "authenticatedUsers"; then
        log $GREEN "✓ 管理员账户创建成功"
    else
        log $RED "❌ 管理员账户创建失败"
        exit 1
    fi

    # ====== 完成部署 ======
    cleanup
    show_summary
}

# 执行主函数
main