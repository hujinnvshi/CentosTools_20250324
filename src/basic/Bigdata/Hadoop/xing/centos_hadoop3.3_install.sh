#!/bin/bash
# Hadoop 3.3.6 一键安装脚本
# 适用于 Ubuntu/CentOS 系统
# wget https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 安装信息
print_step "=== Hadoop 3.3.6 一键安装脚本 ==="

# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    print_message "检测到操作系统: $OS $OS_VERSION"
else
    print_error "无法检测操作系统类型"
    exit 1
fi

# 检查 Java 环境
print_step "1. 检查 Java 环境"
if ! command -v java &> /dev/null; then
    print_error "未检测到 Java 环境，请先安装 JDK 8 或 JDK 11"
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

# 检查 Java 版本
JAVA_VERSION=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
print_message "Java 版本: $JAVA_VERSION"

# 检查必要组件
check_requirements() {
    print_step "2. 检查系统依赖"
    local missing=""
    for cmd in wget tar ssh-keygen; do
        if ! command -v $cmd &> /dev/null; then
            missing="$missing $cmd"
        fi
    done
    
    if [ ! -z "$missing" ]; then
        print_message "安装缺失组件: $missing"
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            apt update
            apt install -y $missing
        elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            yum install -y $missing
        fi
    else
        print_message "所有必要组件已安装"
    fi
}

check_requirements

# 设置 Hadoop 变量
HADOOP_VERSION="3.3.6"
HADOOP_HOME="/opt/hadoop"
HADOOP_DATA="/data/hadoop"
HADOOP_LOGS="/var/log/hadoop"
DOWNLOAD_URL="https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"
BACKUP_URL="https://mirrors.tuna.tsinghua.edu.cn/apache/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))

# 检查内存是否足够
if [ $TOTAL_MEM_GB -lt 2 ]; then
    print_warning "系统内存较少（${TOTAL_MEM_GB}GB），Hadoop 可能无法正常运行"
fi

# 计算 Hadoop 内存配置（修正版本）
calculate_memory_config() {
    local mem_gb=$1
    # 转换为 MB
    local total_mem_mb=$((mem_gb * 1024))
    # YARN 使用 70% 内存
    local yarn_memory=$((total_mem_mb * 70 / 100))
    # Map 任务使用 YARN 内存的 20%
    local map_memory=$((yarn_memory * 20 / 100))
    # Reduce 任务使用 YARN 内存的 40%
    local reduce_memory=$((yarn_memory * 40 / 100))
    
    # 确保最小值
    if [ $map_memory -lt 1024 ]; then
        map_memory=1024
    fi
    if [ $reduce_memory -lt 1024 ]; then
        reduce_memory=1024
    fi
    
    echo "$yarn_memory $map_memory $reduce_memory"
}

# 使用修正的内存计算
read YARN_MEMORY MAP_MEMORY REDUCE_MEMORY <<< $(calculate_memory_config $TOTAL_MEM_GB)

print_message "系统资源: ${CPU_CORES} 核心, ${TOTAL_MEM_GB}GB 内存"
print_message "Hadoop 内存配置: YARN=${YARN_MEMORY}MB, Map=${MAP_MEMORY}MB, Reduce=${REDUCE_MEMORY}MB"

# 清理和备份
print_step "3. 准备安装环境"
if [ -d "${HADOOP_HOME}" ]; then
    print_warning "发现现有 Hadoop 安装，创建备份..."
    backup_dir="/opt/backup/hadoop-$(date +%Y%m%d_%H%M%S)"
    mkdir -p ${backup_dir}
    mv ${HADOOP_HOME} ${backup_dir}/ 2>/dev/null && print_message "备份 ${HADOOP_HOME} 完成"
fi

# 创建目录结构
print_message "创建目录结构..."
mkdir -p ${HADOOP_HOME}
mkdir -p ${HADOOP_DATA}/{namenode,datanode,tmp}
mkdir -p ${HADOOP_LOGS}

# 创建 hadoop 用户和组
print_step "4. 创建 Hadoop 系统用户"
if ! getent group hadoop >/dev/null; then
    groupadd hadoop
    print_message "创建用户组: hadoop"
else
    print_warning "用户组 hadoop 已存在"
fi

if ! id -u hdfs >/dev/null 2>&1; then
    useradd -r -m -g hadoop -s /bin/bash -d ${HADOOP_HOME} hdfs
    print_message "创建用户: hdfs"
else
    print_warning "用户 hdfs 已存在"
    usermod -g hadoop -d ${HADOOP_HOME} -s /bin/bash hdfs
fi

# 设置目录权限
chown -R hdfs:hadoop ${HADOOP_HOME}
chown -R hdfs:hadoop ${HADOOP_DATA}
chown -R hdfs:hadoop ${HADOOP_LOGS}
chmod -R 755 ${HADOOP_HOME}
chmod -R 755 ${HADOOP_DATA}
chmod -R 755 ${HADOOP_LOGS}

# 配置 SSH 免密登录
print_step "5. 配置 SSH 免密登录"
sudo -u hdfs mkdir -p /home/hdfs/.ssh 2>/dev/null || sudo -u hdfs mkdir -p ${HADOOP_HOME}/.ssh

if [ ! -f "/home/hdfs/.ssh/id_rsa" ] && [ ! -f "${HADOOP_HOME}/.ssh/id_rsa" ]; then
    print_message "生成 SSH 密钥对..."
    sudo -u hdfs ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
    sudo -u hdfs cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    sudo -u hdfs chmod 600 ~/.ssh/authorized_keys
else
    print_warning "SSH 密钥已存在"
fi

# 下载 Hadoop
print_step "6. 下载 Hadoop ${HADOOP_VERSION}"
cd /tmp
HADOOP_FILE="hadoop-${HADOOP_VERSION}.tar.gz"

# 检查本地文件
check_local_file() {
    local possible_paths=(
        "/tmp/${HADOOP_FILE}"
        "./${HADOOP_FILE}"
        "/opt/${HADOOP_FILE}"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path" ] && [ -s "$path" ]; then
            print_message "使用本地文件: $path"
            cp "$path" .
            return 0
        fi
    done
    return 1
}

if check_local_file; then
    print_message "使用本地安装包"
else
    print_message "从镜像下载 Hadoop..."
    if wget -O "${HADOOP_FILE}" "${DOWNLOAD_URL}" --no-check-certificate; then
        print_message "下载成功"
    else
        print_warning "主镜像下载失败，尝试备用镜像..."
        if wget -O "${HADOOP_FILE}" "${BACKUP_URL}" --no-check-certificate; then
            print_message "备用镜像下载成功"
        else
            print_error "所有下载源均失败"
            exit 1
        fi
    fi
fi

# 验证下载文件
if [ ! -f "${HADOOP_FILE}" ] || [ ! -s "${HADOOP_FILE}" ]; then
    print_error "Hadoop 安装包不存在或为空"
    exit 1
fi

# 解压安装
print_step "7. 安装 Hadoop"
tar -xzf "${HADOOP_FILE}" -C ${HADOOP_HOME} --strip-components=1
if [ $? -ne 0 ]; then
    print_error "解压安装包失败"
    exit 1
fi

# 设置环境变量
print_step "8. 配置环境变量"
cat > /etc/profile.d/hadoop.sh << EOF
#!/bin/bash
# Hadoop Environment Variables
export JAVA_HOME=${JAVA_HOME}
export HADOOP_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=\${HADOOP_HOME}/etc/hadoop
export HADOOP_LOG_DIR=${HADOOP_LOGS}
export HADOOP_MAPRED_LOG_DIR=${HADOOP_LOGS}
# export YARN_LOG_DIR=${HADOOP_LOGS}
export HADOOP_LOG_DIR=${HADOOP_LOGS}
export PATH=\$PATH:\${JAVA_HOME}/bin:\${HADOOP_HOME}/bin:\${HADOOP_HOME}/sbin
export HADOOP_OPTS="-Djava.library.path=\${HADOOP_HOME}/lib/native"
EOF

chmod 644 /etc/profile.d/hadoop.sh
source /etc/profile.d/hadoop.sh

# 配置 Hadoop
print_step "9. 配置 Hadoop"

# 获取本机IP
HOST_IP=$(hostname -I | awk '{print $1}')
print_message "使用主机IP: $HOST_IP"

# 配置 core-site.xml
cat > ${HADOOP_HOME}/etc/hadoop/core-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://${HOST_IP}:8020</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>file://${HADOOP_DATA}/tmp</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hdfs.hosts</name>
        <value>*</value>
    </property>
    <property>
        <name>hadoop.proxyuser.hdfs.groups</name>
        <value>*</value>
    </property>

</configuration>
EOF

# 配置 hdfs-site.xml
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
        <value>file://${HADOOP_DATA}/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://${HADOOP_DATA}/datanode</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>${HOST_IP}:9870</value>
    </property>
    <property>
        <name>dfs.namenode.secondary.http-address</name>
        <value>${HOST_IP}:9868</value>
    </property>
</configuration>
EOF

# 配置 mapred-site.xml
print_message "配置 mapred-site.xml..."
cp ${HADOOP_HOME}/etc/hadoop/mapred-site.xml ${HADOOP_HOME}/etc/hadoop/mapred-site.xml.template

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
        <value>${MAP_MEMORY}</value>
    </property>
    <property>
        <name>mapreduce.reduce.memory.mb</name>
        <value>${REDUCE_MEMORY}</value>
    </property>
    <property>
        <name>mapreduce.map.java.opts</name>
        <value>-Xmx$((MAP_MEMORY * 80 / 100))m</value>
    </property>
    <property>
        <name>mapreduce.reduce.java.opts</name>
        <value>-Xmx$((REDUCE_MEMORY * 80 / 100))m</value>
    </property>
    <property>
        <name>yarn.app.mapreduce.am.env</name>
        <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
    </property>
    <property>
        <name>mapreduce.map.env</name>
        <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
    </property>
    <property>
        <name>mapreduce.reduce.env</name>
        <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
    </property>
</configuration>
EOF

# 配置 yarn-site.xml
cat > ${HADOOP_HOME}/etc/hadoop/yarn-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>
        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
    </property>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>${HOST_IP}</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>${YARN_MEMORY}</value>
    </property>
    <property>
        <name>yarn.scheduler.maximum-allocation-mb</name>
        <value>${YARN_MEMORY}</value>
    </property>
    <property>
        <name>yarn.scheduler.minimum-allocation-mb</name>
        <value>1024</value>
    </property>
    <property>
        <name>yarn.nodemanager.vmem-check-enabled</name>
        <value>false</value>
    </property>
    <property>
        <name>yarn.log-aggregation-enable</name>
        <value>true</value>
    </property>
</configuration>
EOF

# 配置 workers 文件（替代 slaves 文件）
echo "localhost" > ${HADOOP_HOME}/etc/hadoop/workers
echo "JAVA_HOME: ${JAVA_HOME}"

# 配置 hadoop-env.sh
print_message "配置 hadoop-env.sh..."
echo "export JAVA_HOME=${JAVA_HOME}" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh
echo "export HADOOP_LOG_DIR=${HADOOP_LOGS}" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh
echo "export HADOOP_PID_DIR=/tmp" >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

# 设置权限
chown -R hdfs:hadoop ${HADOOP_HOME}
chown -R hdfs:hadoop ${HADOOP_DATA}
chown -R hdfs:hadoop ${HADOOP_LOGS}

# 配置防火墙
print_step "10. 配置防火墙"
configure_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        # Ubuntu/Debian
        if ufw status | grep -q "Status: active"; then
            ufw allow 9000/tcp  # HDFS
            ufw allow 9870/tcp  # NameNode Web
            ufw allow 8088/tcp  # YARN Web
            ufw allow 9864/tcp  # DataNode
            ufw allow 8030/tcp  # ResourceManager
            ufw allow 8031/tcp  # ResourceTracker
            ufw allow 8032/tcp  # ResourceManager Scheduler
            ufw allow 8033/tcp  # ResourceManager Admin
            print_message "UFW 防火墙规则已添加"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        # CentOS/RHEL
        if systemctl is-active firewalld >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=9000/tcp
            firewall-cmd --permanent --add-port=9870/tcp
            firewall-cmd --permanent --add-port=8088/tcp
            firewall-cmd --permanent --add-port=9864/tcp
            firewall-cmd --permanent --add-port=8030/tcp
            firewall-cmd --permanent --add-port=8031/tcp
            firewall-cmd --permanent --add-port=8032/tcp
            firewall-cmd --permanent --add-port=8033/tcp
            firewall-cmd --reload
            print_message "FirewallD 防火墙规则已添加"
        fi
    else
        print_warning "未检测到防火墙工具，跳过防火墙配置"
    fi
}

configure_firewall

# 格式化 HDFS
print_step "11. 格式化 HDFS"
if [ -d "${HADOOP_DATA}/namenode" ] && [ "$(ls -A ${HADOOP_DATA}/namenode 2>/dev/null)" ]; then
    print_warning "NameNode 数据目录不为空，跳过格式化"
    print_message "如果需要重新格式化，请手动执行: sudo -u hdfs hdfs namenode -format"
else
    print_message "格式化 NameNode..."
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs namenode -format -force
    if [ $? -eq 0 ]; then
        print_message "NameNode 格式化成功"
    else
        print_error "NameNode 格式化失败"
        exit 1
    fi
fi

# 创建启动脚本
print_step "12. 创建启动脚本"
cat > /usr/local/bin/start-hadoop.sh << EOF
#!/bin/bash
# Hadoop 启动脚本

source /etc/profile.d/hadoop.sh

echo "启动 HDFS..."
sudo -u hdfs ${HADOOP_HOME}/sbin/start-dfs.sh

echo "启动 YARN..."
sudo -u hdfs ${HADOOP_HOME}/sbin/start-yarn.sh

echo "启动历史服务器..."
sudo -u hdfs ${HADOOP_HOME}/bin/mapred --daemon start historyserver

echo "Hadoop 启动完成"
EOF

cat > /usr/local/bin/stop-hadoop.sh << EOF
#!/bin/bash
# Hadoop 停止脚本

source /etc/profile.d/hadoop.sh

echo "停止历史服务器..."
sudo -u hdfs ${HADOOP_HOME}/bin/mapred --daemon stop historyserver

echo "停止 YARN..."
sudo -u hdfs ${HADOOP_HOME}/sbin/stop-yarn.sh

echo "停止 HDFS..."
sudo -u hdfs ${HADOOP_HOME}/sbin/stop-dfs.sh

echo "Hadoop 已停止"
EOF

chmod +x /usr/local/bin/start-hadoop.sh
chmod +x /usr/local/bin/stop-hadoop.sh

# 启动 Hadoop
print_step "13. 启动 Hadoop 服务"
sudo -u hdfs ${HADOOP_HOME}/sbin/start-dfs.sh
sleep 3
sudo -u hdfs ${HADOOP_HOME}/sbin/start-yarn.sh
sleep 3
sudo -u hdfs ${HADOOP_HOME}/bin/mapred --daemon start historyserver

# 等待服务启动
sleep 10

# 验证安装
print_step "14. 验证安装"
check_service() {
    local service=$1
    if sudo -u hdfs ${JAVA_HOME}/bin/jps 2>/dev/null | grep -q "$service"; then
        print_message "✓ $service 运行正常"
        return 0
    else
        print_error "✗ $service 未运行"
        return 1
    fi
}

# 检查关键服务
services=("NameNode" "DataNode" "ResourceManager" "NodeManager")
all_services_running=true

for service in "${services[@]}"; do
    if ! check_service "$service"; then
        all_services_running=false
    fi
done

# 测试 HDFS
print_message "测试 HDFS 功能..."
if sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -test -d /tmp 2>/dev/null; then
    print_message "HDFS /tmp 目录已存在"
else
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /tmp
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -chmod 1777 /tmp
    print_message "创建 HDFS /tmp 目录"
fi

# 运行简单测试
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /user/hdfs 2>/dev/null || true

# 显示安装结果
print_step "=== Hadoop 3.3.6 安装完成 ==="
echo ""
print_message "安装信息:"
echo "  Hadoop 版本: ${HADOOP_VERSION}"
echo "  安装目录: ${HADOOP_HOME}"
echo "  数据目录: ${HADOOP_DATA}"
echo "  日志目录: ${HADOOP_LOGS}"
echo ""
print_message "服务状态:"
sudo -u hdfs ${JAVA_HOME}/bin/jps 2>/dev/null || print_warning "无法运行 jps 命令"
echo ""
print_message "Web 管理界面:"
echo "  HDFS NameNode: http://${HOST_IP}:9870"
echo "  YARN ResourceManager: http://${HOST_IP}:8088"
echo ""
print_message "常用命令:"
echo "  启动所有服务: start-hadoop.sh"
echo "  停止所有服务: stop-hadoop.sh"
echo "  格式化 HDFS: sudo -u hdfs hdfs namenode -format"
echo "  HDFS 操作: sudo -u hdfs hdfs dfs -ls /"
echo ""
print_message "环境变量已配置在: /etc/profile.d/hadoop.sh"
echo "请执行 'source /etc/profile' 或重新登录使环境变量生效"
echo ""

# 验证安装是否成功
if $all_services_running; then
    print_message "✓ Hadoop 安装验证成功"
else
    print_warning "⚠ 部分服务可能未启动，请检查日志: ${HADOOP_LOGS}"
    print_message "可以尝试手动启动: sudo -u hdfs start-hadoop.sh"
fi

print_message "安装日志目录: ${HADOOP_LOGS}"