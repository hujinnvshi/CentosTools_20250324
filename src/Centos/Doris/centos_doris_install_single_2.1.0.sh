#!/bin/bash

# 重要：先安装JDK8,再安装MySQL5.x,最后安装Doris2.1.0

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
    # 使用netstat或ss检查端口（兼容不同系统）
    if command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":${port} "; then
            print_error "${port_name}端口(${port})已被占用，请释放后重试"
        fi
    elif command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":${port} "; then
            print_error "${port_name}端口(${port})已被占用，请释放后重试"
        fi
    else
        print_message "警告：未找到netstat或ss，无法检查端口占用情况"
    fi
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
fi

# 设置变量
DORIS_HOME="/data1/Doris2.1.0"
FE_HOME="${DORIS_HOME}/fe"
BE_HOME="${DORIS_HOME}/be"
# 获取本机 IPv4 地址
HOST_IP=$(ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
if [ -z "${HOST_IP}" ]; then
    print_error "无法获取本机 IPv4 地址"
fi
INSTALL_PACKAGE="/tmp/apache-doris-2.1.0-bin-x64.tar.gz"
INSTALL_DIR="/tmp/apache-doris-2.1.0-bin-x64"

# ====================== 新增：端口检查工作 ======================
print_message "开始检查Doris所需端口是否可用..."
# FE 关键端口
check_port 8030 "FE HTTP"       # FE web管理端口
check_port 9020 "FE RPC"        # FE 内部RPC端口
check_port 9030 "FE Query"      # FE MySQL客户端连接端口
# BE 关键端口
check_port 9060 "BE 内部通信"   # BE 内部端口
check_port 8040 "BE HTTP"       # BE web管理端口
check_port 9050 "BE 心跳"       # BE 与FE通信的心跳端口
check_port 8060 "BE BRPC"       # BE BRPC端口
# 其他可能用到的端口（如后续添加follower/observer）
check_port 9010 "FE 副本同步"   # FE follower/observer同步端口
print_message "所有必要端口均未被占用，继续安装..."
# ==============================================================

# 解压安装包
print_message "解压 Doris 安装包..."
if [ ! -f "${INSTALL_PACKAGE}" ]; then
    print_error "Doris 安装包未找到，请确保已下载到 ${INSTALL_PACKAGE}"
fi
mkdir -p ${INSTALL_DIR} || print_error "创建解压目录失败"
tar -xzf ${INSTALL_PACKAGE} -C ${INSTALL_DIR} --strip-components=1 || print_error "解压安装包失败"

# 创建安装目录
print_message "创建安装目录..."
if [ ! -d "/data" ]; then
    print_error "/data 目录不存在，请手动创建并确保有足够权限"
fi
mkdir -p ${DORIS_HOME} ${FE_HOME} ${BE_HOME} || print_error "创建目录失败"

# 移动 FE 和 BE 文件
print_message "移动 FE 和 BE 文件..."
if [ ! -d "/tmp/apache-doris-2.1.0-bin-x64/fe" ] || [ ! -d "/tmp/apache-doris-2.1.0-bin-x64/be" ]; then
    print_error "Doris 安装包未找到，请确保已解压到 /tmp/apache-doris-2.1.0-bin-x64"
fi
cp -r /tmp/apache-doris-2.1.0-bin-x64/fe/* ${FE_HOME} || print_error "移动 FE 文件失败"
cp -r /tmp/apache-doris-2.1.0-bin-x64/be/* ${BE_HOME} || print_error "移动 BE 文件失败"

# 配置 FE
print_message "配置 Doris FE..."
cat > ${FE_HOME}/conf/fe.conf << EOF
# FE 配置
http_port = 8030
rpc_port = 9020
query_port = 9030
priority_networks = ${HOST_IP}/24
meta_dir = ${FE_HOME}/doris-meta
EOF

# 配置 BE
print_message "配置 Doris BE..."
cat > ${BE_HOME}/conf/be.conf << EOF
# BE 配置
be_port = 9060
webserver_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
storage_root_path = ${BE_HOME}/storage
EOF

# 启动 FE
print_message "启动 Doris FE..."
${FE_HOME}/bin/start_fe.sh --daemon || print_error "启动 FE 失败"

# 启动 BE
print_message "启动 Doris BE..."
# 检查并设置 vm.max_map_count
CURRENT_MAP_COUNT=$(sysctl -n vm.max_map_count)
if [ ${CURRENT_MAP_COUNT} -lt 2000000 ]; then
    print_message "当前 vm.max_map_count 值为 ${CURRENT_MAP_COUNT}，设置为 2000000..."
    sysctl -w vm.max_map_count=2000000 || print_error "设置 vm.max_map_count 失败"
    echo "vm.max_map_count=2000000" >> /etc/sysctl.conf || print_error "永久配置 vm.max_map_count 失败"
fi
# 禁用 swap 内存
print_message "禁用 swap 内存..."
swapoff -a || print_error "禁用 swap 内存失败"
sed -i '/swap/d' /etc/fstab || print_error "永久禁用 swap 内存失败"

${BE_HOME}/bin/start_be.sh --daemon || print_error "启动 BE 失败"

# 验证安装
print_message "验证 Doris 安装..."
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 10
    curl http://${HOST_IP}:8030/api/bootstrap && break
    RETRY_COUNT=$((RETRY_COUNT + 1))
    print_message "验证失败，重试中... ($RETRY_COUNT/$MAX_RETRIES)"
done
[ $RETRY_COUNT -eq $MAX_RETRIES ] && print_error "Doris FE 启动失败"

MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 10
    curl http://${HOST_IP}:8040/api/health && break
    RETRY_COUNT=$((RETRY_COUNT + 1))
    print_message "验证失败，重试中... ($RETRY_COUNT/$MAX_RETRIES)"
done
[ $RETRY_COUNT -eq $MAX_RETRIES ] && print_error "Doris BE 启动失败"

# 输出系统信息和优化参数
print_message "系统信息："
echo "FE 端口：8030"
echo "BE 端口：9060"
echo "FE 配置文件：${FE_HOME}/conf/fe.conf"
echo "BE 配置文件：${BE_HOME}/conf/be.conf"
echo "FE 日志目录：${FE_HOME}/log"
echo "BE 日志目录：${BE_HOME}/log"
echo "FE 启动命令：${FE_HOME}/bin/start_fe.sh"
echo "BE 启动命令：${BE_HOME}/bin/start_be.sh"
echo "FE 停止命令：${FE_HOME}/bin/stop_fe.sh"
echo "BE 停止命令：${BE_HOME}/bin/stop_be.sh"
echo "MySQL: mysql -h ${HOST_IP} -P 9030 -u root"
echo "SET PASSWORD FOR 'root' = PASSWORD('Secsmart#612');"
echo "ALTER SYSTEM ADD FOLLOWER \"${HOST_IP}:9010\";"
echo "ALTER SYSTEM ADD OBSERVER \"${HOST_IP}:9010\";"
echo "ALTER SYSTEM ADD BACKEND \"${HOST_IP}:9050\";"

# 完成
print_message "Doris 单节点环境安装完成！"
print_message "FE 管理界面: http://${HOST_IP}:8030"
print_message "BE 管理界面: http://${HOST_IP}:8040"

# 修改 root 用户密码并创建 admin 用户
print_message "修改 root 用户密码并创建 admin 用户..."
mysql -h ${HOST_IP} -P 9030 -u root << EOF
SET PASSWORD FOR 'root' = PASSWORD('Secsmart#612');
CREATE DATABASE IF NOT EXISTS \`admin\`;
CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
if [ $? -ne 0 ]; then
    print_error "修改密码或创建用户失败"
fi
# mysql -h localhost -P 9030 -u root -p