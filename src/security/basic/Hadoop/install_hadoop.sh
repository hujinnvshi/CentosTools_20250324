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

# 设置变量
HADOOP_VERSION="2.7.7"
HADOOP_HOME="/data/hadoop-${HADOOP_VERSION}/base"
HADOOP_DATA="/data/hadoop-${HADOOP_VERSION}/data"
HADOOP_LOGS="/data/hadoop-${HADOOP_VERSION}/logs"
DOWNLOAD_URL="https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HADOOP_HEAP_SIZE=$(($TOTAL_MEM * 60 / 100))

# 创建目录
print_message "创建目录结构..."
mkdir -p ${HADOOP_HOME}
mkdir -p ${HADOOP_DATA}/{namenode,datanode}
mkdir -p ${HADOOP_LOGS}

# 下载 Hadoop
print_message "下载 Hadoop..."
cd /tmp
if [ ! -f "hadoop-${HADOOP_VERSION}.tar.gz" ]; then
    wget ${DOWNLOAD_URL}
    if [ $? -ne 0 ]; then
        print_error "下载失败，请检查网络连接"
        exit 1
    fi
fi

# 解压安装
print_message "安装 Hadoop..."
tar -xzf hadoop-${HADOOP_VERSION}.tar.gz -C ${HADOOP_HOME} --strip-components=1

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/hadoop.sh << EOF
# Hadoop 环境变量
export HADOOP_HOME=${HADOOP_HOME}
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
export HADOOP_CONF_DIR=\$HADOOP_HOME/etc/hadoop
export HADOOP_LOG_DIR=${HADOOP_LOGS}
export YARN_LOG_DIR=${HADOOP_LOGS}
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

# 创建服务文件
print_message "创建系统服务..."
cat > /usr/lib/systemd/system/hadoop.service << EOF
[Unit]
Description=Hadoop Service
After=network.target

[Service]
Type=forking
User=root
Environment=JAVA_HOME=${JAVA_HOME}
ExecStart=${HADOOP_HOME}/sbin/start-all.sh
ExecStop=${HADOOP_HOME}/sbin/stop-all.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 设置权限
print_message "设置权限..."
chmod -R 755 ${HADOOP_HOME}
chmod -R 755 ${HADOOP_DATA}
chmod -R 755 ${HADOOP_LOGS}

# 格式化 namenode
print_message "格式化 namenode..."
${HADOOP_HOME}/bin/hdfs namenode -format

# 启动服务
print_message "启动 Hadoop 服务..."
systemctl daemon-reload
systemctl enable hadoop
systemctl start hadoop

# 等待服务启动
sleep 30

# 测试验证
print_message "验证 Hadoop 安装..."
jps
${HADOOP_HOME}/bin/hadoop fs -mkdir /test
${HADOOP_HOME}/bin/hadoop fs -ls /

print_message "Hadoop 安装完成！"
print_message "Web 界面: http://localhost:50070"
print_message "YARN 界面: http://localhost:8088"