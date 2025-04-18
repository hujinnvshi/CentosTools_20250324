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

# 设置变量
JAVA_VERSION="8u371"
JAVA_BUILD="b11"
JAVA_HOME="/data/java/jdk1.8.0_251"

# 使用阿里云镜像源(从百度网盘手工下载)
DOWNLOAD_URL="https://mirrors.aliyun.com/adoptopenjdk/8/jdk/x64/linux/OpenJDK8U-jdk_x64_linux_hotspot_8u372b07.tar.gz"
JAVA_FILE="jdk-8u251-linux-x64.tar.gz"

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HEAP_SIZE=$(($TOTAL_MEM * 70 / 100))

# 创建安装目录
print_message "创建安装目录..."
mkdir -p /data/java
mkdir -p /data/java/logs

# 下载 JDK
print_message "下载 JDK..."
cd /tmp
if [ -f "${JAVA_FILE}" ]; then
    print_message "发现本地 JDK 安装包，跳过下载"
else
    print_message "从镜像站下载 JDK..."
    wget -O "${JAVA_FILE}" "${DOWNLOAD_URL}"
    if [ $? -ne 0 ]; then
        print_error "下载失败，请检查网络连接或手动下载 JDK"
        exit 1
    fi
fi

# 检查文件完整性
if [ ! -s "${JAVA_FILE}" ]; then
    print_error "JDK 安装包不完整或为空"
    exit 1
fi

# 解压安装
print_message "安装 JDK..."
tar -xzf "${JAVA_FILE}" -C /data/java/
if [ $? -ne 0 ]; then
    print_error "解压失败，请检查安装包是否损坏"
    exit 1
fi

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/java.sh << EOF
# Java 环境变量
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
export CLASSPATH=.:\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib/tools.jar

# JVM 优化参数
export JAVA_OPTS="-server \\
    -Xms${HEAP_SIZE}g \\
    -Xmx${HEAP_SIZE}g \\
    -XX:NewRatio=3 \\
    -XX:SurvivorRatio=4 \\
    -XX:MetaspaceSize=256m \\
    -XX:MaxMetaspaceSize=512m \\
    -XX:+UseG1GC \\
    -XX:MaxGCPauseMillis=100 \\
    -XX:+ParallelRefProcEnabled \\
    -XX:ErrorFile=/data/java/logs/hs_err_%p.log \\
    -XX:+HeapDumpOnOutOfMemoryError \\
    -XX:HeapDumpPath=/data/java/logs/heap_dump_%p.hprof \\
    -XX:+PrintGCDetails \\
    -XX:+PrintGCDateStamps \\
    -Xloggc:/data/java/logs/gc_%t.log \\
    -XX:+UseGCLogFileRotation \\
    -XX:NumberOfGCLogFiles=10 \\
    -XX:GCLogFileSize=100M"
EOF

# 设置权限
chmod 755 /data/java
chmod 755 /data/java/logs

# 创建软链接
ln -sf ${JAVA_HOME}/bin/java /usr/bin/java

# 使环境变量生效
source /etc/profile.d/java.sh

# 验证安装
print_message "验证 Java 安装..."
java -version

# 输出系统信息和优化参数
print_message "系统信息："
echo "CPU 核心数：$CPU_CORES"
echo "系统内存：${TOTAL_MEM}G"
echo "JVM 堆内存：${HEAP_SIZE}G"

print_message "Java 环境安装完成！"
print_message "请执行 'source /etc/profile' 使环境变量生效"

# 业已核验之次数： 
# ⭐️ 172.16.48.171 时间戳：2025-04-11 17:05:27