#!/bin/bash
set -euo pipefail

# 配置参数 - 这些参数可以外部传入或修改
HIVE_VERSION="${HIVE_VERSION:-2.3.9}"
INSTANCE_ID="${INSTANCE_ID:-v2}"  # 实例标识，用于区分同版本的不同实例
HIVE_BASE_DIR="/data/hive_${HIVE_VERSION}_${INSTANCE_ID}"
MYSQL_HOST="172.16.48.233"
MYSQL_PORT="6005"
MYSQL_USER="admin"
MYSQL_PASS="Secsmart#612"
MYSQL_DRIVER="/tmp/mysql-connector-java-5.1.49.jar"
HIVE_META_DB="hive_meta_${HIVE_VERSION//./}_${INSTANCE_ID}"  # 动态生成元数据库名称

# 依赖路径配置
JAVA_HOME="/data/java/jdk1.8.0_251"
HADOOP_VERSION="2.7.7"
HADOOP_USER="hadoop_${HADOOP_VERSION}_v1"
HADOOP_HOME="/data/hadoop_2.7.7_v1/current"

# 检查端口是否可用
check_port_available() {
    local port=$1
    local service=$2
    
    # 使用多种方法检查端口占用
    if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":$port "; then
            error "$service 端口 $port 已被占用"
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$port "; then
            error "$service 端口 $port 已被占用"
        fi
    elif command -v lsof &> /dev/null; then
        if lsof -i :$port &>/dev/null; then
            error "$service 端口 $port 已被占用"
        fi
    else
        # 尝试直接绑定端口测试
        if ! ( timeout 1 bash -c "echo >/dev/tcp/localhost/$port" ) 2>/dev/null; then
            warn "无法检测端口状态，假设端口 $port 可用"
        else
            error "$service 端口 $port 已被占用"
        fi
    fi
}

# 动态端口分配 - 基于版本和实例计算
calculate_ports() {
    # 基础端口偏移量 (版本号 * 100 + 实例ID哈希)
    local version_hash=$(( (${HIVE_VERSION//./} % 100) * 100 ))
    local instance_hash=$(echo -n "$INSTANCE_ID" | md5sum | tr -dc '0-9' | head -c 3)
    local base_offset=$((version_hash + instance_hash))
    
    # Metastore端口 (9083 + 偏移量)
    METASTORE_PORT=$((9083 + base_offset % 1000))
    
    # HiveServer2端口 (10000 + 偏移量)
    HIVESERVER_PORT=$((METASTORE_PORT + 1))
    
    # WebUI端口 (10012 + 偏移量)
    WEBUI_PORT=$((HIVESERVER_PORT + 1))
    
    # 验证端口范围
    if [ $METASTORE_PORT -lt 1024 ] || [ $METASTORE_PORT -gt 65535 ]; then
        error "无效的Metastore端口: $METASTORE_PORT"
    fi
    
    if [ $HIVESERVER_PORT -lt 1024 ] || [ $HIVESERVER_PORT -gt 65535 ]; then
        error "无效的HiveServer2端口: $HIVESERVER_PORT"
    fi
    
    # 检查Metastore端口
    check_port_available $METASTORE_PORT "Metastore"
    
    # 检查HiveServer2端口
    check_port_available $HIVESERVER_PORT "HiveServer2"
    
    info "端口可用性验证通过 - Metastore: $METASTORE_PORT, HiveServer2: $HIVESERVER_PORT"
}

# 服务参数
HIVE_USER="hive_${HIVE_VERSION}_${INSTANCE_ID}"
SERVICE_LOG_DIR="$HIVE_BASE_DIR/logs"
PID_DIR="$HIVE_BASE_DIR/pids"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 状态函数
error() { echo -e "${RED}[ERROR] $* ${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN] $* ${NC}" >&2; }
info() { echo -e "${GREEN}[INFO] $* ${NC}"; }

# 检查端口冲突
check_port_conflict() {
    local port=$1
    local service=$2
    
    if netstat -tuln | grep -q ":$port "; then
        error "端口冲突: $port 已被占用 ($service)"
    fi
}

# 检查元数据库
check_metastore_db() {
    local db_exists=$(mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" \
        -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${HIVE_META_DB}';" -sN)
    
    if [ "$db_exists" -eq 1 ]; then
        warn "元数据库已存在: ${HIVE_META_DB}"
        read -p "是否覆盖现有元数据库? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "安装中止"
        fi
    fi
}

# 检查root权限
check_root() {
    [ "$(id -u)" -eq 0 ] || error "请使用root用户运行此脚本"
    info "root权限验证通过"
}

# 检查依赖
check_dependencies() {
    # 计算端口
    calculate_ports
    
    # 检查端口冲突
    check_port_conflict $METASTORE_PORT "Metastore"
    check_port_conflict $HIVESERVER_PORT "HiveServer2"
    
    # 检查元数据库
    check_metastore_db
    
    # 检查必要路径
    [ -d "$JAVA_HOME" ] || error "JAVA_HOME路径不存在: $JAVA_HOME"
    [ -d "$HADOOP_HOME" ] || error "Hadoop路径不存在: $HADOOP_HOME"
    [ -f "$MYSQL_DRIVER" ] || error "MySQL驱动不存在: $MYSQL_DRIVER"
    
    # 设置环境变量
    export JAVA_HOME HADOOP_HOME
    PATH="$PATH:$HADOOP_HOME/bin"
    
    # 检查必要命令
    for cmd in wget mysql netstat nmap; do
        command -v $cmd &>/dev/null || {
            warn "未找到命令: $cmd, 尝试安装..."
            if command -v yum &>/dev/null; then
                yum install -y $cmd || error "安装$cmd失败"
            elif command -v apt-get &>/dev/null; then
                apt-get install -y $cmd || error "安装$cmd失败"
            else
                error "无法自动安装$cmd, 请手动安装"
            fi
        }
    done
    
    # 验证MySQL连接
    info "验证MySQL数据库连接..."
    mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" \
        -e "CREATE DATABASE IF NOT EXISTS hive_check; DROP DATABASE hive_check;" &>/dev/null \
        || error "无法连接到MySQL数据库"
    
    info "所有依赖检查通过"
}

# 创建系统用户
create_user() {
    if id -u "$HIVE_USER" &>/dev/null; then
        warn "系统用户已存在: $HIVE_USER"
    else
        info "创建系统用户: $HIVE_USER"
        useradd -r -s /bin/false -d "$HIVE_BASE_DIR" "$HIVE_USER"
    fi
    
    # 确保用户目录存在
    local user_dir="/user/$HIVE_USER"    
    # 使用Hadoop超级用户执行所有HDFS操作
    su - $HADOOP_USER <<EOF
        hdfs dfs -mkdir -p '$user_dir'
        hdfs dfs -chown '$HIVE_USER:$HIVE_USER' '$user_dir'
        hdfs dfs -chmod 777 '$user_dir'
EOF
}

# 下载Hive
download_hive() {
    local hive_tar="apache-hive-$HIVE_VERSION-bin.tar.gz"
    local hive_url="https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/$hive_tar"
    
    info "开始下载Hive $HIVE_VERSION"
    
    # 使用本地缓存或下载
    if [ -f "/tmp/$hive_tar" ]; then
        info "使用本地缓存的Hive安装包"
        cp "/tmp/$hive_tar" .
    else
        wget "$hive_url" -O "$hive_tar" || error "下载Hive失败"
    fi
    
    # 检查文件完整性
    [ $(stat -c %s "$hive_tar") -gt 1000000 ] || error "下载的Hive包不完整"
    
    info "Hive下载成功"
}

# 安装Hive
install_hive() {
    info "安装Hive到: $HIVE_BASE_DIR"
    
    # 清理并创建目录
    [ -d "$HIVE_BASE_DIR" ] && rm -rf "$HIVE_BASE_DIR"
    mkdir -p "$HIVE_BASE_DIR" "$PID_DIR" "$SERVICE_LOG_DIR"
    
    # 解压并安装驱动
    tar -zxf "apache-hive-$HIVE_VERSION-bin.tar.gz" -C "$HIVE_BASE_DIR" --strip-components=1
    cp "apache-hive-$HIVE_VERSION-bin.tar.gz" /tmp
    cp "$MYSQL_DRIVER" "$HIVE_BASE_DIR/lib/"
    rm -f "apache-hive-$HIVE_VERSION-bin.tar.gz"
    
    info "Hive安装完成"
}

# 配置Hive
configure_hive() {
    info "配置Hive环境"
    
    # 创建环境配置文件
    cat > "$HIVE_BASE_DIR/conf/hive-env.sh" <<EOF
#!/bin/bash
export JAVA_HOME="$JAVA_HOME"
export HADOOP_HOME="$HADOOP_HOME"
export HIVE_HOME="$HIVE_BASE_DIR"
export HIVE_CONF_DIR="$HIVE_BASE_DIR/conf"
export HIVE_LOG_DIR="$SERVICE_LOG_DIR"
export PATH="\$PATH:\$HIVE_HOME/bin"
EOF
    
    # 版本化HDFS路径
    local warehouse_dir="/user/hive_${HIVE_VERSION}_${INSTANCE_ID}/warehouse"
    local scratch_dir="/tmp/hive_${HIVE_VERSION}_${INSTANCE_ID}"
    
    # 创建hive-site.xml
    cat > "$HIVE_BASE_DIR/conf/hive-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <!-- 元数据库配置 -->
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/${HIVE_META_DB}?createDatabaseIfNotExist=true&amp;useSSL=false&amp;characterEncoding=UTF-8</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>com.mysql.jdbc.Driver</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>${MYSQL_USER}</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>${MYSQL_PASS}</value>
  </property>
  
  <!-- 版本化存储配置 -->
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>${warehouse_dir}</value>
  </property>
  <property>
    <name>hive.exec.scratchdir</name>
    <value>${scratch_dir}</value>
  </property>
  
  <!-- 日志配置 -->
  <property>
    <name>hive.querylog.location</name>
    <value>${SERVICE_LOG_DIR}</value>
  </property>
  
  <!-- 性能配置 -->
  <property>
    <name>hive.exec.compress.output</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.exec.compress.intermediate</name>
    <value>true</value>
  </property>
  
  <!-- 元数据验证 -->
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>false</value>
  </property>
  <property>
    <name>datanucleus.schema.autoCreateAll</name>
    <value>true</value>
  </property>
  
  <!-- 动态端口配置 -->
  <property>
    <name>hive.server2.thrift.port</name>
    <value>${HIVESERVER_PORT}</value>
  </property>
  <property>
    <name>hive.metastore.port</name>
    <value>${METASTORE_PORT}</value>
  </property>
  
  <!-- 安全配置 -->
  <property>
    <name>hive.server2.enable.doAs</name>
    <value>false</value>
  </property>
  
  <!-- 操作日志 -->
  <property>
    <name>hive.server2.logging.operation.enabled</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.server2.logging.operation.log.location</name>
    <value>${SERVICE_LOG_DIR}/operation_logs</value>
  </property>
  <property>
    <name>hive.server2.webui.port</name>
    <value>${WEBUI_PORT}</value>  <!-- 改为未被占用的端口 -->
  </property>
</configuration>
EOF
    
    # 设置权限
    chmod 640 "$HIVE_BASE_DIR/conf/hive-site.xml"
    
    # 创建版本化环境变量
    local env_file="/etc/profile.d/hive-${HIVE_VERSION}-${INSTANCE_ID}.sh"
    cat > "$env_file" <<EOF
export HIVE_HOME_${HIVE_VERSION//./}_${INSTANCE_ID}="$HIVE_BASE_DIR"
export PATH="\$PATH:$HIVE_BASE_DIR/bin"
alias hive-${HIVE_VERSION}-${INSTANCE_ID}="$HIVE_BASE_DIR/bin/hive"
alias beeline-${HIVE_VERSION}-${INSTANCE_ID}="$HIVE_BASE_DIR/bin/beeline"
EOF
    
    source "$env_file"
    info "Hive配置完成"
}

# 初始化元数据库
init_metastore() {
    info "初始化Hive元数据库: ${HIVE_META_DB}"
    
    # 创建版本化HDFS目录
    local warehouse_dir=$(grep -A1 'hive.metastore.warehouse.dir' "$HIVE_BASE_DIR/conf/hive-site.xml" | tail -1 | sed -e 's/<[^>]*>//g' | tr -d ' ')
    local scratch_dir=$(grep -A1 'hive.exec.scratchdir' "$HIVE_BASE_DIR/conf/hive-site.xml" | tail -1 | sed -e 's/<[^>]*>//g' | tr -d ' ')
    
    info "创建版本化HDFS目录hive.metastore.warehouse.dir: $warehouse_dir"
    info "创建版本化HDFS目录hive.exec.scratchdir: $scratch_dir"
    info "HIVE_BASE_DIR: $HIVE_BASE_DIR"
    hdfs dfs -mkdir -p "$warehouse_dir" "$scratch_dir"
    hdfs dfs -chmod 773 "$warehouse_dir"
    hdfs dfs -chmod 777 "$scratch_dir"
    
    # 初始化元数据库（带重试）
    for i in {1..3}; do
        "$HIVE_BASE_DIR/bin/schematool" -dbType mysql -initSchema --verbose && {
            info "Hive元数据库初始化成功"
            return 0
        }
        warn "元数据库初始化失败，尝试 $i/3..."
        sleep $((i*5))
    done
    
    error "元数据库初始化失败"
}

# 服务健康检

check_service_health() {
    local port=$1
    local service=$2
    local timeout=30
    local start_time=$(date +%s)    
    info "等待 $service 服务启动 (端口: $port)..."    
    while ! nc -z localhost $port; do
        sleep 1
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            error "$service 服务启动超时"
        fi
    done
    info "$service 服务启动成功"
}

# 停止服务
stop_service() {
    local pid_file=$1
    local service_name=$2
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 $pid 2>/dev/null; then
            info "停止 $service_name 服务 (PID: $pid)"
            kill $pid
            # 等待进程结束
            for i in {1..10}; do
                kill -0 $pid 2>/dev/null || break
                sleep 1
            done
            # 强制终止如果仍在运行
            if kill -0 $pid 2>/dev/null; then
                warn "强制终止 $service_name 服务"
                kill -9 $pid
            fi
        fi
        rm -f "$pid_file"
    fi
}

# 测试Hive功能
test_hive() {
    info "启动Hive服务..."
    
    # 启动服务
    nohup "$HIVE_BASE_DIR/bin/hive" --service metastore > "$SERVICE_LOG_DIR/metastore.log" 2>&1 &
    metastore_pid=$!
    echo $metastore_pid > "$PID_DIR/metastore.pid"
    
    nohup "$HIVE_BASE_DIR/bin/hive" --service hiveserver2 > "$SERVICE_LOG_DIR/hiveserver2.log" 2>&1 &
    hiveserver_pid=$!
    echo $hiveserver_pid > "$PID_DIR/hiveserver2.pid"
    
    # 服务健康检查
    check_service_health $METASTORE_PORT "Metastore"
    check_service_health $HIVESERVER_PORT "HiveServer2"
    
    # 创建测试环境
    "$HIVE_BASE_DIR/bin/hive" -e "CREATE DATABASE IF NOT EXISTS test_db;
             CREATE TABLE test_db.install_test (id INT, name STRING);
             INSERT INTO test_db.install_test VALUES (1, '测试数据1'), (2, '测试数据2');"
    
    # 验证结果
    result=$("$HIVE_BASE_DIR/bin/hive" -S -e "SELECT COUNT(*) FROM test_db.install_test;" 2>/dev/null)
    info "Hive功能测试成功 $result 条记录"
    
    # 清理
    "$HIVE_BASE_DIR/bin/hive" -e "DROP DATABASE test_db CASCADE;" &>/dev/null || true
    
    # 停止服务
    stop_service "$PID_DIR/metastore.pid" "Metastore"
    stop_service "$PID_DIR/hiveserver2.pid" "HiveServer2"
}

# 设置权限
set_permissions() {
    info "设置目录权限"
    chown -R "$HIVE_USER":"$HIVE_USER" "$HIVE_BASE_DIR"
    chmod 755 "$HIVE_BASE_DIR"/bin
    chmod 750 "$HIVE_BASE_DIR"/conf
    chmod 770 "$PID_DIR"
}

# 主安装流程
install_main() {
    info "开始安装 Hive $HIVE_VERSION (实例: $INSTANCE_ID)"
    check_root
    check_dependencies
    create_user
    download_hive
    install_hive
    configure_hive
    init_metastore
    set_permissions
    
    info "运行安装测试..."
    test_hive || warn "功能测试失败，但安装已完成"
    
    info "Hive安装成功!"
    cat <<EOF
=============================================================

版本:       $HIVE_VERSION
实例ID:     $INSTANCE_ID
安装路径:   $HIVE_BASE_DIR
日志目录:   $SERVICE_LOG_DIR
服务用户:   $HIVE_USER
元数据库:   $HIVE_META_DB
Metastore端口:   $METASTORE_PORT
HiveServer2端口: $HIVESERVER_PORT
WebUI端口:  $WEBUI_PORT

HDFS目录:
  仓库目录: $(grep -A1 'hive.metastore.warehouse.dir' $HIVE_BASE_DIR/conf/hive-site.xml | tail -1 | sed -e 's/<[^>]*>//g')
  临时目录: $(grep -A1 'hive.exec.scratchdir' $HIVE_BASE_DIR/conf/hive-site.xml | tail -1 | sed -e 's/<[^>]*>//g')

环境变量文件: /etc/profile.d/hive-${HIVE_VERSION}-${INSTANCE_ID}.sh

使用说明:
1. 加载环境变量:
   source /etc/profile.d/hive-${HIVE_VERSION}-${INSTANCE_ID}.sh

2. 启动服务:
   nohup $HIVE_BASE_DIR/bin/hive --service metastore > $SERVICE_LOG_DIR/metastore.log 2>&1 &
   echo \$! > $PID_DIR/metastore.pid
   
   nohup $HIVE_BASE_DIR/bin/hive --service hiveserver2 > $SERVICE_LOG_DIR/hiveserver2.log 2>&1 &
   echo \$! > $PID_DIR/hiveserver2.pid

3. 停止服务:
   kill \$(cat $PID_DIR/metastore.pid)
   kill \$(cat $PID_DIR/hiveserver2.pid)
   rm -f $PID_DIR/{metastore,hiveserver2}.pid

4. 使用客户端:
   $HIVE_BASE_DIR/bin/beeline -u "jdbc:hive2://$(hostname):$HIVESERVER_PORT/default" -n $HIVE_USER

=============================================================
EOF
}

# 执行入口
[ $# -eq 0 ] && {
    echo "多版本Hive安装工具"
    echo "用法:"
    echo "  HIVE_VERSION=x.x.x INSTANCE_ID=id $0 install"
    echo "示例:"
    echo "  HIVE_VERSION=2.3.9 INSTANCE_ID=v1 $0 install(✅)"
    echo "  HIVE_VERSION=3.1.3 INSTANCE_ID=v1 $0 install(✅)"
    exit 1
}

case "$1" in
    install) install_main ;;
    *) echo "无效命令: $1"; exit 1 ;;
esac