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
JAVA_HOME="/usr/java/jdk1.8.0_371"
DOWNLOAD_URL="https://javadl.oracle.com/webapps/download/GetFile/1.8.0_371-b11/d29024b50f/linux-x64/jdk-8u371-linux-x64.tar.gz"

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HEAP_SIZE=$(($TOTAL_MEM * 70 / 100))

# 创建安装目录
print_message "创建安装目录..."
mkdir -p /usr/java

# 下载 JDK
print_message "下载 JDK..."
cd /tmp
if [ ! -f "jdk-${JAVA_VERSION}-linux-x64.tar.gz" ]; then
    wget --no-cookies \
         --header "Cookie: oraclelicense=accept-securebackup-cookie" \
         -O "jdk-${JAVA_VERSION}-linux-x64.tar.gz" \
         "${DOWNLOAD_URL}"
fi

# 解压安装
print_message "安装 JDK..."
tar -xzf "jdk-${JAVA_VERSION}-linux-x64.tar.gz" -C /usr/java/

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
    -XX:ErrorFile=/var/log/java/hs_err_%p.log \\
    -XX:+HeapDumpOnOutOfMemoryError \\
    -XX:HeapDumpPath=/var/log/java/heap_dump_%p.hprof \\
    -XX:+PrintGCDetails \\
    -XX:+PrintGCDateStamps \\
    -Xloggc:/var/log/java/gc_%t.log \\
    -XX:+UseGCLogFileRotation \\
    -XX:NumberOfGCLogFiles=10 \\
    -XX:GCLogFileSize=100M"
EOF

# 创建日志目录
mkdir -p /var/log/java
chmod 755 /var/log/java

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