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
    print_warning "发现旧安装，创建备份..."
    backup_dir="/data/backup/hadoop-$(date +%Y%m%d_%H%M%S)"
    mkdir -p ${backup_dir}
    mv ${HADOOP_HOME} ${backup_dir}/ 2>/dev/null || print_warning "备份 ${HADOOP_HOME} 失败"
    mv ${HADOOP_DATA} ${backup_dir}/ 2>/dev/null || print_warning "备份 ${HADOOP_DATA} 失败"
    mv ${HADOOP_LOGS} ${backup_dir}/ 2>/dev/null || print_warning "备份 ${HADOOP_LOGS} 失败"
fi

# 创建目录
print_message "创建目录结构..."
mkdir -p ${HADOOP_HOME} 2>/dev/null || print_warning "目录 ${HADOOP_HOME} 已存在"
mkdir -p ${HADOOP_DATA}/{namenode,datanode} 2>/dev/null || print_warning "目录 ${HADOOP_DATA} 已存在"
mkdir -p ${HADOOP_LOGS} 2>/dev/null || print_warning "目录 ${HADOOP_LOGS} 已存在"

# 创建 hadoop 用户和组
print_message "创建 hadoop 用户..."
groupadd hadoop 2>/dev/null || print_warning "用户组 hadoop 已存在"
useradd -m -g hadoop -s /bin/bash hadoop 2>/dev/null || print_warning "用户 hadoop 已存在"

# 创建 hadoop 用户组和 hdfs 用户
print_message "创建用户和用户组..."
groupadd hadoop 2>/dev/null || print_warning "用户组 hadoop 已存在"
useradd -m -g hadoop -s /bin/bash hdfs 2>/dev/null || print_warning "用户 hdfs 已存在"

# 设置权限
print_message "设置权限..."
chown -R hdfs:hadoop ${HADOOP_HOME} 2>/dev/null || print_warning "设置 ${HADOOP_HOME} 权限失败，可能已设置"
chown -R hdfs:hadoop ${HADOOP_DATA} 2>/dev/null || print_warning "设置 ${HADOOP_DATA} 权限失败，可能已设置"
chown -R hdfs:hadoop ${HADOOP_LOGS} 2>/dev/null || print_warning "设置 ${HADOOP_LOGS} 权限失败，可能已设置"
chmod -R 755 ${HADOOP_HOME}
chmod -R 755 ${HADOOP_DATA}
chmod -R 755 ${HADOOP_LOGS}

# 配置 SSH 免密登录
print_message "配置 SSH 免密登录..."
if [ ! -f "/home/hdfs/.ssh/id_rsa" ]; then
    su - hdfs -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
else
    print_warning "SSH 密钥已存在"
fi

su - hdfs -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys" 2>/dev/null || print_warning "authorized_keys 可能已配置"
su - hdfs -c "chmod 600 ~/.ssh/authorized_keys" 2>/dev/null || print_warning "authorized_keys 权限已设置"

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
tar -xzf "${HADOOP_FILE}" -C ${HADOOP_HOME} --strip-components=1 || {
    print_error "解压安装包失败"
    exit 1
}

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

source /etc/profile.d/hadoop.sh

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
        <value>hdfs://localhost:8020</value>
    </property>
    
    <property>
        <name>hadoop.tmp.dir</name>
        <value>${HADOOP_DATA}</value>
    </property>
    
    <property>
        <name>hadoop.proxyuser.hadoop.hosts</name>
        <value>*</value>
    </property>
    
    <property>
        <name>hadoop.proxyuser.hadoop.groups</name>
        <value>*</value>
    </property>
    
    <property>
        <name>hadoop.proxyuser.hive.hosts</name>
        <value>*</value>
    </property>
    
    <property>
        <name>hadoop.proxyuser.hive.groups</name>
        <value>*</value>
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
cp ${HADOOP_HOME}/etc/hadoop/mapred-site.xml.template ${HADOOP_HOME}/etc/hadoop/mapred-site.xml 2>/dev/null || print_warning "mapred-site.xml 已存在"
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
if ! systemctl is-active firewalld &>/dev/null; then
    print_warning "防火墙服务未运行，尝试启动..."
    systemctl start firewalld 2>/dev/null || print_warning "启动防火墙失败"
    systemctl enable firewalld 2>/dev/null || print_warning "设置防火墙开机启动失败"
fi

if systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-port=8020/tcp || print_warning "添加端口 8020 失败"
    firewall-cmd --permanent --add-port=50070/tcp || print_warning "添加端口 50070 失败"
    firewall-cmd --permanent --add-port=8088/tcp || print_warning "添加端口 8088 失败"
    firewall-cmd --reload || print_warning "重载防火墙配置失败"
else
    print_warning "防火墙服务未运行，跳过端口配置"
fi

# 创建服务文件
print_message "创建系统服务..."
if [ -f "/usr/lib/systemd/system/hadoop.service" ]; then
    print_warning "Hadoop 服务文件已存在，将覆盖..."
    systemctl stop hadoop 2>/dev/null || true
fi

cat > /usr/lib/systemd/system/hadoop.service << EOF
[Unit]
Description=Hadoop Service
After=network.target

[Service]
Type=forking
User=hdfs
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
if [ -d "${HADOOP_DATA}/namenode/current" ]; then
    print_warning "NameNode 已格式化，跳过格式化步骤"
else
    su - hdfs -c "${HADOOP_HOME}/bin/hdfs namenode -format"
fi

# 启动服务
print_message "启动 Hadoop 服务..."
systemctl daemon-reload

# 检查并显示 Hadoop 日志目录权限
print_message "检查日志目录权限..."
ls -la ${HADOOP_LOGS}
chown -R hdfs:hadoop ${HADOOP_LOGS}

# 尝试启动服务
systemctl enable hadoop || print_warning "设置 Hadoop 服务开机启动失败"
if ! systemctl start hadoop; then
    print_warning "通过 systemd 启动失败，尝试直接启动..."
    su - hdfs -c "${HADOOP_HOME}/sbin/start-dfs.sh"
    su - hdfs -c "${HADOOP_HOME}/sbin/start-yarn.sh"
fi

# 等待服务启动
print_message "等待服务启动..."
max_attempts=10
attempt=1

check_service() {
    local service=$1
    if ! jps | grep -q "$service"; then
        # 检查相关日志
        print_warning "检查 ${service} 日志..."
        tail -n 20 ${HADOOP_LOGS}/${service}*.log 2>/dev/null || print_warning "无法找到 ${service} 日志"
        return 1
    fi
    return 0
}

wait_for_service() {
    local service=$1
    while [ $attempt -le $max_attempts ]; do
        if check_service "$service"; then
            print_message "${service} 启动成功"
            return 0
        fi
        print_message "等待 ${service} 启动... $attempt/$max_attempts"
        attempt=$((attempt + 1))
        sleep 5
    done
    print_error "${service} 启动失败"
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
su - hdfs -c "${HADOOP_HOME}/bin/hadoop fs -mkdir /test" 2>/dev/null || print_message "测试目录已存在"
su - hdfs -c "${HADOOP_HOME}/bin/hadoop fs -ls /"

print_message "Hadoop 安装完成！"
print_message "Web 界面: http://localhost:50070"
print_message "YARN 界面: http://localhost:8088"

# 显示服务状态
print_message "当前服务状态:"
jps
systemctl status hadoop

# 在脚本末尾添加
print_message "执行验证和测试..."
if [ -f "./verify_hadoop.sh" ]; then
    chmod +x ./verify_hadoop.sh
    ./verify_hadoop.sh
else
    print_error "未找到验证脚本 verify_hadoop.sh"
fi

# 业已核验之次数： 
# ⭐️ 172.16.48.171 时间戳：2025-04-11 17:05:27