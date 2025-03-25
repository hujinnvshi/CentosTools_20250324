#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量
HIVE_VERSION="3.1.2"
HIVE_HOME="/data/hive"
HIVE_CONF_DIR="${HIVE_HOME}/conf"
HIVE_LOG_DIR="/data/hive/logs"
DOWNLOAD_URL="https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz"
BACKUP_URL="https://mirrors.tuna.tsinghua.edu.cn/apache/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz"

# MySQL 配置
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_DB="hive20250324"
MYSQL_USER="hive20250324"
MYSQL_PASSWORD="Secsmart#612"

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HIVE_HEAP_SIZE=$(($TOTAL_MEM * 40 / 100))

# 检查必要组件
check_requirements() {
    local missing=""
    for cmd in wget tar java mysql; do
        if ! command -v $cmd &> /dev/null; then
            missing="$missing $cmd"
        fi
    done
    
    if [ ! -z "$missing" ]; then
        print_error "缺少必要组件:$missing"
        exit 1
    fi
}

# 检查 Java 版本
check_java_version() {
    local java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    if [[ ! $java_version =~ ^1\.8\. ]]; then
        print_error "需要 JDK 1.8，当前版本: $java_version"
        exit 1
    fi
}

# 检查 Hadoop
check_hadoop() {
    if ! command -v hdfs &> /dev/null; then
        print_error "未检测到 Hadoop 环境"
        exit 1
    fi
    
    # 测试 HDFS 连接
    if ! hdfs dfs -ls / &> /dev/null; then
        print_error "无法连接到 HDFS"
        exit 1
    fi
}

# 安装 MySQL 驱动
print_message "安装 MySQL 驱动..."
MYSQL_CONNECTOR_VERSION="5.1.49"
MYSQL_CONNECTOR_JAR="mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar"
MYSQL_CONNECTOR_URL="https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_CONNECTOR_VERSION}/${MYSQL_CONNECTOR_JAR}"

# 下载并安装 MySQL 驱动
cd /tmp
if [ ! -f "${MYSQL_CONNECTOR_JAR}" ]; then
    wget ${MYSQL_CONNECTOR_URL} || {
        print_error "下载 MySQL 驱动失败"
        exit 1
    }
fi

# 复制到全局 Java 扩展目录
mkdir -p /usr/share/java
cp ${MYSQL_CONNECTOR_JAR} /usr/share/java/mysql-connector-java.jar
ln -sf /usr/share/java/mysql-connector-java.jar ${JAVA_HOME}/jre/lib/ext/

# 同时复制到 Hive lib 目录
cp /usr/share/java/mysql-connector-java.jar ${HIVE_HOME}/lib/


# 检查 MySQL
check_mysql() {
    if ! mysql -h${MYSQL_HOST} -P${MYSQL_PORT} -u${MYSQL_USER} -p${MYSQL_PASSWORD} -e ";" 2>/dev/null; then
        print_error "MySQL 连接失败"
        exit 1
    fi
}

# 运行检查
print_message "执行环境检查..."
check_requirements
check_java_version
check_hadoop
check_mysql

# 创建目录
print_message "创建目录结构..."
mkdir -p ${HIVE_HOME} 2>/dev/null || print_warning "目录 ${HIVE_HOME} 已存在"
mkdir -p ${HIVE_LOG_DIR} 2>/dev/null || print_warning "目录 ${HIVE_LOG_DIR} 已存在"

# 下载 Hive
print_message "下载 Hive..."
cd /tmp
HIVE_FILE="apache-hive-${HIVE_VERSION}-bin.tar.gz"

# 检查文件是否存在且有效
check_file() {
    if [ -f "$1" ] && [ -s "$1" ]; then
        print_message "发现有效的安装包: $1"
        return 0
    fi
    return 1
}

# 首先检查当前目录
if check_file "${HIVE_FILE}"; then
    print_message "使用当前目录的安装包..."
elif check_file "/tmp/${HIVE_FILE}"; then
    print_message "使用 /tmp 目录的安装包..."
    cp "/tmp/${HIVE_FILE}" .
else
    print_message "未找到本地安装包，尝试从镜像下载..."
    wget ${DOWNLOAD_URL} || {
        print_message "Apache 下载失败，尝试清华镜像..."
        wget ${BACKUP_URL} || {
            print_error "所有下载源均失败"
            exit 1
        }
    }
fi

# 解压安装
print_message "安装 Hive..."
tar -xzf "${HIVE_FILE}" -C ${HIVE_HOME} --strip-components=1 || {
    print_error "解压安装包失败"
    exit 1
}

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/hive.sh << EOF
# Hive 环境变量
export HIVE_HOME=${HIVE_HOME}
export PATH=\${HIVE_HOME}/bin:\${PATH}
EOF

source /etc/profile.d/hive.sh

# 为 hadoop 用户配置环境变量
print_message "配置 hadoop 用户环境变量..."
su - hadoop -c "cat >> ~/.bash_profile << 'EOF'

# Hive 环境变量
if [ -f /etc/profile.d/hive.sh ]; then
    source /etc/profile.d/hive.sh
fi
EOF"

# 配置 hive-site.xml
print_message "配置 hive-site.xml..."
cat > ${HIVE_CONF_DIR}/hive-site.xml << EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <!-- 基础配置 -->
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB}?createDatabaseIfNotExist=true&amp;useSSL=false</value>
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
        <value>${MYSQL_PASSWORD}</value>
    </property>
    
    <!-- Binary 传输模式配置 -->
    <property>
        <name>hive.server2.transport.mode</name>
        <value>binary</value>
    </property>
    <property>
        <name>hive.server2.thrift.port</name>
        <value>10000</value>
    </property>
    <property>
        <name>hive.server2.thrift.bind.host</name>
        <value>0.0.0.0</value>
    </property>
    
    <!-- 执行引擎配置 -->
    <property>
        <name>hive.execution.engine</name>
        <value>mr</value>
    </property>
    
    <!-- 禁用 Tez 初始化 -->
    <property>
        <name>hive.server2.enable.doAs</name>
        <value>false</value>
    </property>
    
    <property>
        <name>hive.server2.tez.initialize.default.sessions</name>
        <value>false</value>
    </property>

    <property>
        <name>hive.server2.tez.default.queues</name>
        <value></value>
    </property>

    <property>
        <name>hive.server2.tez.sessions.per.default.queue</name>
        <value>0</value>
    </property>

    <!-- 其他配置保持不变 -->
</configuration>
EOF

# 配置日志
print_message "配置日志..."
cat > ${HIVE_CONF_DIR}/hive-log4j2.properties << EOF
property.hive.log.dir = ${HIVE_LOG_DIR}
property.hive.log.file = hive.log

# Root logger
rootLogger.level = INFO
rootLogger.appenderRefs = console, file
rootLogger.appenderRef.console.ref = CONSOLE
rootLogger.appenderRef.file.ref = DAILY

# Console appender
appender.console.type = Console
appender.console.name = CONSOLE
appender.console.target = SYSTEM_ERR
appender.console.layout.type = PatternLayout
appender.console.layout.pattern = %d{ISO8601} %5p [%t] %c{2}: %m%n

# Daily file appender
appender.daily.type = RollingFile
appender.daily.name = DAILY
appender.daily.fileName = \${sys:hive.log.dir}/\${sys:hive.log.file}
appender.daily.filePattern = \${sys:hive.log.dir}/\${sys:hive.log.file}.%d{yyyy-MM-dd}
appender.daily.layout.type = PatternLayout
appender.daily.layout.pattern = %d{ISO8601} %5p [%t] %c{2}: %m%n
appender.daily.policies.type = Policies
appender.daily.policies.time.type = TimeBasedTriggeringPolicy
appender.daily.policies.time.interval = 1
appender.daily.policies.time.modulate = true
appender.daily.strategy.type = DefaultRolloverStrategy
appender.daily.strategy.max = 30
EOF

# 配置日志轮转
print_message "配置日志轮转..."
cat > /etc/logrotate.d/hive << EOF
${HIVE_LOG_DIR}/*.log {
    weekly
    rotate 52
    copytruncate
    compress
    missingok
    notifempty
}
EOF

# 创建 hive 用户
print_message "创建 hive 用户..."
groupadd hadoop 2>/dev/null || print_warning "用户组 hadoop 已存在"
useradd -m -g hadoop -s /bin/bash hive 2>/dev/null || print_warning "用户 hive 已存在"

# 设置权限
print_message "设置权限..."
chown -R hive:hadoop ${HIVE_HOME}
chown -R hive:hadoop ${HIVE_LOG_DIR}
chmod -R 755 ${HIVE_HOME}
chmod -R 755 ${HIVE_LOG_DIR}

# 为 hive 用户配置环境变量
print_message "配置 hive 用户环境变量..."
su - hive -c "cat >> ~/.bash_profile << 'EOF'

# Hive 环境变量
if [ -f /etc/profile.d/hive.sh ]; then
    source /etc/profile.d/hive.sh
fi
EOF"

# 初始化元数据库
print_message "初始化 Hive 元数据库..."
su - hive -c "${HIVE_HOME}/bin/schematool -dbType mysql -initSchema" || {
    print_error "初始化元数据库失败"
    exit 1
}

# 创建 Metastore 服务文件
print_message "创建 Metastore 服务文件..."
cat > /usr/lib/systemd/system/hive-metastore.service << EOF
[Unit]
Description=Apache Hive Metastore
After=network.target mysql.service hadoop.service
Before=hive.service

[Service]
Type=forking
User=hive
Group=hadoop
Environment=JAVA_HOME=${JAVA_HOME}
Environment=HIVE_HOME=${HIVE_HOME}
ExecStart=${HIVE_HOME}/bin/hive --service metastore
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 修改 HiveServer2 服务配置
print_message "更新 HiveServer2 服务配置..."
cat > /usr/lib/systemd/system/hive.service << EOF
[Unit]
Description=Apache Hive Server
After=network.target hadoop.service hive-metastore.service
Requires=hive-metastore.service

[Service]
Type=forking
User=hive
Group=hadoop
Environment=JAVA_HOME=${JAVA_HOME}
Environment=HIVE_HOME=${HIVE_HOME}
ExecStart=${HIVE_HOME}/bin/hiveserver2
ExecStop=/bin/kill \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
print_message "启动 Hive 服务..."
systemctl daemon-reload
systemctl enable hive-metastore
systemctl enable hive
systemctl start hive-metastore
sleep 10  # 等待 metastore 完全启动
systemctl start hive


# 等待服务启动
print_message "等待服务启动..."
max_attempts=10
attempt=1

while [ $attempt -le $max_attempts ]; do
    if netstat -tnlp | grep -q ":10000"; then
        print_message "Hive 服务已启动"
        break
    fi
    print_message "等待 Hive 服务启动... $attempt/$max_attempts"
    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -gt $max_attempts ]; then
    print_error "Hive 服务启动失败"
    exit 1
fi

# 测试验证
print_message "验证 Hive 安装..."
su - hive -c "hive -e 'show databases;'" || {
    print_error "Hive 测试失败"
    exit 1
}

# 完成安装
cat > ${HIVE_HOME}/bin/start-hive.sh << EOF
#!/bin/bash
cd \${HIVE_HOME}/bin
nohup \${HIVE_HOME}/bin/hive --service metastore > ${HIVE_LOG_DIR}/metastore.out 2>&1 &
sleep 30
nohup \${HIVE_HOME}/bin/hiveserver2 > ${HIVE_LOG_DIR}/hiveserver2.out 2>&1 &
EOF

cat > ${HIVE_HOME}/bin/stop-hive.sh << EOF
#!/bin/bash
pkill -f org.apache.hadoop.hive.metastore.HiveMetaStore
pkill -f org.apache.hive.service.server.HiveServer2
EOF

chmod +x ${HIVE_HOME}/bin/start-hive.sh
chmod +x ${HIVE_HOME}/bin/stop-hive.sh
chown hive:hadoop ${HIVE_HOME}/bin/start-hive.sh
chown hive:hadoop ${HIVE_HOME}/bin/stop-hive.sh


print_message "Hive 安装完成！"
print_message "HiveServer2 端口: 10000"
print_message "Web UI: http://localhost:10002"

# 显示服务状态
print_message "当前服务状态:"
systemctl status hive