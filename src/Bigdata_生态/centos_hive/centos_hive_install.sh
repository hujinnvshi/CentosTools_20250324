#!/bin/bash
set -euo pipefail

# 配置参数
HIVE_VERSION="2.3.9"
SERVICE_ID="hive_${HIVE_VERSION}_v1"
HIVE_BASE_DIR="/data/${SERVICE_ID}"
MYSQL_HOST="172.16.48.233"
MYSQL_PORT="6005"
MYSQL_USER="admin"
MYSQL_PASS="Secsmart#612"
MYSQL_DRIVER="/tmp/mysql-connector-java-5.1.49.jar"
HIVE_META_DB="metastore_db_239v1"

# 依赖路径配置
JAVA_HOME="/data/java/jdk1.8.0_251"
HADOOP_HOME="/data/hadoop_2.7.7_v1/current"

# 服务参数
HIVE_USER=$SERVICE_ID
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
    [ "$(id -u)" -eq 0 ] || error "请使用root用户运行此脚本"
    info "root权限验证通过"
}

# 检查依赖
check_dependencies() {
    # 检查必要路径
    [ -d "$JAVA_HOME" ] || error "JAVA_HOME路径不存在: $JAVA_HOME"
    [ -d "$HADOOP_HOME" ] || error "Hadoop路径不存在: $HADOOP_HOME"
    [ -f "$MYSQL_DRIVER" ] || error "MySQL驱动不存在: $MYSQL_DRIVER"
    
    # 设置环境变量
    export JAVA_HOME HADOOP_HOME
    PATH="$PATH:$HADOOP_HOME/bin"
    
    # 检查必要命令
    for cmd in wget mysql; do
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
    id -u "$HIVE_USER" &>/dev/null || {
        info "创建系统用户: $HIVE_USER"
        useradd -r -s /bin/false -d "$HIVE_BASE_DIR" "$HIVE_USER"
    }
    
    # 确保Hadoop权限
    hdfs dfs -mkdir -p /user/$HIVE_USER 2>/dev/null || true
    hdfs dfs -chown $HIVE_USER:$HIVE_USER /user/$HIVE_USER 2>/dev/null || true
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
    mkdir -p "$HIVE_BASE_DIR"/{conf,data} "$PID_DIR" "$SERVICE_LOG_DIR"
    
    # 解压并安装驱动
    tar -zxf "apache-hive-$HIVE_VERSION-bin.tar.gz" -C "$HIVE_BASE_DIR" --strip-components=1
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
    
    # 创建hive-site.xml
    cat > "$HIVE_BASE_DIR/conf/hive-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
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
    <name>hive.exec.compress.output</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.exec.compress.intermediate</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.mapred.mode</name>
    <value>nonstrict</value>
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
  <property>
    <name>hive.server2.enable.doAs</name>
    <value>false</value>
  </property>
  <property>
    <name>hive.server2.logging.operation.enabled</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.server2.logging.operation.log.location</name>
    <value>${SERVICE_LOG_DIR}/operation_logs</value>
  </property>
</configuration>
EOF
    
    # 设置权限并添加环境变量
    chmod 640 "$HIVE_BASE_DIR/conf/hive-site.xml"
    cat > /etc/profile.d/hive.sh <<EOF
export HIVE_HOME="$HIVE_BASE_DIR"
export PATH="\$PATH:\$HIVE_HOME/bin"
export HIVE_CONF_DIR="\$HIVE_HOME/conf"
EOF
    source /etc/profile.d/hive.sh
    
    info "Hive配置完成"
}

# 初始化元数据库
init_metastore() {
    info "初始化Hive元数据库"
    
    # 创建HDFS目录
    hdfs dfs -mkdir -p /user/hive/warehouse /tmp/hive
    hdfs dfs -chmod 773 /user/hive/warehouse
    hdfs dfs -chmod 770 /tmp/hive
    
    # 初始化元数据库（带重试）
    for i in {1..3}; do
        schematool -dbType mysql -initSchema && {
            info "Hive元数据库初始化成功"
            return 0
        }
        warn "元数据库初始化失败，尝试 $i/3..."
        sleep $((i*5))
    done
    
    error "元数据库初始化失败"
}

# 测试Hive功能
test_hive() {
    info "启动Hive服务..."
    
    # 启动服务
    nohup hive --service metastore > "$SERVICE_LOG_DIR/metastore.log" 2>&1 &
    metastore_pid=$!
    echo $metastore_pid > "$PID_DIR/metastore.pid"
    
    nohup hive --service hiveserver2 > "$SERVICE_LOG_DIR/hiveserver2.log" 2>&1 &
    hiveserver_pid=$!
    echo $hiveserver_pid > "$PID_DIR/hiveserver2.pid"
    
    info "等待服务启动..."
    sleep 10
    
    # 创建测试环境
    hive -e "CREATE DATABASE IF NOT EXISTS test_db;
             CREATE TABLE test_db.install_test (id INT, name STRING);
             INSERT INTO test_db.install_test VALUES (1, '测试数据1'), (2, '测试数据2');"
    
    # 验证结果
    result=$(hive -S -e "SELECT COUNT(*) FROM test_db.install_test;" 2>/dev/null)
    [ "$result" -eq 2 ] || error "功能测试失败，期望2条记录，实际$result"
    
    info "Hive功能测试成功"
    
    # 清理
    hive -e "DROP DATABASE test_db CASCADE;" &>/dev/null || true
    kill $metastore_pid $hiveserver_pid
    rm -f "$PID_DIR"/{metastore,hiveserver2}.pid
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
    info "开始安装 Hive $HIVE_VERSION"
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
安装路径:   $HIVE_BASE_DIR
日志目录:   $SERVICE_LOG_DIR
服务用户:   $HIVE_USER
Metastore端口:   $METASTORE_PORT
HiveServer2端口: $HIVESERVER_PORT

手动启动服务命令:
1. 启动Metastore服务:
   nohup \$HIVE_HOME/bin/hive --service metastore > "$SERVICE_LOG_DIR/metastore.log" 2>&1 &
   echo \$! > "$PID_DIR/metastore.pid"

2. 启动HiveServer2服务:
   nohup \$HIVE_HOME/bin/hive --service hiveserver2 > "$SERVICE_LOG_DIR/hiveserver2.log" 2>&1 &
   echo \$! > "$PID_DIR/hiveserver2.pid"

3. 停止服务:
   kill \$(cat "$PID_DIR/metastore.pid")
   kill \$(cat "$PID_DIR/hiveserver2.pid")
   rm -f "$PID_DIR"/{metastore,hiveserver2}.pid
=============================================================
EOF
}

# 执行入口
[ $# -eq 0 ] && {
    echo "Hive安装工具"
    echo "用法: $0 install"
    exit 1
}

case "$1" in
    install) install_main ;;
    *) echo "无效命令: $1"; exit 1 ;;
esac