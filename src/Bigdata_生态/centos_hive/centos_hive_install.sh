#!/bin/bash
set -euo pipefail

# 配置参数
HIVE_VERSION="2.3.9"
HIVE_BASE_DIR="/data/hive_2.3.9_v1"
MYSQL_HOST="192.168.0.105"
MYSQL_PORT="6005"
MYSQL_USER="admin"
MYSQL_PASS="Secsmart#612"
MYSQL_DRIVER="/tmp/mysql-connector-java-5.1.49.jar"

# 依赖路径配置
JAVA_HOME="/data/java/jdk1.8.0_251"
HADOOP_HOME="/data/hadoop_2.7.7_v1/current"

# 服务管理参数
HIVE_USER="hiveadmin"
SERVICE_LOG_DIR="$HIVE_BASE_DIR/logs"
METASTORE_PORT=9083
HIVESERVER_PORT=10000
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

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用root用户运行此脚本"
    fi
    info "root权限验证通过"
}

# 检查依赖
check_dependencies() {
    # Java检查
    [ -d "$JAVA_HOME" ] || error "JAVA_HOME路径不存在: $JAVA_HOME"
    export JAVA_HOME
    
    # Hadoop检查
    [ -d "$HADOOP_HOME" ] || error "Hadoop路径不存在: $HADOOP_HOME"
    export HADOOP_HOME
    PATH="$PATH:$HADOOP_HOME/bin"
    
    # 检查Hadoop是否运行
    if ! hdfs dfsadmin -report &>/dev/null; then
        error "Hadoop未运行，请先启动Hadoop集群"
    fi
    
    # MySQL驱动检查
    [ -f "$MYSQL_DRIVER" ] || error "MySQL驱动不存在: $MYSQL_DRIVER"
    
    # 必要命令检查
    for cmd in wget mysql; do
        command -v $cmd &>/dev/null || {
            warn "未找到命令: $cmd, 尝试安装..."
            if command -v yum &>/dev/null; then
                yum install -y $cmd
            elif command -v apt-get &>/dev/null; then
                apt-get install -y $cmd
            else
                error "无法自动安装$cmd, 请手动安装"
            fi
        }
    done
    
    # MySQL连接检查
    if ! mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT 1;" &>/dev/null; then
        error "无法连接到MySQL数据库, 请检查连接参数"
    fi
    
    info "所有依赖检查通过"
}

# 创建系统用户
create_user() {
    if ! id -u "$HIVE_USER" &>/dev/null; then
        info "创建系统用户: $HIVE_USER"
        useradd -r -s /bin/false -d "$HIVE_BASE_DIR" "$HIVE_USER"
    fi
}

# 下载Hive
download_hive() {
    local hive_tar="apache-hive-$HIVE_VERSION-bin.tar.gz"
    local hive_url="https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/$hive_tar"
    
    info "开始下载Hive $HIVE_VERSION"
    [ -f "$hive_tar" ] && return
    
    if ! wget -q --show-progress "$hive_url" -O "$hive_tar"; then
        error "下载Hive失败, 请检查网络连接"
    fi
    
    # 基础完整性检查
    local filesize=$(stat -c %s "$hive_tar")
    if [ "$filesize" -lt 1000000 ]; then
        error "下载的Hive包不完整, 大小: ${filesize}字节"
    fi
}

# 安装Hive
install_hive() {
    info "安装Hive到: $HIVE_BASE_DIR"
    
    # 创建目录结构
    mkdir -p "$HIVE_BASE_DIR" \
             "$HIVE_BASE_DIR/conf" \
             "$HIVE_BASE_DIR/data" \
             "$PID_DIR" \
             "$SERVICE_LOG_DIR"
    
    # 解压安装包
    tar -zxf "apache-hive-$HIVE_VERSION-bin.tar.gz" -C "$HIVE_BASE_DIR" --strip-components=1
    
    # 安装MySQL驱动
    cp "$MYSQL_DRIVER" "$HIVE_BASE_DIR/lib/"
    chmod 640 "$HIVE_BASE_DIR/lib/mysql-connector-java"*
    
    info "Hive安装完成"
}

# 配置Hive
configure_hive() {
    info "配置Hive环境"
    
    # 创建配置文件
    cat << EOF > "$HIVE_BASE_DIR/conf/hive-env.sh"
export JAVA_HOME="$JAVA_HOME"
export HADOOP_HOME="$HADOOP_HOME"
export HIVE_HOME="$HIVE_BASE_DIR"
export HIVE_CONF_DIR="$HIVE_BASE_DIR/conf"
export HIVE_LOG_DIR="$SERVICE_LOG_DIR"
EOF
    
    # hive-site.xml配置
    cat << EOF > "$HIVE_BASE_DIR/conf/hive-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/hive_metastore?createDatabaseIfNotExist=true&amp;useSSL=false</value>
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
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>/user/hive/warehouse</value>
  </property>
  <property>
    <name>hive.exec.scratchdir</name>
    <value>/tmp/hive</value>
  </property>
  <property>
    <name>hive.querylog.location</name>
    <value>${SERVICE_LOG_DIR}</value>
  </property>
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>false</value>
  </property>
  <property>
    <name>datanucleus.schema.autoCreateAll</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.server2.thrift.port</name>
    <value>${HIVESERVER_PORT}</value>
  </property>
  <property>
    <name>hive.metastore.port</name>
    <value>${METASTORE_PORT}</value>
  </property>
</configuration>
EOF
    
    # 设置配置文件权限
    chmod 600 "$HIVE_BASE_DIR/conf/hive-site.xml"
    
    # 添加环境变量
    cat << EOF > /etc/profile.d/hive.sh
export HIVE_HOME="$HIVE_BASE_DIR"
export PATH="\$PATH:\$HIVE_HOME/bin"
export HIVE_CONF_DIR="\$HIVE_HOME/conf"
EOF
    source /etc/profile.d/hive.sh
    
    info "Hive配置完成"
}

# 初始化Hive数据库
init_metastore() {
    info "初始化Hive元数据库"
    
    # 创建HDFS目录
    hdfs dfs -mkdir -p /user/hive/warehouse /tmp/hive
    hdfs dfs -chmod 773 /user/hive/warehouse
    hdfs dfs -chmod 777 /tmp/hive
    
    # 初始化元数据库
    if ! schematool -dbType mysql -initSchema; then
        error "元数据库初始化失败, 请检查日志: $SERVICE_LOG_DIR/metastore.log"
    fi
    
    info "Hive元数据库初始化成功"
}

# 服务管理函数
service_control() {
    local service=$1
    local action=$2
    local pid_file="$PID_DIR/hive-${service}.pid"
    local log_file="$SERVICE_LOG_DIR/${service}.log"
    
    case "$action" in
        start)
            info "启动Hive ${service}服务..."
            nohup $HIVE_HOME/bin/hive --service $service > "$log_file" 2>&1 &
            echo $! > "$pid_file"
            sleep 3
            if [ ! -s "$pid_file" ] || ! kill -0 $(cat "$pid_file") 2>/dev/null; then
                error "无法启动$service服务, 检查日志: $log_file"
            fi
            ;;
        stop)
            if [ -f "$pid_file" ]; then
                local pid=$(cat "$pid_file")
                if kill -0 $pid 2>/dev/null; then
                    info "停止Hive ${service}服务 (PID: $pid)"
                    kill $pid
                    rm -f "$pid_file"
                else
                    warn "进程已停止, 清理PID文件: $pid_file"
                    rm -f "$pid_file"
                fi
            else
                warn "未找到PID文件: $pid_file"
            fi
            ;;
        status)
            if [ -f "$pid_file" ] && kill -0 $(cat "$pid_file") 2>/dev/null; then
                info "Hive ${service}服务正在运行 (PID: $(cat $pid_file))"
                return 0
            else
                warn "Hive ${service}服务未运行"
                return 1
            fi
            ;;
        *)
            error "无效操作: $action"
            ;;
    esac
}

# 测试Hive功能
test_hive() {
    info "启动Hive服务..."
    service_control metastore start
    service_control hiveserver start
    
    info "等待服务启动..."
    sleep 10
    
    #