#!/bin/bash
set -euo pipefail

# 新增配置参数
TEZ_VERSION="${TEZ_VERSION:-0.9.2}"  # Tez 版本
TEZ_BASE_DIR="/data/tez_${TEZ_VERSION}_${INSTANCE_ID}"  # Tez 安装目录

# 安装 Tez
install_tez() {
    info "开始安装 Tez $TEZ_VERSION"
    
    # 清理旧安装
    [ -d "$TEZ_BASE_DIR" ] && rm -rf "$TEZ_BASE_DIR"
    mkdir -p "$TEZ_BASE_DIR"
    
    # 下载 Tez
    local tez_tar="apache-tez-${TEZ_VERSION}-bin.tar.gz"
    local tez_url="https://archive.apache.org/dist/tez/${TEZ_VERSION}/${tez_tar}"
    
    # 使用本地缓存或下载
    if [ -f "/tmp/$tez_tar" ]; then
        info "使用本地缓存的Tez安装包"
        cp "/tmp/$tez_tar" .
    else
        info "下载Tez $TEZ_VERSION"
        wget "$tez_url" -O "$tez_tar" || error "下载Tez失败"
        
        # 保存到缓存
        cp "$tez_tar" "/tmp/"
    fi
    
    # 检查文件完整性
    local file_size=$(stat -c %s "$tez_tar")
    if [ "$file_size" -lt 1000000 ]; then
        error "下载的Tez包不完整, 大小: ${file_size}字节"
    fi
    
    info "解压Tez安装包..."
    tar -zxf "$tez_tar" -C "$TEZ_BASE_DIR" --strip-components=1
    
    # 保留安装包用于后续上传
    mv "$tez_tar" "$TEZ_BASE_DIR/share/"
    
    info "Tez安装完成"
}

# 配置 Tez
configure_tez() {
    info "配置Tez环境"
    
    # 创建配置文件目录
    mkdir -p "$TEZ_BASE_DIR/conf"
    
    # 创建tez-site.xml
    cat > "$TEZ_BASE_DIR/conf/tez-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>tez.lib.uris</name>
    <value>\${fs.defaultFS}/tez/tez-${TEZ_VERSION}.tar.gz</value>
  </property>
  <property>
    <name>tez.use.cluster.hadoop-libs</name>
    <value>true</value>
  </property>
  <property>
    <name>tez.am.resource.memory.mb</name>
    <value>1024</value>
  </property>
  <property>
    <name>tez.task.resource.memory.mb</name>
    <value>1024</value>
  </property>
  <property>
    <name>tez.runtime.io.sort.mb</name>
    <value>256</value>
  </property>
  <property>
    <name>tez.runtime.compress</name>
    <value>true</value>
  </property>
  <property>
    <name>tez.runtime.compress.codec</name>
    <value>org.apache.hadoop.io.compress.SnappyCodec</value>
  </property>
</configuration>
EOF
    
    # 上传Tez到HDFS
    info "上传Tez到HDFS..."
    hdfs dfs -mkdir -p /tez || warn "无法创建/tez目录，可能已存在"
    hdfs dfs -put -f "$TEZ_BASE_DIR/share/apache-tez-${TEZ_VERSION}-bin.tar.gz" "/tez/tez-${TEZ_VERSION}.tar.gz" \
        || error "上传Tez到HDFS失败"
    
    info "Tez配置完成"
}

# 配置Hive使用Tez引擎
configure_hive_for_tez() {
    info "配置Hive使用Tez执行引擎"
    
    # 备份原始配置文件
    cp "$HIVE_BASE_DIR/conf/hive-site.xml" "$HIVE_BASE_DIR/conf/hive-site.xml.bak"
    
    # 检查并安装xmlstarlet
    if ! command -v xmlstarlet &>/dev/null; then
        warn "未找到xmlstarlet，尝试安装..."
        if command -v yum &>/dev/null; then
            yum install -y xmlstarlet || error "安装xmlstarlet失败"
        elif command -v apt-get &>/dev/null; then
            apt-get install -y xmlstarlet || error "安装xmlstarlet失败"
        else
            error "无法自动安装xmlstarlet，请手动安装"
        fi
    fi
    
    # 添加Tez配置
    xmlstarlet ed -L \
        --subnode "/configuration" -t elem -n "property" -v "" \
        --subnode "//property[last()]" -t elem -n "name" -v "hive.execution.engine" \
        --subnode "//property[last()]" -t elem -n "value" -v "tez" \
        --subnode "/configuration" -t elem -n "property" -v "" \
        --subnode "//property[last()]" -t elem -n "name" -v "tez.lib.uris" \
        --subnode "//property[last()]" -t elem -n "value" -v "\${fs.defaultFS}/tez/tez-${TEZ_VERSION}.tar.gz" \
        --subnode "/configuration" -t elem -n "property" -v "" \
        --subnode "//property[last()]" -t elem -n "name" -v "hive.tez.container.size" \
        --subnode "//property[last()]" -t elem -n "value" -v "1024" \
        "$HIVE_BASE_DIR/conf/hive-site.xml" || error "修改hive-site.xml失败"
    
    # 更新环境变量
    cat >> "/etc/profile.d/hive-${HIVE_VERSION}-${INSTANCE_ID}.sh" <<EOF

# Tez配置
export TEZ_HOME="$TEZ_BASE_DIR"
export TEZ_CONF_DIR="$TEZ_BASE_DIR/conf"
export HADOOP_CLASSPATH="\$HADOOP_CLASSPATH:\$TEZ_HOME/*:\$TEZ_HOME/lib/*"
EOF
    
    source "/etc/profile.d/hive-${HIVE_VERSION}-${INSTANCE_ID}.sh"
    
    info "Hive已配置为使用Tez执行引擎"
}

# 等待服务启动
wait_for_service() {
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

# 验证Tez功能
test_tez() {
    info "验证Tez功能..."
    
    # 确保日志目录存在
    mkdir -p "$SERVICE_LOG_DIR" "$PID_DIR"
    
    # 启动服务
    info "启动Metastore服务..."
    nohup "$HIVE_BASE_DIR/bin/hive" --service metastore > "$SERVICE_LOG_DIR/metastore.log" 2>&1 &
    metastore_pid=$!
    echo $metastore_pid > "$PID_DIR/metastore.pid"
    
    info "启动HiveServer2服务..."
    nohup "$HIVE_BASE_DIR/bin/hive" --service hiveserver2 > "$SERVICE_LOG_DIR/hiveserver2.log" 2>&1 &
    hiveserver_pid=$!
    echo $hiveserver_pid > "$PID_DIR/hiveserver2.pid"
    
    # 等待服务启动
    wait_for_service $METASTORE_PORT "Metastore"
    wait_for_service $HIVESERVER_PORT "HiveServer2"
    
    # 创建测试环境
    info "创建测试数据库和表..."
    "$HIVE_BASE_DIR/bin/hive" -e "CREATE DATABASE IF NOT EXISTS test_db;
             CREATE TABLE test_db.install_test (id INT, name STRING);
             INSERT INTO test_db.install_test VALUES (1, '测试数据1'), (2, '测试数据2');" \
             || warn "创建测试数据失败"
    
    # 运行Tez测试查询
    info "执行Tez测试查询..."
    local result=$("$HIVE_BASE_DIR/bin/beeline" -u "jdbc:hive2://localhost:$HIVESERVER_PORT" \
        -n "$HIVE_USER" \
        --silent=true \
        --outputformat=tsv2 \
        -e "EXPLAIN SELECT COUNT(*) FROM test_db.install_test;" 2>/dev/null)
    
    # 验证结果
    if echo "$result" | grep -q "Tez"; then
        info "Tez功能验证成功: 查询使用Tez执行引擎"
    else
        warn "Tez功能验证失败: 查询未使用Tez执行引擎"
        echo "$result"
    fi
    
    # 清理测试数据
    "$HIVE_BASE_DIR/bin/hive" -e "DROP DATABASE test_db CASCADE;" &>/dev/null || true
    
    # 停止服务
    info "停止服务..."
    kill $metastore_pid $hiveserver_pid
    wait $metastore_pid $hiveserver_pid 2>/dev/null || true
    rm -f "$PID_DIR"/{metastore,hiveserver2}.pid
}

# 主安装流程（添加Tez支持）
install_main() {
    info "开始安装 Hive $HIVE_VERSION (实例: $INSTANCE_ID)"
    check_root
    check_dependencies
    create_user
    download_hive
    install_hive
    
    # 安装和配置Tez
    install_tez
    configure_tez
    
    configure_hive
    init_metastore
    set_permissions
    
    # 配置Hive使用Tez
    configure_hive_for_tez
    
    info "运行安装测试..."
    test_hive || warn "基础功能测试失败，但安装已完成"
    
    info "运行Tez测试..."
    test_tez || warn "Tez功能测试失败"
    
    info "Hive安装成功! (使用Tez引擎)"
    cat <<EOF
=============================================================

版本:       Hive $HIVE_VERSION + Tez $TEZ_VERSION
实例ID:     $INSTANCE_ID
安装路径:   $HIVE_BASE_DIR
Tez路径:    $TEZ_BASE_DIR
日志目录:   $SERVICE_LOG_DIR
服务用户:   $HIVE_USER
元数据库:   $HIVE_META_DB
Metastore端口:   $METASTORE_PORT
HiveServer2端口: $HIVESERVER_PORT

Tez配置:
  HDFS路径: /tez/tez-${TEZ_VERSION}.tar.gz
  内存配置: 1024MB

使用说明:
1. 加载环境变量:
   source /etc/profile.d/hive-${HIVE_VERSION}-${INSTANCE_ID}.sh

2. 启动服务:
   nohup \$HIVE_HOME/bin/hive --service metastore > \$SERVICE_LOG_DIR/metastore.log 2>&1 &
   echo \$! > \$PID_DIR/metastore.pid
   
   nohup \$HIVE_HOME/bin/hive --service hiveserver2 > \$SERVICE_LOG_DIR/hiveserver2.log 2>&1 &
   echo \$! > \$PID_DIR/hiveserver2.pid

3. 使用Tez引擎查询:
   beeline -u "jdbc:hive2://localhost:$HIVESERVER_PORT" -e "SET hive.execution.engine=tez; SELECT ..."

=============================================================
EOF
}

# 执行入口
[ $# -eq 0 ] && {
    echo "Hive + Tez 安装工具"
    echo "用法:"
    echo "  HIVE_VERSION=x.x.x TEZ_VERSION=y.y.y INSTANCE_ID=id $0 install"
    echo "示例:"
    echo "  HIVE_VERSION=2.3.9 TEZ_VERSION=0.9.2 INSTANCE_ID=v1 $0 install"
    echo "  HIVE_VERSION=3.1.3 TEZ_VERSION=0.10.1 INSTANCE_ID=v2 $0 install"
    exit 1
}

case "$1" in
    install) install_main ;;
    *) echo "无效命令: $1"; exit 1 ;;
esac