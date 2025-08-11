#!/bin/bash

# Doris 2.1.0 单节点安装脚本
# 重要：先安装JDK8,再安装MySQL5.x,最后安装Doris2.1.0
# 优化点：修复端口冲突、增强权限设置、优化存储配置

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查端口是否被占用的函数
check_port() {
    local port=$1
    local port_name=$2
    if ss -tuln | grep -q ":${port} "; then
        print_error "${port_name}端口(${port})已被占用，请释放后重试"
    fi
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
fi

# 检查 Java 环境
if [ -z "$JAVA_HOME" ]; then
    print_message "检测到未设置 JAVA_HOME，尝试查找 JDK..."
    
    # 尝试查找 JDK 安装路径
    if [ -d "/usr/lib/jvm/java-1.8.0" ]; then
        export JAVA_HOME="/usr/lib/jvm/java-1.8.0"
        print_message "检测到 OpenJDK 1.8: 设置 JAVA_HOME=${JAVA_HOME}"
    elif [ -d "/usr/java/jdk1.8.0" ]; then
        export JAVA_HOME="/usr/java/jdk1.8.0"
        print_message "检测到 Oracle JDK 1.8: 设置 JAVA_HOME=${JAVA_HOME}"
    else
        print_error "未检测到 JDK 8 安装，请先安装 JDK 8"
    fi
else
    print_message "已设置 JAVA_HOME=${JAVA_HOME}"
fi

# 设置变量
DORIS_HOME="/data/Doris2.1.0"
FE_HOME="${DORIS_HOME}/fe"
BE_HOME="${DORIS_HOME}/be"
INSTALL_PACKAGE="/tmp/apache-doris-2.1.0-bin-x64.tar.gz"
INSTALL_DIR="/tmp/doris-install"

# 获取本机 IPv4 地址
HOST_IP=$(ip route get 8.8.8.8 | awk '{print $7}' | head -1)
if [ -z "${HOST_IP}" ]; then
    HOST_IP=$(hostname -I | awk '{print $1}')
    print_message "备用方法获取 IP: ${HOST_IP}"
fi

# ====================== 端口检查 ======================
print_message "开始检查Doris所需端口..."
ports_to_check=(
    "8030 FE HTTP"
    "9020 FE RPC"
    "9030 FE Query"
    "9060 BE 内部通信"
    "8040 BE HTTP"
    "9050 BE 心跳"
    "8060 BE BRPC"
)

for item in "${ports_to_check[@]}"; do
    port=$(echo $item | awk '{print $1}')
    name=$(echo $item | awk '{print $2}')
    check_port $port $name
done
print_message "所有必要端口均未被占用，继续安装..."

# ====================== 解压安装 ======================
print_message "解压 Doris 安装包..."
if [ ! -f "${INSTALL_PACKAGE}" ]; then
    print_error "Doris 安装包未找到，请确保已下载到 ${INSTALL_PACKAGE}"
fi

rm -rf ${INSTALL_DIR}
mkdir -p ${INSTALL_DIR}
tar -xzf ${INSTALL_PACKAGE} -C ${INSTALL_DIR} --strip-components=1 || print_error "解压安装包失败"

# 创建安装目录
print_message "创建安装目录..."
mkdir -p ${DORIS_HOME} ${FE_HOME} ${BE_HOME} ${BE_HOME}/storage

# 移动 FE 和 BE 文件
print_message "移动 FE 和 BE 文件..."
cp -r ${INSTALL_DIR}/fe/* ${FE_HOME} || print_error "移动 FE 文件失败"
cp -r ${INSTALL_DIR}/be/* ${BE_HOME} || print_error "移动 BE 文件失败"

# 配置 FE
print_message "配置 Doris FE..."
cat > ${FE_HOME}/conf/fe.conf << EOF
# FE 核心配置
http_port = 8030
rpc_port = 9020
query_port = 9030
priority_networks = ${HOST_IP}/24
meta_dir = ${FE_HOME}/doris-meta

# JVM 优化 (根据内存大小调整)
JAVA_OPTS = "-Xmx8192m -Xms8192m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
EOF

# 配置 BE
print_message "配置 Doris BE..."
cat > ${BE_HOME}/conf/be.conf << EOF
# BE 核心配置
be_port = 9060
webserver_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
storage_root_path = ${BE_HOME}/storage,medium:ssd

# 内存优化 (建议物理内存50%)
mem_limit = 60%
EOF

# ====================== 系统优化 ======================
print_message "进行系统优化配置..."
# 优化 vm.max_map_count 限制
CURRENT_MAP_COUNT=$(sysctl -n vm.max_map_count)
if [ ${CURRENT_MAP_COUNT} -lt 2000000 ]; then
    print_message "优化 vm.max_map_count (当前值 ${CURRENT_MAP_COUNT} -> 2000000)"
    sysctl -w vm.max_map_count=2000000
    echo "vm.max_map_count=2000000" >> /etc/sysctl.conf
fi

# 禁用 swap
if free | grep -q swap; then
    print_message "禁用 swap 内存..."
    swapoff -a
    sed -i '/swap/d' /etc/fstab
fi

# ====================== 启动服务 ======================
print_message "启动 Doris FE..."
${FE_HOME}/bin/start_fe.sh --daemon || print_error "启动 FE 失败"

print_message "启动 Doris BE..."
${BE_HOME}/bin/start_be.sh --daemon || print_error "启动 BE 失败"

# ====================== 验证服务 ======================
print_message "验证 Doris 服务状态..."
check_service() {
    local port=$1
    local service=$2
    local timeout=60
    local start_time=$(date +%s)
    
    while :; do
        if ss -tuln | grep -q ":${port} "; then
            print_message "${service} 在端口 ${port} 成功启动"
            return 0
        fi
        
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_error "${service} 启动超时，查看日志: ${service}/log/*.log"
        fi
        
        sleep 2
    done
}

check_service 8030 "FE"
check_service 8040 "BE"

# ====================== 数据库初始化 ======================
print_message "初始化 Doris 数据库和用户..."
sleep 10 # 确保服务完全就绪

mysql -h ${HOST_IP} -P 9030 -u root <<EOF
-- 修改 root 密码
SET PASSWORD FOR 'root' = PASSWORD('Secsmart#612');

-- 添加 BE 节点 (单节点不需要添加 follower)
ALTER SYSTEM ADD BACKEND "${HOST_IP}:9050";

-- 创建管理数据库
CREATE DATABASE IF NOT EXISTS admin;

-- 创建管理员用户并赋权
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- 验证节点状态
SHOW BACKENDS\G
EOF

[ $? -eq 0 ] || print_error "数据库初始化失败"

# ====================== 完成输出 ======================
print_message "="
print_message "***** Doris 2.1.0 单节点安装完成! *****"
print_message "="
print_message "系统信息:"
print_message "本机 IP 地址: ${HOST_IP}"
print_message "Doris 安装目录: ${DORIS_HOME}"
print_message "FE 配置文件: ${FE_HOME}/conf/fe.conf"
print_message "BE 配置文件: ${BE_HOME}/conf/be.conf"
print_message "="
print_message "访问地址:"
print_message "FE 管理界面: http://${HOST_IP}:8030 (用户名/密码: root/无)"
print_message "BE 管理界面: http://${HOST_IP}:8040"
print_message "="
print_message "MySQL 连接:"
print_message "管理员: mysql -h ${HOST_IP} -P 9030 -u admin -p'Secsmart#612'"
print_message "Root 用户: mysql -h ${HOST_IP} -P 9030 -u root -p'Secsmart#612'"
print_message "="
print_message "常用命令:"
print_message "启动 FE: ${FE_HOME}/bin/start_fe.sh --daemon"
print_message "停止 FE: ${FE_HOME}/bin/stop_fe.sh"
print_message "启动 BE: ${BE_HOME}/bin/start_be.sh --daemon"
print_message "停止 BE: ${BE_HOME}/bin/stop_be.sh"
print_message "查看日志: tail -f ${FE_HOME}/log/fe.log 或 ${BE_HOME}/log/be.log"
print_message "="
print_message "首次使用建议:"
print_message "1. 访问 FE 管理界面创建新用户"
print_message "2. 执行 'SHOW BACKENDS;' 确保 BE 状态健康"
print_message "3. 执行 'CREATE DATABASE test; USE test; CREATE TABLE demo (...) ENGINE=olap;' 测试"
print_message "="

# 清理临时文件
rm -rf ${INSTALL_DIR}
print_message "已清理临时安装文件"