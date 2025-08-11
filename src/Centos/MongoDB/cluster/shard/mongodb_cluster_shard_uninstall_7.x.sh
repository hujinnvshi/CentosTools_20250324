#!/bin/bash
# MongoDB 7.0.12 分片集群清理脚本
# 清理点：
# 1. 停止所有 MongoDB 进程
# 2. 删除数据目录
# 3. 删除日志文件
# 4. 删除配置文件
# 5. 保留安装包

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

# 安全删除目录
safe_remove_dir() {
    local dir=$1
    local name=$2
    
    if [[ -d "$dir" ]]; then
        log_step 4 "删除 $name 目录..."
        rm -rf "$dir"
        log $GREEN "✓ $name 目录已删除: $dir"
    else
        log $YELLOW "⚠ $name 目录不存在: $dir"
    fi
}

# 安全删除文件
safe_remove_file() {
    local file=$1
    local name=$2
    
    if [[ -f "$file" ]]; then
        log_step 5 "删除 $name 文件..."
        rm -f "$file"
        log $GREEN "✓ $name 文件已删除: $file"
    else
        log $YELLOW "⚠ $name 文件不存在: $file"
    fi
}

# ====== 主流程 ======
main() {
    # 检查 root 权限
    if [[ "$(id -u)" -ne 0 ]]; then
        log $RED "请以 root 身份运行脚本"
        exit 1
    fi

    echo -e "\n${BOLD}${BLUE}⚠️ 开始清理 MongoDB ${MONGO_VERSION} 分片集群环境...${RESET}"
    log $GREEN "基准目录: $BASE_DIR"

    # ====== 停止所有 MongoDB 进程 ======
    log_step 1 "停止所有 MongoDB 服务..."
    
    # 停止 mongos 进程
    mongos_pids=$(pgrep -f "mongos.*$BASE_DIR")
    if [[ -n "$mongos_pids" ]]; then
        log $YELLOW "停止 Mongos 进程..."
        kill $mongos_pids
        sleep 2
    else
        log $CYAN "未找到运行的 Mongos 进程"
    fi
    
    # 停止 mongod 进程
    mongod_pids=$(pgrep -f "mongod.*$BASE_DIR")
    if [[ -n "$mongod_pids" ]]; then
        log $YELLOW "停止 Mongod 进程..."
        kill $mongod_pids
        sleep 2
    else
        log $CYAN "未找到运行的 Mongod 进程"
    fi
    
    # 确保所有进程已停止
    if pgrep -f "mongod.*$BASE_DIR" || pgrep -f "mongos.*$BASE_DIR"; then
        log $RED "❌ 无法停止所有 MongoDB 进程，尝试强制停止..."
        pkill -9 -f "mongod.*$BASE_DIR"
        pkill -9 -f "mongos.*$BASE_DIR"
        sleep 1
    fi
    
    log $GREEN "✓ 所有 MongoDB 进程已停止"

    # ====== 删除数据目录 ======
    safe_remove_dir "$BASE_DIR/data" "数据"
    
    # ====== 删除日志目录 ======
    safe_remove_dir "$BASE_DIR/logs" "日志"
    
    # ====== 删除配置目录 ======
    safe_remove_dir "$BASE_DIR/config" "配置"
    
    # ====== 删除 keyfile ======
    safe_remove_file "$BASE_DIR/keyfile" "KeyFile"
    
    # ====== 删除二进制文件 ======
    safe_remove_dir "$BASE_DIR/bin" "二进制文件"
    
    # ====== 保留安装包 ======
    log_step 6 "保留安装包..."
    if [[ -f "$TARBALL" ]]; then
        log $GREEN "✓ 安装包已保留: $TARBALL"
    else
        log $YELLOW "⚠ 安装包不存在: $TARBALL"
    fi
    
    # ====== 检查是否完全清理 ======
    log_step 7 "验证清理结果..."
    if [[ -d "$BASE_DIR" ]]; then
        # 列出剩余文件
        remaining_files=$(find "$BASE_DIR" -type f -o -type d | grep -v "$TARBALL")
        
        if [[ -n "$remaining_files" ]]; then
            log $YELLOW "⚠ 以下文件/目录未被删除:"
            echo "$remaining_files"
        else
            log $GREEN "✓ 所有生成的文件和目录已成功删除"
            # 删除空的基础目录
            rmdir "$BASE_DIR" 2>/dev/null
        fi
    else
        log $GREEN "✓ 基准目录已完全删除"
    fi
    
    # ====== 完成清理 ======
    echo -e "\n${BOLD}${GREEN}✅ MongoDB 分片集群环境清理完成！${RESET}"
    log $YELLOW "注意: MongoDB 安装包 ($TARBALL) 已被保留"
}

# 执行主函数
main