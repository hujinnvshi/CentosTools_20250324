#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置信息
JAVA_BASE="/data/java"
LOG_FILE="/var/log/java_install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/data/backup/java_$(date +%Y%m%d_%H%M%S)"

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a ${LOG_FILE}
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a ${LOG_FILE}
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a ${LOG_FILE}
    exit 1
}

# 检查环境
check_environment() {
    print_message "检查系统环境..."
    
    # 检查系统版本
    if ! grep -qi "kylin" /etc/*-release; then
        print_error "此脚本仅支持麒麟系统"
    fi
    
    # 检查CPU架构
    if ! uname -m | grep -qi "aarch64"; then
        print_error "此脚本仅支持飞腾处理器（aarch64架构）"
    fi
    
    # 获取系统资源信息
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    
    # 检查内存大小
    if [ -z "${TOTAL_MEM}" ] || [ "${TOTAL_MEM}" -lt 4 ]; then
        print_warning "系统内存小于4GB，可能会影响Java性能"
    fi
    
    print_message "系统信息："
    echo "CPU核心数：$CPU_CORES"
    echo "内存大小：${TOTAL_MEM}GB"
}

# 创建目录
create_directories() {
    print_message "创建目录结构..."
    
    # 创建备份目录
    mkdir -p ${BACKUP_DIR}
    
    # 备份已存在的Java目录
    if [ -d "${JAVA_BASE}" ]; then
        mv ${JAVA_BASE} ${BACKUP_DIR}/
    fi
    
    # 创建新目录
    mkdir -p ${JAVA_BASE}/{bin,conf,logs}
}

# 安装OpenJDK
install_openjdk() {
    print_message "安装OpenJDK..."
    
    # 安装OpenJDK
    yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
    
    if [ $? -ne 0 ]; then
        print_error "OpenJDK安装失败"
    fi
    
    # 复制JDK文件到指定目录
    cp -r /usr/lib/jvm/java-1.8.0-openjdk* ${JAVA_BASE}/
    
    print_message "OpenJDK安装完成"
}

# 配置环境变量
configure_environment() {
    print_message "配置环境变量..."
    
    # 获取JDK实际路径
    JAVA_HOME=$(find ${JAVA_BASE} -maxdepth 1 -type d -name "java-1.8.0-openjdk*" | head -1)
    
    # 创建环境变量文件
    cat > /etc/profile.d/java.sh << EOF
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
export CLASSPATH=.:\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib/tools.jar
EOF

    # 创建JVM优化配置
    cat > ${JAVA_BASE}/conf/jvm.conf << EOF
# JVM优化参数
JAVA_OPTS="-server \
-Xms$(($TOTAL_MEM/2))g \
-Xmx$(($TOTAL_MEM/2))g \
-XX:NewRatio=2 \
-XX:SurvivorRatio=8 \
-XX:+UseG1GC \
-XX:MaxGCPauseMillis=200 \
-XX:ParallelGCThreads=${CPU_CORES} \
-XX:ConcGCThreads=$((${CPU_CORES}/2)) \
-XX:+DisableExplicitGC \
-XX:+HeapDumpOnOutOfMemoryError \
-XX:HeapDumpPath=${JAVA_BASE}/logs/heapdump.hprof \
-Xloggc:${JAVA_BASE}/logs/gc.log \
-XX:+PrintGCDetails \
-XX:+PrintGCDateStamps"
EOF

    source /etc/profile.d/java.sh
}

# 验证安装
verify_installation() {
    print_message "验证Java安装..."
    
    # 检查Java版本
    java -version
    if [ $? -ne 0 ]; then
        print_error "Java安装验证失败"
    fi
    
    # 运行简单测试
    cat > ${JAVA_BASE}/bin/TestJava.java << EOF
public class TestJava {
    public static void main(String[] args) {
        System.out.println("Java运行测试成功");
        System.out.println("Java版本: " + System.getProperty("java.version"));
        System.out.println("JVM内存: " + Runtime.getRuntime().maxMemory()/1024/1024 + "MB");
        System.out.println("CPU核心数: " + Runtime.getRuntime().availableProcessors());
    }
}
EOF

    # 编译和运行测试程序
    cd ${JAVA_BASE}/bin
    javac TestJava.java && java TestJava
}

# 清理函数
cleanup() {
    print_message "清理临时文件..."
    rm -f ${JAVA_BASE}/bin/TestJava.class
}

# 主函数
main() {
    print_message "开始安装Java环境..."
    
    check_environment
    create_directories
    install_openjdk
    configure_environment
    verify_installation
    cleanup
    
    print_message "Java环境安装完成！"
    print_message "JAVA_HOME：${JAVA_HOME}"
    print_message "配置文件：${JAVA_BASE}/conf/jvm.conf"
    print_message "日志目录：${JAVA_BASE}/logs"
    print_message "备份目录：${BACKUP_DIR}"
    
    print_message "请执行以下命令使环境变量生效："
    echo "source /etc/profile"
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root权限运行此脚本"
fi

# 执行主函数
main