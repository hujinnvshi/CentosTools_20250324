#!/bin/bash
# Hadoop 2.x 单机模式一键安装脚本 (优化版)
# 支持版本切换功能
# 安装路径: /data/hadoop_2.x
# JDK路径: /data/java/jdk1.8.0_251

set -euo pipefail

# 配置参数
HADOOP_VERSION="2.7.7"
Service_ID="hadoop_${HADOOP_VERSION}_v1"
HADOOP_BASE_DIR="/data/${Service_ID}"
HADOOP_DATA_DIR="$HADOOP_BASE_DIR/data"
HADOOP_LOG_DIR="$HADOOP_BASE_DIR/logs"
JDK_HOME="/data/java/jdk1.8.0_251"
HADOOP_USER=${Service_ID}
HADOOP_GROUP=${Service_ID}

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 安装依赖
install_dependencies() {
    echo "安装系统依赖..."
    yum install -y wget ssh pdsh
}

# 创建用户和组
create_user_group() {
    if ! id "$HADOOP_USER" &>/dev/null; then
        echo "创建Hadoop用户: $HADOOP_USER"
        groupadd "$HADOOP_GROUP"
        useradd -g "$HADOOP_GROUP" "$HADOOP_USER" -d "$HADOOP_BASE_DIR"
        echo "hadoop" | passwd --stdin "$HADOOP_USER"
        # 创建配置文件
        chmod 750 /etc/sudoers
        echo "$HADOOP_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        chmod 440 /etc/sudoers
    fi
}

# 创建目录结构
create_directories() {
    echo "创建目录结构..."
    mkdir -p "$HADOOP_BASE_DIR"
    mkdir -p "$HADOOP_DATA_DIR/dfs/name"
    mkdir -p "$HADOOP_DATA_DIR/dfs/data"
    mkdir -p "$HADOOP_LOG_DIR"
    mkdir -p "$HADOOP_DATA_DIR/tmp"  # 为hadoop.tmp.dir创建目录
    chown -R "$HADOOP_USER:$HADOOP_GROUP" "$HADOOP_BASE_DIR"
}

# 下载Hadoop
download_hadoop() {
    local version=$1
    local hadoop_url="https://archive.apache.org/dist/hadoop/core/hadoop-$version/hadoop-$version.tar.gz"
    
    echo "下载Hadoop $version..."    
    # wget -O "$HADOOP_BASE_DIR/hadoop-$version.tar.gz" "$hadoop_url"
    cp -avf /tmp/hadoop-$version.tar.gz "$HADOOP_BASE_DIR"

    # 解压并创建软链接
    tar -xzf "$HADOOP_BASE_DIR/hadoop-$version.tar.gz" -C "$HADOOP_BASE_DIR"
    ln -sfn "$HADOOP_BASE_DIR/hadoop-$version" "$HADOOP_BASE_DIR/current"
    
    # 设置权限
    chown -R "$HADOOP_USER:$HADOOP_GROUP" "$HADOOP_BASE_DIR/hadoop-$version"
    chown -R "$HADOOP_USER:$HADOOP_GROUP" "$HADOOP_BASE_DIR/current"
}

# 配置Hadoop
configure_hadoop() {
    local hadoop_home="$HADOOP_BASE_DIR/current"
    
    echo "配置Hadoop环境..."
    
    # 配置hadoop-env.sh
    cat > "$hadoop_home/etc/hadoop/hadoop-env.sh" <<EOF
export JAVA_HOME=$JDK_HOME
export HADOOP_PREFIX=$hadoop_home
export HADOOP_LOG_DIR=$HADOOP_LOG_DIR
export HADOOP_OPTS="-Djava.net.preferIPv4Stack=true"
export HADOOP_CLIENT_OPTS="-Xmx512m"
EOF
    
    # 配置core-site.xml
    cat > "$hadoop_home/etc/hadoop/core-site.xml" <<EOF
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:8020</value>
    </property>
    <property>
        <name>dfs.namenode.rpc-address</name>
        <value>0.0.0.0:8020</value>  <!-- 恢复为默认 RPC 端口 8020 -->
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>file://$HADOOP_DATA_DIR/tmp</value>
    </property>
</configuration>
EOF
    
    # 配置hdfs-site.xml
    cat > "$hadoop_home/etc/hadoop/hdfs-site.xml" <<EOF
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file://$HADOOP_DATA_DIR/dfs/name</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://$HADOOP_DATA_DIR/dfs/data</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>0.0.0.0:50070</value>  <!-- 恢复为默认 Web UI 端口 50070 -->
    </property>
</configuration>
EOF
    
    # 配置mapred-site.xml
    cp "$hadoop_home/etc/hadoop/mapred-site.xml.template" "$hadoop_home/etc/hadoop/mapred-site.xml"
    cat > "$hadoop_home/etc/hadoop/mapred-site.xml" <<EOF
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.jobhistory.webapp.address</name>
        <value>0.0.0.0:19888</value>
    </property>
</configuration>
EOF
    
    # 配置yarn-site.xml
    cat > "$hadoop_home/etc/hadoop/yarn-site.xml" <<EOF
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_MAPRED_HOME</value>
    </property>
    <property>
        <name>yarn.nodemanager.localizer.address</name>
        <value>0.0.0.0:8041</value>
    </property>
    <property>
        <name>yarn.resourcemanager.address</name>
        <value>0.0.0.0:8032</value>
    </property>
    <property>
        <name>yarn.resourcemanager.scheduler.address</name>
        <value>0.0.0.0:8034</value>  <!-- 默认端口 8030 -->
    </property>
</configuration>
EOF
}

# 初始化HDFS
initialize_hdfs() {
    echo "初始化HDFS..."
    sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" namenode -format -force
}

# 创建管理脚本
create_management_scripts() {
    # 启动脚本
    cat > "$HADOOP_BASE_DIR/start-hadoop.sh" <<EOF
#!/bin/bash
# Hadoop启动脚本

set -e

echo "启动HDFS..."
sudo -u $HADOOP_USER $HADOOP_BASE_DIR/current/sbin/start-dfs.sh

echo "启动YARN..."
sudo -u $HADOOP_USER $HADOOP_BASE_DIR/current/sbin/start-yarn.sh

echo "启动历史服务器..."
sudo -u $HADOOP_USER $HADOOP_BASE_DIR/current/sbin/mr-jobhistory-daemon.sh start historyserver

echo "Hadoop服务已启动"
EOF
    
    # 停止脚本
    cat > "$HADOOP_BASE_DIR/stop-hadoop.sh" <<EOF
#!/bin/bash
# Hadoop停止脚本

set -e

echo "停止历史服务器..."
sudo -u $HADOOP_USER $HADOOP_BASE_DIR/current/sbin/mr-jobhistory-daemon.sh stop historyserver

echo "停止YARN..."
sudo -u $HADOOP_USER $HADOOP_BASE_DIR/current/sbin/stop-yarn.sh

echo "停止HDFS..."
sudo -u $HADOOP_USER $HADOOP_BASE_DIR/current/sbin/stop-dfs.sh

echo "Hadoop服务已停止"
EOF
    
    # 设置权限
    chmod +x "$HADOOP_BASE_DIR/start-hadoop.sh"
    chmod +x "$HADOOP_BASE_DIR/stop-hadoop.sh"
    chown "$HADOOP_USER:$HADOOP_GROUP" "$HADOOP_BASE_DIR/start-hadoop.sh"
    chown "$HADOOP_USER:$HADOOP_GROUP" "$HADOOP_BASE_DIR/stop-hadoop.sh"
}

# 端口检测函数
check_ports() {
    local ports=("8020" "50070" "8032" "19888" "8041")
    local services=("HDFS NameNode(RPC)" "HDFS Web UI" "YARN ResourceManager" "JobHistory(Web UI)" "YARN NodeManager")
    echo "检测端口状态..."
    for i in "${!ports[@]}"; do
        if netstat -tuln | grep ":${ports[i]}" > /dev/null; then
            echo "✅ ${services[i]} 端口 ${ports[i]} 已监听"
        else
            echo "❌ ${services[i]} 端口 ${ports[i]} 未监听"
        fi
    done
}

# 连接测试
test_connection() {
    echo "运行连接测试..."
    
    # 创建测试目录
    sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" dfs -mkdir -p /test
    
    # 上传测试文件
    local test_file="/tmp/hadoop_test_$(date +%s).txt"
    echo "Hello Hadoop" > "$test_file"
    sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" dfs -put "$test_file" /test/
    
    # 读取测试文件
    local content=$(sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" dfs -cat /test/$(basename "$test_file"))
    
    if [ "$content" == "Hello Hadoop" ]; then
        echo "✅ HDFS 读写测试成功"
    else
        echo "❌ HDFS 读写测试失败"
    fi
    
    # 运行MapReduce测试
    echo "运行WordCount示例..."
    sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" dfs -mkdir -p /input
    sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" dfs -put "$HADOOP_BASE_DIR/current/etc/hadoop"/*.xml /input
    
    # 确保使用正确的JAR文件
    local example_jar=$(find "$HADOOP_BASE_DIR/current/share/hadoop/mapreduce" -name "hadoop-mapreduce-examples-*.jar" | head -1)
    
    if [ -z "$example_jar" ]; then
        echo "⚠️ 未找到MapReduce示例JAR文件，跳过MapReduce测试"
    else
        sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hadoop" jar "$example_jar" wordcount /input /output
        
        # 检查结果
        local result=$(sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" dfs -cat /output/part-r-00000 | wc -l)
        
        if [ "$result" -gt 0 ]; then
            echo "✅ MapReduce 测试成功"
        else
            echo "❌ MapReduce 测试失败"
        fi
    fi
    
    # 清理测试数据
    sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/current/bin/hdfs" dfs -rm -r /test /input /output 2>/dev/null || true
    rm -f "$test_file"
}

# 设置环境变量
setup_environment() {
    echo "设置环境变量..."
    cat > /etc/profile.d/hadoop.sh <<EOF
export HADOOP_HOME=$HADOOP_BASE_DIR/current
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
EOF
    source /etc/profile.d/hadoop.sh
}

# 版本切换函数
switch_version() {
    local new_version=$1
    local hadoop_url="https://archive.apache.org/dist/hadoop/core/hadoop-$new_version/hadoop-$new_version.tar.gz"
    
    if [ ! -d "$HADOOP_BASE_DIR/hadoop-$new_version" ]; then
        echo "下载并安装Hadoop $new_version..."
        wget -q -O "$HADOOP_BASE_DIR/hadoop-$new_version.tar.gz" "$hadoop_url"
        tar -xzf "$HADOOP_BASE_DIR/hadoop-$new_version.tar.gz" -C "$HADOOP_BASE_DIR"
        chown -R "$HADOOP_USER:$HADOOP_GROUP" "$HADOOP_BASE_DIR/hadoop-$new_version"
    fi
    
    # 切换版本
    ln -sfn "$HADOOP_BASE_DIR/hadoop-$new_version" "$HADOOP_BASE_DIR/current"
    configure_hadoop
    echo "已切换到Hadoop $new_version"
}

# 主安装函数
install_hadoop() {
    # 下载并安装Hadoop
    download_hadoop "$HADOOP_VERSION"
    
    # 配置Hadoop
    configure_hadoop
    
    # 初始化HDFS
    initialize_hdfs
    
    # 创建管理脚本
    create_management_scripts
    
    # 设置环境变量
    setup_environment
}

# 主执行流程
main() {
    # 检查JDK
    if [ ! -d "$JDK_HOME" ]; then
        echo "❌ JDK未安装或路径不正确: $JDK_HOME"
        exit 1
    fi
    
    # 安装依赖
    install_dependencies
    
    # 创建用户和组
    create_user_group
    
    # 创建目录
    create_directories
    
    # 安装Hadoop
    install_hadoop
    
    # 启动Hadoop
    echo "启动Hadoop服务..."
    sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/start-hadoop.sh"
    
    # 等待服务启动
    echo "等待服务启动..."
    sleep 15
    
    # 检查端口
    check_ports
    
    # 运行测试
    test_connection
    
    # 完成提示
    echo -e "\n✅ Hadoop $HADOOP_VERSION 安装完成"
    echo "=================================================="
    echo "安装目录: $HADOOP_BASE_DIR"
    echo "数据目录: $HADOOP_DATA_DIR"
    echo "日志目录: $HADOOP_LOG_DIR"
    echo "管理脚本:"
    echo "  启动: $HADOOP_BASE_DIR/start-hadoop.sh"
    echo "  停止: $HADOOP_BASE_DIR/stop-hadoop.sh"
    echo "Web界面:"
    echo "  HDFS: http://$(hostname -I | awk '{print $1}'):50070"
    echo "  YARN: http://$(hostname -I | awk '{print $1}'):8088"
    echo "=================================================="
}

# 执行主函数
main