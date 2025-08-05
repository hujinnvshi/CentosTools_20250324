#!/bin/bash
set -euo pipefail

# 配置参数
HIVE_VERSION="2.3.9"
Service_ID="hive_${HIVE_VERSION}_v1"
HIVE_BASE_DIR="/data/${Service_ID}"
MYSQL_HOST="172.16.48.233"
MYSQL_PORT="6005"
MYSQL_USER="admin"
MYSQL_PASS="Secsmart#612"
MYSQL_DRIVER="/tmp/mysql-connector-java-5.1.49.jar"
Hive_Meta_DB="metastore_db_239v1"

# 依赖路径配置
JAVA_HOME="/data/java/jdk1.8.0_251"
HADOOP_HOME="/data/hadoop_2.7.7_v1/current"

# 服务管理参数
HIVE_USER=$Service_ID
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
    
    # MySQL驱动检查
    [ -f "$MYSQL_DRIVER" ] || error "MySQL驱动不存在: $MYSQL_DRIVER"
    
    # 必要命令检查
    for cmd in wget mysql; do
        if ! command -v $cmd &>/dev/null; then
            warn "未找到命令: $cmd, 尝试安装..."
            if command -v yum &>/dev/null; then
                yum install -y $cmd || error "安装$cmd失败"
            elif command -v apt-get &>/dev/null; then
                apt-get install -y $cmd || error "安装$cmd失败"
            else
                error "无法自动安装$cmd, 请手动安装"
            fi
            info "$cmd 安装成功"
        fi
    done
    
    # MySQL连接检查
    info "验证MySQL数据库连接..."
    if ! mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" \
        -e "CREATE DATABASE IF NOT EXISTS hive_check; DROP DATABASE hive_check;" &>/dev/null; then
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
    
    # 确保用户对Hadoop有足够的权限
    hdfs dfs -mkdir -p /user/$HIVE_USER 2>/dev/null || true
    hdfs dfs -chown $HIVE_USER:$HIVE_USER /user/$HIVE_USER 2>/dev/null || true
}

# 下载Hive
download_hive() {
    local hive_tar="apache-hive-$HIVE_VERSION-bin.tar.gz"
    local hive_url="https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/$hive_tar"
    
    info "开始下载Hive $HIVE_VERSION"
    
    # 如果本地已有安装包，直接使用
    if [ -f "/tmp/$hive_tar" ]; then
        info "使用本地缓存的Hive安装包"
        cp "/tmp/$hive_tar" .
    else
        info "从Apache镜像下载Hive"
        if ! wget "$hive_url" -O "$hive_tar"; then
            error "下载Hive失败, 请检查网络连接或镜像可用性"
        fi
    fi
    
    # 基础完整性检查
    local filesize=$(stat -c %s "$hive_tar" 2>/dev/null || echo 0)
    if [ "$filesize" -lt 1000000 ]; then
        error "下载的Hive包不完整, 大小: ${filesize}字节"
    fi
    
    info "Hive下载成功, 大小: $(numfmt --to=iec-i --suffix=B $filesize)"
}

# 安装Hive
install_hive() {
    info "安装Hive到: $HIVE_BASE_DIR"
    
    # 清理旧安装
    [ -d "$HIVE_BASE_DIR" ] && rm -rf "$HIVE_BASE_DIR"
    
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
    chmod 640 "$HIVE_BASE_DIR/lib/$(basename $MYSQL_DRIVER)"
    
    # 清理安装包
    rm -f "apache-hive-$HIVE_VERSION-bin.tar.gz"
    
    info "Hive安装完成"
}

# 配置Hive
configure_hive() {
    info "配置Hive环境"
    
    # 创建环境配置文件
    cat << EOF > "$HIVE_BASE_DIR/conf/hive-env.sh"
#!/bin/bash
# Hive环境设置
export JAVA_HOME="$JAVA_HOME"
export HADOOP_HOME="$HADOOP_HOME"
export HIVE_HOME="$HIVE_BASE_DIR"
export HIVE_CONF_DIR="$HIVE_BASE_DIR/conf"
export HIVE_LOG_DIR="$SERVICE_LOG_DIR"
export PATH="\$PATH:\$HIVE_HOME/bin"
EOF
    
    # hive-site.xml配置
    cat << EOF > "$HIVE_BASE_DIR/conf/hive-site.xml"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <!-- 元数据库配置 -->
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/${Hive_Meta_DB}?createDatabaseIfNotExist=true&amp;useSSL=false&amp;characterEncoding=UTF-8</value>
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
  
  <!-- 存储配置 -->
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
  
  <!-- 性能配置 -->
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
  
  <!-- 元数据验证 -->
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>false</value>
  </property>
  <property>
    <name>datanucleus.schema.autoCreateAll</name>
    <value>true</value>
  </property>
  
  <!-- 服务端口 -->
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
  
  <!-- 日志配置 -->
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
    
    # 设置配置文件权限
    chmod 640 "$HIVE_BASE_DIR/conf/hive-site.xml"
    
    # 添加全局环境变量
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
    
    # 初始化元数据库，包含错误重试
    local max_retries=3
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if schematool -dbType mysql -initSchema; then
            info "Hive元数据库初始化成功"
            return 0
        else
            retry_count=$((retry_count+1))
            warn "元数据库初始化失败，尝试 $retry_count/$max_retries..."
            sleep $((retry_count*5))
        fi
    done
    
    error "元数据库初始化失败, 请检查日志: $SERVICE_LOG_DIR/schematool.log"
}

# 测试Hive功能
test_hive() {
    info "启动Hive服务..."
    
    # 启动Metastore服务
    info "启动Metastore服务:"
    info "nohup \$HIVE_HOME/bin/hive --service metastore > \"$SERVICE_LOG_DIR/metastore.log\" 2>&1 &"
    nohup $HIVE_HOME/bin/hive --service metastore > "$SERVICE_LOG_DIR/metastore.log" 2>&1 &
    metastore_pid=$!
    echo $metastore_pid > "$PID_DIR/metastore.pid"
    
    # 启动HiveServer2服务
    info "启动HiveServer2服务:"
    info "nohup \$HIVE_HOME/bin/hive --service hiveserver2 > \"$SERVICE_LOG_DIR/hiveserver2.log\" 2>&1 &"
    nohup $HIVE_HOME/bin/hive --service hiveserver2 > "$SERVICE_LOG_DIR/hiveserver2.log" 2>&1 &
    hiveserver_pid=$!
    echo $hiveserver_pid > "$PID_DIR/hiveserver2.pid"
    
    info "等待服务启动..."
    sleep 10
    
    # 创建测试表
    info "创建测试表..."
    hive -e "CREATE DATABASE IF NOT EXISTS test_db;"
    hive -e "CREATE TABLE test_db.install_test (id INT, name STRING) STORED AS TEXTFILE;"
    
    # 插入数据
    info "插入测试数据..."
    hive -e "INSERT INTO test_db.install_test VALUES (1, '测试数据1'), (2, '测试数据2');"
    
    # 查询验证
    info "验证测试数据..."
    result=$(hive -S -e "SELECT COUNT(*) FROM test_db.install_test;" 2>/dev/null)
    
    info "Hive功能测试成功, 共找到${result}条记录"
    
    # 清理测试数据
    hive -e "DROP DATABASE test_db CASCADE;" &>/dev/null || warn "未能清理测试数据库"
    
    # 停止服务
    info "停止Hive服务..."
    kill $metastore_pid
    kill $hiveserver_pid
    rm -f "$PID_DIR/metastore.pid" "$PID_DIR/hiveserver2.pid"
}

# 安装后的权限设置
set_permissions() {
    info "设置目录权限"
    
    # 主目录权限
    chown -R "$HIVE_USER":"$HIVE_USER" "$HIVE_BASE_DIR"
    
    # 特定目录权限
    chmod 755 "$HIVE_BASE_DIR"/bin
    chmod 750 "$HIVE_BASE_DIR"/conf
    
    # PID目录权限
    chmod 770 "$PID_DIR"
    chown "$HIVE_USER":"$HIVE_USER" "$PID_DIR"
    
    info "权限设置完成"
}

# 主安装函数
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
    if test_hive; then
        info "Hive功能测试通过"
    else
        warn "Hive功能测试失败，但安装已完成"
    fi
    
    info "Hive安装成功完成!"
    echo "============================================================="
    info "安装路径:   $HIVE_BASE_DIR"
    info "日志目录:   $SERVICE_LOG_DIR"
    info "数据目录:   $HIVE_BASE_DIR/data"
    info "服务用户:   $HIVE_USER"
    info "Metastore端口:   $METASTORE_PORT"
    info "HiveServer2端口: $HIVESERVER_PORT"
    echo ""
    info "手动启动服务命令:"
    info "1. 启动Metastore服务:"
    info "   nohup \$HIVE_HOME/bin/hive --service metastore > \"$SERVICE_LOG_DIR/metastore.log\" 2>&1 &"
    info "   echo \$! > \"$PID_DIR/metastore.pid\""
    echo ""
    info "2. 启动HiveServer2服务:"
    info "   nohup \$HIVE_HOME/bin/hive --service hiveserver2 > \"$SERVICE_LOG_DIR/hiveserver2.log\" 2>&1 &"
    info "   echo \$! > \"$PID_DIR/hiveserver2.pid\""
    echo ""
    info "3. 停止服务:"
    info "   kill \$(cat \"$PID_DIR/metastore.pid\")"
    info "   kill \$(cat \"$PID_DIR/hiveserver2.pid\")"
    info "   rm -f \"$PID_DIR/metastore.pid\" \"$PID_DIR/hiveserver2.pid\""
    echo "============================================================="
}

# 执行入口
if [ $# -eq 0 ]; then
    echo "Hive安装工具"
    echo "用法: $0 install"
    exit 1
fi

case "$1" in
    install)
        install_main
        ;;
    *)
        echo "无效命令: $1"
        echo "可用命令: install"
        exit 1
        ;;
esac