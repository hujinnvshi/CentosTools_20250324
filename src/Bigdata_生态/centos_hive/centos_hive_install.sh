#!/bin/bash
set -euo pipefail

# 配置参数
HIVE_VERSION="2.3.9"
Service_ID="hive_${HIVE_VERSION}_v1"
HIVE_BASE_DIR="/data/${Service_ID}"
MYSQL_HOST="192.168.0.105"
MYSQL_PORT="6005"
MYSQL_USER="admin"
MYSQL_PASS="Secsmart#612"
MYSQL_DRIVER="/tmp/mysql-connector-java-5.1.49.jar"

# 依赖路径配置
JAVA_HOME="/data/java/jdk1.8.0_251"
HADOOP_HOME="/data/hadoop_2.7.7_v1/current"

# 服务管理参数
HIVE_USER=$Service_ID
SERVICE_LOG_DIR="$HIVE_BASE_DIR/logs"
METASTORE_PORT=9083
HIVESERVER_PORT=10000
PID_DIR="$HIVE_BASE_DIR/pids"
HEALTH_CHECK_TIMEOUT=120  # 健康检查超时时间（秒）
RETRY_INTERVAL=5          # 重试间隔（秒）

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 状态函数
error() { echo -e "${RED}[ERROR] $* ${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN] $* ${NC}" >&2; }
info() { echo -e "${GREEN}[INFO] $* ${NC}"; }

# 检查服务状态
service_status() {
    local pid_file="$PID_DIR/hive-$1.pid"
    if [ -f "$pid_file" ] && kill -0 $(cat "$pid_file") 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 服务健康检查
check_service_health() {
    local service=$1
    local port=$2
    local start_time=$(date +%s)
    
    info "等待 $service 服务启动 (端口: $port)..."
    
    while true; do
        # 端口检查
        if nc -z localhost $port &>/dev/null; then
            info "$service 服务启动成功"
            return 0
        fi
        
        # PID检查
        if ! service_status $service; then
            error "$service 服务进程异常终止"
        fi
        
        # 超时检查
        local current_time=$(date +%s)
        if (( current_time - start_time > HEALTH_CHECK_TIMEOUT )); then
            error "$service 服务启动超时（${HEALTH_CHECK_TIMEOUT}秒）"
        fi
        
        sleep $RETRY_INTERVAL
    done
}

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
    # if ! hdfs dfsadmin -report &>/dev/null; then
    #     error "Hadoop未运行，请先启动Hadoop集群"
    # fi
    
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
    echo "下载Hive: wget $hive_url -O /tmp/$hive_tar"

    # 清理旧安装包
    [ -f "$hive_tar" ] && rm -f "$hive_tar"
    
    info "开始下载Hive $HIVE_VERSION"
    cp /tmp/"$hive_tar" "$hive_tar"
    #if ! wget "$hive_url" -O "$hive_tar"; then
    #    error "下载Hive失败, 请检查网络连接或镜像可用性"
    #fi
    
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
    <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/hive_metastore?createDatabaseIfNotExist=true&amp;useSSL=false&amp;characterEncoding=UTF-8</value>
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

# 服务管理函数
service_control() {
    local service=$1
    local action=$2
    local pid_file="$PID_DIR/hive-${service}.pid"
    local log_file="$SERVICE_LOG_DIR/${service}.log"
    local port_var="${service^^}_PORT"
    local port=${!port_var:-0}
    
    case "$action" in
        start)
            # 检查是否已在运行
            if service_status $service; then
                info "Hive ${service}服务已在运行 (PID: $(cat $pid_file))"
                return 0
            fi
            
            info "启动Hive ${service}服务..."
            mkdir -p $(dirname "$log_file")
            nohup $HIVE_HOME/bin/hive --service $service > "$log_file" 2>&1 &
            local pid=$!
            echo $pid > "$pid_file"
            
            # 短暂的初始等待
            sleep 2
            
            # 等待服务启动
            start_time=$(date +%s)
            while true; do
                # 检查进程状态
                if ! kill -0 $pid 2>/dev/null; then
                    error "Hive ${service}服务启动失败, 检查日志: $log_file"
                fi
                
                # 端口健康检查
                if [ $port -gt 0 ] && nc -z localhost $port 2>/dev/null; then
                    info "Hive ${service}服务启动成功 (PID: $pid, Port: $port)"
                    return 0
                fi
                
                # 检查超时
                if (( $(date +%s) - start_time > HEALTH_CHECK_TIMEOUT )); then
                    warn "Hive ${service}服务启动超时，仍在运行但端口未就绪 (PID: $pid)"
                    return 1
                fi
                
                sleep 1
            done
            ;;
        stop)
            if [ -f "$pid_file" ]; then
                local pid=$(cat "$pid_file")
                if kill -0 $pid 2>/dev/null; then
                    info "停止Hive ${service}服务 (PID: $pid)"
                    kill $pid
                    
                    # 等待进程结束
                    local max_wait=15
                    local wait_time=0
                    while kill -0 $pid 2>/dev/null && [ $wait_time -lt $max_wait ]; do
                        sleep 1
                        wait_time=$((wait_time+1))
                    done
                    
                    if kill -0 $pid 2>/dev/null; then
                        warn "服务未正常退出，强制终止"
                        kill -9 $pid
                    fi
                fi
                rm -f "$pid_file"
            else
                warn "未找到PID文件: $pid_file"
            fi
            ;;
        status)
            if [ -f "$pid_file" ]; then
                local pid=$(cat "$pid_file")
                if kill -0 $pid 2>/dev/null; then
                    info "Hive ${service}服务正在运行 (PID: $pid)"
                    return 0
                else
                    warn "Hive ${service}服务进程不存在或已停止"
                    return 2
                fi
            else
                warn "Hive ${service}服务未运行"
                return 3
            fi
            ;;
        restart)
            service_control $service stop
            sleep 2
            service_control $service start
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
    service_control hiveserver2 start
    
    info "运行基本功能测试..."
    
    # 准备测试数据
    local test_data="/tmp/hive_test_data.txt"
    echo -e "1\ttest1\n2\ttest2" > "$test_data"
    hdfs dfs -mkdir -p /tmp/hive_test
    hdfs dfs -put "$test_data" /tmp/hive_test/
    
    # 创建测试表
    hive -e "DROP TABLE IF EXISTS hive_install_test;" 
    hive -e "CREATE TABLE hive_install_test (id INT, name STRING) ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t';"
    
    # 加载数据
    hive -e "LOAD DATA INPATH '/tmp/hive_test/hive_test_data.txt' INTO TABLE hive_install_test;"
    
    # 查询验证
    local result_count=$(hive -S -e "SELECT COUNT(*) FROM hive_install_test;" 2>/dev/null | grep -v 'SLF4J')
    local result_name=$(hive -S -e "SELECT name FROM hive_install_test WHERE id = 1;" 2>/dev/null | grep -v 'SLF4J' | tr -d '[:space:]')
    
    # 清理测试数据
    rm -f "$test_data"
    hdfs dfs -rm -r -f /tmp/hive_test
    
    # 验证结果
    if [[ "$result_count" -eq 2 && "$result_name" == "test1" ]]; then
        info "Hive功能测试成功"
        info "  - 查询结果: $result_count 条记录"
        info "  - 名称验证: test1 == $result_name"
        return 0
    else
        error "Hive功能测试失败"
        info "  - 查询结果: $result_count (应为 2)"
        info "  - 名称验证: $result_name (应为 test1)"
        return 1
    fi
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

# 创建服务管理脚本
create_service_script() {
    local service_script="$HIVE_BASE_DIR/bin/hive-service.sh"
    
    cat << 'EOF' > "$service_script"
#!/bin/bash
set -euo pipefail

# 服务管理脚本
SERVICE=$1
ACTION=$2

# 加载配置
HIV_HOME=$(dirname "$(readlink -f "$0")")/..
[ -f "$HIV_HOME/conf/hive-env.sh" ] && source "$HIV_HOME/conf/hive-env.sh"
[ -z "$HIVE_HOME" ] && error "HIVE_HOME 未定义"

# 定义函数
service_control() {
    local service=$1
    local action=$2
    local pid_file="$PID_DIR/hive-${service}.pid"
    
    case "$action" in
        start|stop|restart|status)
            "$HIVE_HOME/bin/hive" --service $service --${action}Service
            ;;
        *)
            echo "未知操作: $action"
            exit 1
            ;;
    esac
}

# 执行服务管理
case "$SERVICE" in
    metastore|hiveserver2)
        service_control $SERVICE $ACTION
        ;;
    *)
        echo "用法: $0 [metastore|hiveserver2] [start|stop|restart|status]"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$service_script"
    chown "$HIVE_USER":"$HIVE_USER" "$service_script"
    
    info "创建服务管理脚本: $service_script"
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
    
    create_service_script
    
    info "Hive安装成功完成!"
    echo "============================================================="
    info "安装路径:   $HIVE_BASE_DIR"
    info "日志目录:   $SERVICE_LOG_DIR"
    info "数据目录:   $HIVE_BASE_DIR/data"
    info "服务用户:   $HIVE_USER"
    info "Metastore:   localhost:$METASTORE_PORT"
    info "HiveServer2: jdbc:hive2://localhost:$HIVESERVER_PORT"
    echo ""
    info "管理服务:   $HIVE_BASE_DIR/bin/hive-service.sh [服务] [操作]"
    info "示例:       hive-service.sh metastore start"
    echo "============================================================="
}

# 服务管理入口
service_main() {
    # 确保环境变量已加载
    [ -f "/etc/profile.d/hive.sh" ] && source "/etc/profile.d/hive.sh"
    [ -z "$HIVE_HOME" ] && error "HIVE_HOME 未定义"

    case "$1" in
        start)
            service_control metastore start
            service_control hiveserver2 start
            ;;
        stop)
            service_control hiveserver2 stop
            service_control metastore stop
            ;;
        restart)
            service_control hiveserver2 stop
            service_control metastore stop
            sleep 3
            service_control metastore start
            service_control hiveserver2 start
            ;;
        status)
            service_control metastore status
            service_control hiveserver2 status
            ;;
        test)
            test_hive
            ;;
        *)
            echo "用法: $0 [install | start | stop | restart | status | test]"
            exit 1
            ;;
    esac
}

# 执行入口
if [ $# -eq 0 ]; then
    echo "Hive管理工具"
    echo "用法: $0 [install | service_command]"
    echo "命令:"
    echo "  install     - 全新安装 Hive"
    echo "  start       - 启动所有服务"
    echo "  stop        - 停止所有服务"
    echo "  restart     - 重启所有服务"
    echo "  status      - 检查服务状态"
    echo "  test        - 运行功能测试"
    exit 1
fi

case "$1" in
    install)
        install_main
        ;;
    *)
        service_main "$1"
        ;;
esac