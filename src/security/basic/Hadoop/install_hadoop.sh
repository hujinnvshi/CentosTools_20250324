#!/bin/bash

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
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 检查 Java 环境
if ! command -v java &> /dev/null; then
    print_error "未检测到 Java 环境，请先安装 JDK"
    exit 1
fi

# 检查并设置 JAVA_HOME
if [ -z "${JAVA_HOME}" ]; then
    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    print_message "自动设置 JAVA_HOME 为: ${JAVA_HOME}"
fi

if [ ! -d "${JAVA_HOME}" ]; then
    print_error "JAVA_HOME 目录不存在: ${JAVA_HOME}"
    exit 1
fi

# 检查必要组件
check_requirements() {
    local missing=""
    for cmd in wget tar ssh-keygen java; do
        if ! command -v $cmd &> /dev/null; then
            missing="$missing $cmd"
        fi
    done
    
    if [ ! -z "$missing" ]; then
        print_error "缺少必要组件:$missing"
        exit 1
    fi
}

check_requirements

# 添加错误处理函数
handle_error() {
    print_error "在执行过程中发生错误，请检查日志"
    exit 1
}

# 添加错误捕获
trap 'handle_error' ERR

# 设置变量
HADOOP_VERSION="2.7.7"
HADOOP_HOME="/data/hadoop-${HADOOP_VERSION}/base"
HADOOP_DATA="/data/hadoop-${HADOOP_VERSION}/data"
HADOOP_LOGS="/data/hadoop-${HADOOP_VERSION}/logs"
DOWNLOAD_URL="https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"
BACKUP_URL="https://mirrors.tuna.tsinghua.edu.cn/apache/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HADOOP_HEAP_SIZE=$(($TOTAL_MEM * 60 / 100))

# 清理和备份
if [ -d "${HADOOP_HOME}" ]; then
    print_message "发现旧安装，创建备份..."
    backup_dir="/data/backup/hadoop-$(date +%Y%m%d_%H%M%S)"
    mkdir -p ${backup_dir}
    mv ${HADOOP_HOME} ${backup_dir}/
    mv ${HADOOP_DATA} ${backup_dir}/ 2>/dev/null || true
    mv ${HADOOP_LOGS} ${backup_dir}/ 2>/dev/null || true
fi

# 创建目录
print_message "创建目录结构..."
mkdir -p ${HADOOP_HOME}
mkdir -p ${HADOOP_DATA}/{namenode,datanode}
mkdir -p ${HADOOP_LOGS}

# 创建 hadoop 用户和组
print_message "创建 hadoop 用户..."
groupadd hadoop
useradd -m -g hadoop -s /bin/bash hadoop

# 设置权限
print_message "设置权限..."
chown -R hadoop:hadoop ${HADOOP_HOME}
chown -R hadoop:hadoop ${HADOOP_DATA}
chown -R hadoop:hadoop ${HADOOP_LOGS}
chmod -R 755 ${HADOOP_HOME}
chmod -R 755 ${HADOOP_DATA}
chmod -R 755 ${HADOOP_LOGS}

# 配置 SSH 免密登录
print_message "配置 SSH 免密登录..."
su - hadoop -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
su - hadoop -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
su - hadoop -c "chmod 600 ~/.ssh/authorized_keys"

# 下载 Hadoop
print_message "下载 Hadoop..."
cd /tmp
HADOOP_FILE="hadoop-${HADOOP_VERSION}.tar.gz"

# 检查文件是否存在且有效
check_file() {
    if [ -f "$1" ] && [ -s "$1" ]; then
        print_message "发现有效的安装包: $1"
        return 0
    fi
    return 1
}

# 首先检查当前目录
if check_file "${HADOOP_FILE}"; then
    print_message "使用当前目录的安装包..."
# 然后检查 /tmp 目录
elif check_file "/tmp/${HADOOP_FILE}"; then
    print_message "使用 /tmp 目录的安装包..."
    cp "/tmp/${HADOOP_FILE}" .
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
print_message "安装 Hadoop..."
tar -xzf "${HADOOP_FILE}" -C ${HADOOP_HOME} --strip-components=1

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/hadoop.sh << EOF
# Hadoop 环境变量
export JAVA_HOME=${JAVA_HOME}
export HADOOP_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=\${HADOOP_HOME}/etc/hadoop
export HADOOP_LOG_DIR=${HADOOP_LOGS}
export YARN_LOG_DIR=${HADOOP_LOGS}
export PATH=\${JAVA_HOME}/bin:\${HADOOP_HOME}/bin:\${HADOOP_HOME}/sbin:\${PATH}
export HADOOP_OPTS="-Djava.library.path=\${HADOOP_HOME}/lib/native"
export HADOOP_COMMON_LIB_NATIVE_DIR=\${HADOOP_HOME}/lib/native
EOF

# 配置日志轮转
print_message "配置日志轮转..."
cat > /etc/logrotate.d/hadoop << EOF
${HADOOP_LOGS}/*.log {
    weekly
    rotate 52
    copytruncate
    compress
    missingok
    notifempty
}
EOF

# 配置 core-site.xml
print_message "配置 core-site.xml..."
cat > ${HADOOP_HOME}/etc/hadoop/core-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>${HADOOP_DATA}</value>
    </property>
</configuration>
EOF

# 配置 hdfs-site.xml
print_message "配置 hdfs-site.xml..."
cat > ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>${HADOOP_DATA}/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>${HADOOP_DATA}/datanode</value>
    </property>
</configuration>
EOF

# 配置 mapred-site.xml
print_message "配置 mapred-site.xml..."
cp ${HADOOP_HOME}/etc/hadoop/mapred-site.xml.template ${HADOOP_HOME}/etc/hadoop/mapred-site.xml
cat > ${HADOOP_HOME}/etc/hadoop/mapred-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.map.memory.mb</name>
        <value>1024</value>
    </property>
    <property>
        <name>mapreduce.reduce.memory.mb</name>
        <value>2048</value>
    </property>
    <property>
        <name>mapreduce.map.java.opts</name>
        <value>-Xmx820m</value>
    </property>
    <property>
        <name>mapreduce.reduce.java.opts</name>
        <value>-Xmx1638m</value>
    </property>
</configuration>
EOF

# 配置 yarn-site.xml
print_message "配置 yarn-site.xml..."
cat > ${HADOOP_HOME}/etc/hadoop/yarn-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>$((TOTAL_MEM * 1024 * 80 / 100))</value>
    </property>
    <property>
        <name>yarn.scheduler.maximum-allocation-mb</name>
        <value>$((TOTAL_MEM * 1024 * 70 / 100))</value>
    </property>
    <property>
        <name>yarn.scheduler.minimum-allocation-mb</name>
        <value>1024</value>
    </property>
</configuration>
EOF

# 配置防火墙
print_message "配置防火墙..."
# 检查防火墙状态
if ! systemctl is-active firewalld &>/dev/null; then
    print_message "防火墙服务未运行，正在启动..."
    systemctl start firewalld
    systemctl enable firewalld
fi

if systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-port=9000/tcp
    firewall-cmd --permanent --add-port=50070/tcp
    firewall-cmd --permanent --add-port=8088/tcp
    firewall-cmd --reload
else
    print_message "警告: 防火墙服务未运行，跳过端口配置"
fi

# 创建服务文件
print_message "创建系统服务..."
cat > /usr/lib/systemd/system/hadoop.service << EOF
[Unit]
Description=Hadoop Service
After=network.target

[Service]
Type=forking
User=hadoop
Group=hadoop
Environment=JAVA_HOME=${JAVA_HOME}
Environment=HADOOP_HOME=${HADOOP_HOME}
ExecStart=${HADOOP_HOME}/sbin/start-all.sh
ExecStop=${HADOOP_HOME}/sbin/stop-all.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 格式化 namenode
print_message "格式化 namenode..."
su - hadoop -c "${HADOOP_HOME}/bin/hdfs namenode -format"

# 启动服务
print_message "启动 Hadoop 服务..."
systemctl daemon-reload
systemctl enable hadoop
systemctl start hadoop

# 等待服务启动
print_message "等待服务启动..."
max_attempts=30
attempt=1

check_service() {
    local service=$1
    jps | grep -q "$service"
    return $?
}

wait_for_service() {
    local service=$1
    while [ $attempt -le $max_attempts ]; do
        if check_service "$service"; then
            return 0
        fi
        print_message "等待 $service 启动... $attempt/$max_attempts"
        attempt=$((attempt + 1))
        sleep 2
    done
    return 1
}

# 检查关键服务
for service in NameNode DataNode ResourceManager NodeManager; do
    if ! wait_for_service "$service"; then
        print_error "$service 启动失败"
        exit 1
    fi
    print_message "$service 已启动"
done

# 测试验证
print_message "验证 Hadoop 安装..."
su - hadoop -c "${HADOOP_HOME}/bin/hadoop fs -mkdir /test"
su - hadoop -c "${HADOOP_HOME}/bin/hadoop fs -ls /"

print_message "Hadoop 安装完成！"
print_message "Web 界面: http://localhost:50070"
print_message "YARN 界面: http://localhost:8088"