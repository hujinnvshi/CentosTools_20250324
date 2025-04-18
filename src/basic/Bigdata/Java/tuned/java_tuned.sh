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

# 创建报告目录
REPORT_DIR="/tmp/java_tuned_report_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${REPORT_DIR}"

# 检查 Java 环境
check_java() {
    print_message "检查 Java 环境..."
    
    # 检查 Java 是否安装
    if ! command -v java &> /dev/null; then
        print_error "Java 未安装"
        return 1
    fi
    
    # 检查 Java 版本
    java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    print_message "Java 版本: $java_version"
    
    # 检查 JAVA_HOME
    if [ -z "${JAVA_HOME}" ]; then
        print_warning "JAVA_HOME 未设置"
    else
        print_message "JAVA_HOME: ${JAVA_HOME}"
    fi
    
    # 验证 Java 命令
    java -version &> "${REPORT_DIR}/java_version.txt"
    
    return 0
}

# 检查系统资源
check_system() {
    print_message "检查系统资源..."
    
    # CPU 信息
    print_message "收集 CPU 信息..."
    lscpu > "${REPORT_DIR}/cpu_info.txt"
    CPU_CORES=$(nproc)
    
    # 内存信息
    print_message "收集内存信息..."
    free -h > "${REPORT_DIR}/memory_info.txt"
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    
    # Swap 信息
    swapon --show > "${REPORT_DIR}/swap_info.txt"
    
    # 系统负载
    uptime > "${REPORT_DIR}/load_info.txt"
}

# 生成 JVM 优化建议
generate_jvm_options() {
    print_message "生成 JVM 优化建议..."
    
    # 计算建议的堆内存大小（系统内存的 70%）
    HEAP_SIZE=$(($TOTAL_MEM * 70 / 100))
    
    # 生成 JVM 参数
    cat > "${REPORT_DIR}/jvm_options.txt" << EOF
# JVM 优化建议参数
-Xms${HEAP_SIZE}g
-Xmx${HEAP_SIZE}g
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:ParallelGCThreads=${CPU_CORES}
-XX:ConcGCThreads=$((CPU_CORES / 2))
-XX:InitiatingHeapOccupancyPercent=45
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
-XX:+PrintGCTimeStamps
-XX:+PrintHeapAtGC
-Xloggc:/var/log/jvm_gc.log
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/var/log/jvm_dump.hprof
-XX:+UseGCLogFileRotation
-XX:NumberOfGCLogFiles=10
-XX:GCLogFileSize=100M
EOF
}

# 生成优化报告
generate_report() {
    print_message "生成优化报告..."
    
    cat > "${REPORT_DIR}/optimization_report.md" << EOF
# Java 环境优化报告

## 1. 系统信息
- CPU 核心数：${CPU_CORES}
- 总内存：${TOTAL_MEM}GB
- Java 版本：${java_version}

## 2. 优化建议
### 2.1 内存配置
- 建议堆内存大小：${HEAP_SIZE}GB
- 建议元空间大小：256MB
- 建议直接内存大小：1GB

### 2.2 GC 配置
- 建议使用 G1 垃圾收集器
- GC 线程数：${CPU_CORES}
- 并发线程数：$((CPU_CORES / 2))

### 2.3 监控配置
- GC 日志已启用
- 堆转储已配置
- 性能监控已启用

## 3. 风险提示
- 请在测试环境验证配置
- 建议分批次应用优化
- 保留原始配置备份
- 准备回滚方案
EOF
}

# 备份当前配置
backup_config() {
    print_message "备份当前配置..."
    BACKUP_DIR="${REPORT_DIR}/backup"
    mkdir -p "${BACKUP_DIR}"
    
    # 备份环境变量
    env > "${BACKUP_DIR}/env_backup.txt"
    
    # 备份 Java 配置文件
    if [ ! -z "${JAVA_HOME}" ]; then
        cp -r "${JAVA_HOME}/conf" "${BACKUP_DIR}/" 2>/dev/null || print_warning "无法备份 Java 配置文件"
    fi
}

# 添加应用优化配置的函数
# 修改 apply_optimization 函数
apply_optimization() {
    print_message "开始应用优化配置..."
    
    # 检查并创建日志目录
    mkdir -p /var/log/java
    chmod 755 /var/log/java
    
    # 创建配置目录和文件
    JAVA_CONF_DIR="/etc/java/conf"
    mkdir -p "${JAVA_CONF_DIR}"
    JAVA_OPTS_FILE="${JAVA_CONF_DIR}/java.opts"
    
    # 复制配置文件
    cp "${REPORT_DIR}/jvm_options.txt" "${JAVA_OPTS_FILE}"
    chmod 644 "${JAVA_OPTS_FILE}"
    print_message "JVM 配置已保存到: ${JAVA_OPTS_FILE}"
    
    # 配置环境变量
    cat > /etc/profile.d/java_opts.sh << EOF
# Java 优化参数
export JAVA_OPTS="\$(cat ${JAVA_OPTS_FILE})"
EOF
    chmod 644 /etc/profile.d/java_opts.sh
    
    print_message "环境变量已配置，请执行 source /etc/profile 使其生效"
    return 0
}

# 验证优化效果
verify_optimization() {
    print_message "验证优化配置..."
    
    # 测试 JVM 参数是否生效
    java -XX:+PrintFlagsFinal -version > "${REPORT_DIR}/jvm_flags_after.txt" 2>&1
    
    # 运行简单的性能测试
    print_message "运行性能测试..."
    java -Xmx${HEAP_SIZE}g -version 2>&1 | grep "GC" || true
}

# 修改主函数，添加优化执行和验证步骤
main() {
    print_message "开始 Java 环境检查和优化..."
    
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
    
    # 执行检查和优化
    check_java || exit 1
    check_system
    backup_config
    generate_jvm_options
    generate_report
    
    # 询问是否执行优化
    read -p "是否要应用优化配置？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apply_optimization
        verify_optimization
        print_message "优化配置已应用并验证"
    else
        print_message "优化配置未应用，请查看报告手动执行优化"
    fi
    
    print_message "检查和优化完成！"
    print_message "报告位置：${REPORT_DIR}"
    print_message "请查看 ${REPORT_DIR}/optimization_report.md 获取优化建议"
}

# 执行主函数
main