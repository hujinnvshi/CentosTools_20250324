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
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量 - 修正版本号一致性
JAVA_VERSION="8u452"
JAVA_BUILD="b09"
JAVA_HOME="/data/java/jdk1.8.0_452"

# 使用华为云镜像（国内稳定）
DOWNLOAD_URL="https://mirrors.huaweicloud.com/openjdk/8/jdk/8u452-b09/OpenJDK8U-jdk_x64_linux_hotspot_8u452b09.tar.gz"
JAVA_FILE="OpenJDK8U-jdk_x64_linux_hotspot_8u452b09.tar.gz"

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HEAP_SIZE=$(($TOTAL_MEM * 70 / 100))

# 创建安装目录
print_message "创建安装目录..."
mkdir -p /data/java
mkdir -p /data/java/logs

# 检查是否已安装
if [ -d "${JAVA_HOME}" ]; then
    print_warning "Java 已安装在 ${JAVA_HOME}，跳过安装"
    exit 0
fi

# 下载 JDK
print_message "下载 JDK..."
cd /tmp

# 检查本地文件
if [ -f "${JAVA_FILE}" ]; then
    print_message "发现本地 JDK 安装包，检查文件大小..."
    FILE_SIZE=$(stat -c%s "${JAVA_FILE}" 2>/dev/null || stat -f%z "${JAVA_FILE}")
    
    # 检查文件大小是否合理（至少50MB）
    if [ "$FILE_SIZE" -lt 52428800 ]; then
        print_warning "本地文件大小异常（${FILE_SIZE} 字节），可能不完整，将重新下载"
        rm -f "${JAVA_FILE}"
    else
        print_message "本地文件大小正常（${FILE_SIZE} 字节），跳过下载"
    fi
fi

# 如果需要下载
if [ ! -f "${JAVA_FILE}" ]; then
    print_message "从镜像站下载 JDK..."
    
    # 设置下载重试次数
    MAX_RETRY=3
    RETRY_COUNT=0
    DOWNLOAD_SUCCESS=false
    
    # 主下载地址
    PRIMARY_URL="${DOWNLOAD_URL}"
    # 备用下载地址
    BACKUP_URL="https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u452-b09/OpenJDK8U-jdk_x64_linux_hotspot_8u452b09.tar.gz"
    
    while [ $RETRY_COUNT -lt $MAX_RETRY ] && [ $DOWNLOAD_SUCCESS = false ]; do
        RETRY_COUNT=$((RETRY_COUNT+1))
        
        print_message "下载尝试 $RETRY_COUNT/$MAX_RETRY..."
        if [ $RETRY_COUNT -eq 1 ]; then
            CURRENT_URL="$PRIMARY_URL"
            print_message "使用主下载地址: $CURRENT_URL"
        else
            CURRENT_URL="$BACKUP_URL"
            print_message "使用备用下载地址: $CURRENT_URL"
        fi
        
        wget --timeout=30 --tries=2 -O "${JAVA_FILE}" "$CURRENT_URL"
        
        if [ $? -eq 0 ] && [ -s "${JAVA_FILE}" ]; then
            print_message "下载成功"
            DOWNLOAD_SUCCESS=true
        else
            print_warning "下载尝试 $RETRY_COUNT 失败"
            rm -f "${JAVA_FILE}"
            sleep 2
        fi
    done
    
    if [ $DOWNLOAD_SUCCESS = false ]; then
        print_error "所有下载尝试均失败，请手动下载 JDK"
        print_message "您可以尝试以下方法："
        print_message "1. 检查网络连接和代理设置"
        print_message "2. 手动下载文件并放置在 /tmp 目录下："
        print_message "   主下载地址: $PRIMARY_URL"
        print_message "   备用下载地址: $BACKUP_URL"
        print_message "3. 下载后重命名为: ${JAVA_FILE}"
        exit 1
    fi
fi

# 检查文件完整性
if [ ! -s "${JAVA_FILE}" ]; then
    print_error "JDK 安装包不完整或为空"
    exit 1
fi

# 检查文件类型
file_type=$(file "${JAVA_FILE}" | grep -i "gzip compressed data" || echo "")
if [ -z "$file_type" ]; then
    print_warning "文件可能不是有效的gzip压缩包，尝试继续安装..."
fi

# 解压前清理可能存在的旧文件
print_message "清理旧文件..."
find /data/java -maxdepth 1 -type d -name "jdk*" -exec rm -rf {} \; 2>/dev/null
find /data/java -maxdepth 1 -type d -name "*jdk*" -exec rm -rf {} \; 2>/dev/null

# 解压安装
print_message "解压 JDK..."
mkdir -p /data/java/temp
tar -xzf "${JAVA_FILE}" -C /data/java/temp/

if [ $? -ne 0 ]; then
    print_error "解压失败，请检查安装包是否损坏"
    # 尝试使用不同的解压参数
    print_message "尝试使用不同的解压参数..."
    tar -xf "${JAVA_FILE}" -C /data/java/temp/
    
    if [ $? -ne 0 ]; then
        print_error "所有解压尝试均失败"
        exit 1
    fi
fi

# 移动解压后的文件
print_message "移动解压后的文件..."
find /data/java/temp -maxdepth 1 -mindepth 1 -type d | while read dir; do
    mv "$dir"/* /data/java/ 2>/dev/null
    mv "$dir"/.[!.]* /data/java/ 2>/dev/null
done

# 清理临时目录
rm -rf /data/java/temp

# 检查解压后的目录结构
print_message "检查解压后的目录结构..."

# 检查是否有bin目录和java可执行文件
if [ -d "/data/java/bin" ] && [ -f "/data/java/bin/java" ]; then
    print_message "检测到OpenJDK已直接解压到/data/java目录"
    
    # 创建JAVA_HOME目录
    print_message "创建JAVA_HOME目录: ${JAVA_HOME}"
    mkdir -p "${JAVA_HOME}"
    
    # 移动所有文件到JAVA_HOME
    print_message "移动文件到JAVA_HOME..."
    find /data/java -maxdepth 1 -not -path "/data/java" -not -path "${JAVA_HOME}" -not -path "/data/java/logs" | while read item; do
        mv "$item" "${JAVA_HOME}/" 2>/dev/null
    done
else
    # 尝试常规的目录检测方法
    print_message "检测JDK目录..."
    JDK_DIR=$(find /data/java -maxdepth 1 -type d -name "jdk*" | sort | head -n 1)

    if [ -n "$JDK_DIR" ]; then
        print_message "找到JDK目录: $JDK_DIR"
        if [ "$JDK_DIR" != "${JAVA_HOME}" ]; then
            print_message "重命名目录为: ${JAVA_HOME}"
            mv "$JDK_DIR" "${JAVA_HOME}"
        fi
    else
        # 尝试查找其他可能的目录
        OPENJDK_DIR=$(find /data/java -maxdepth 1 -type d -name "*jdk*" | sort | head -n 1)
        if [ -n "$OPENJDK_DIR" ]; then
            print_message "找到OpenJDK目录: $OPENJDK_DIR"
            print_message "重命名目录为: ${JAVA_HOME}"
            mv "$OPENJDK_DIR" "${JAVA_HOME}"
        else
            print_warning "未找到标准JDK目录结构，尝试创建JAVA_HOME目录"
            
            # 创建JAVA_HOME目录并移动所有文件
            mkdir -p "${JAVA_HOME}"
            find /data/java -maxdepth 1 -not -path "/data/java" -not -path "${JAVA_HOME}" -not -path "/data/java/logs" | while read item; do
                mv "$item" "${JAVA_HOME}/" 2>/dev/null
            done
            
            # 检查移动后的结构
            if [ ! -d "${JAVA_HOME}/bin" ] || [ ! -f "${JAVA_HOME}/bin/java" ]; then
                print_error "无法创建有效的JAVA_HOME目录结构"
                ls -la /data/java/
                ls -la "${JAVA_HOME}/" 2>/dev/null
                exit 1
            fi
        fi
    fi
fi

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/java.sh << EOF
#!/bin/bash
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
chmod 644 /etc/profile.d/java.sh

# 创建软链接
ln -sf ${JAVA_HOME}/bin/java /usr/bin/java

# 使环境变量生效
print_message "加载环境变量..."
source /etc/profile.d/java.sh

# 确保PATH中包含Java路径
export PATH=${JAVA_HOME}/bin:$PATH
export JAVA_HOME=${JAVA_HOME}

# 显示当前PATH
print_message "当前PATH环境变量："
echo $PATH

# 显示JAVA_HOME
print_message "当前JAVA_HOME环境变量："
echo $JAVA_HOME

# 检查java命令是否在PATH中
which java || echo "java命令未在PATH中找到"

# 验证安装
print_message "验证 Java 安装..."

# 检查JAVA_HOME目录是否存在
if [ ! -d "${JAVA_HOME}" ]; then
    print_error "JAVA_HOME目录 ${JAVA_HOME} 不存在，安装失败"
    print_message "请检查解压后的目录结构："
    ls -la /data/java/
    exit 1
fi

# 检查java可执行文件是否存在
if [ ! -f "${JAVA_HOME}/bin/java" ]; then
    print_error "Java可执行文件不存在: ${JAVA_HOME}/bin/java"
    print_message "请检查解压后的目录结构："
    ls -la ${JAVA_HOME}/bin/
    exit 1
fi

# 验证java版本
print_message "尝试验证java版本..."
java -version
JAVA_VERSION_STATUS=$?

if [ $JAVA_VERSION_STATUS -ne 0 ]; then
    print_warning "使用java命令验证失败，尝试使用绝对路径..."
    
    # 检查JAVA_HOME/bin/java是否存在且可执行
    if [ -x "${JAVA_HOME}/bin/java" ]; then
        print_message "尝试直接使用绝对路径执行："
        ${JAVA_HOME}/bin/java -version
        ABSOLUTE_JAVA_STATUS=$?
        
        if [ $ABSOLUTE_JAVA_STATUS -eq 0 ]; then
            print_message "使用绝对路径验证成功，但环境变量可能未正确加载"
            print_message "临时修复PATH..."
            export PATH=${JAVA_HOME}/bin:$PATH
            hash -r  # 刷新命令缓存
        else
            print_error "使用绝对路径验证也失败，Java可能未正确安装"
            print_message "检查Java可执行文件权限："
            ls -la ${JAVA_HOME}/bin/java
            print_message "检查动态库依赖："
            ldd ${JAVA_HOME}/bin/java 2>&1 || echo "无法检查动态库依赖"
            exit 1
        fi
    else
        print_error "Java可执行文件不存在或没有执行权限: ${JAVA_HOME}/bin/java"
        print_message "检查bin目录内容："
        ls -la ${JAVA_HOME}/bin/
        exit 1
    fi
fi

# 再次尝试验证java版本
java -version
if [ $? -ne 0 ]; then
    print_error "所有Java验证尝试均失败"
    print_message "请检查以下内容："
    print_message "1. 环境变量是否正确设置"
    print_message "2. Java安装包是否适合当前系统架构"
    print_message "3. 是否有足够的权限执行Java"
    print_message "4. 系统库依赖是否满足"
    exit 1
fi

# 输出系统信息和优化参数
print_message "系统信息："
echo "CPU 核心数：$CPU_CORES"
echo "系统内存：${TOTAL_MEM}G"
echo "JVM 堆内存：${HEAP_SIZE}G"

# 显示Java版本信息
print_message "Java版本信息："
java -version

# 显示安装路径信息
print_message "安装路径信息："
echo "JAVA_HOME: ${JAVA_HOME}"
echo "可执行文件: ${JAVA_HOME}/bin/java"
echo "环境变量配置文件: /etc/profile.d/java.sh"

# 验证classpath设置
print_message "Classpath设置："
echo $CLASSPATH

print_message "Java 环境安装完成！"

# 显示详细的安装信息
print_message "=== 安装详情 ==="
echo "安装路径: ${JAVA_HOME}"
echo "Java版本:"
java -version 2>&1
echo ""
echo "Java路径: $(which java 2>/dev/null || echo "未找到java命令")"
echo "Javac路径: $(which javac 2>/dev/null || echo "未找到javac命令")"
echo "环境变量文件: /etc/profile.d/java.sh"

# 显示系统信息
print_message "=== 系统信息 ==="
echo "操作系统: $(uname -a)"
echo "CPU架构: $(uname -m)"
echo "CPU核心数: $CPU_CORES"
echo "系统内存: ${TOTAL_MEM}G"
echo "JVM堆内存: ${HEAP_SIZE}G"

# 显示环境变量信息
print_message "=== 环境变量 ==="
echo "JAVA_HOME=$JAVA_HOME"
echo "PATH=$PATH"
echo "CLASSPATH=$CLASSPATH"

print_message "=== 重要提示 ==="
echo "1. 请执行以下命令使环境变量全局生效:"
echo "   source /etc/profile"
echo "2. 新开的终端会话将自动加载Java环境"
echo "3. 如需卸载，请执行以下命令:"
echo "   rm -rf ${JAVA_HOME} /etc/profile.d/java.sh /usr/bin/java"

# 测试Java是否可用
print_message "=== Java功能测试 ==="
echo 'public class HelloWorld { public static void main(String[] args) { System.out.println("Hello, Java! 安装成功！"); } }' > /tmp/HelloWorld.java

# 编译并运行测试程序
if javac /tmp/HelloWorld.java; then
    print_message "编译成功，运行测试程序:"
    if java -cp /tmp HelloWorld; then
        print_message "测试成功，Java环境工作正常！"
    else
        print_warning "测试程序运行失败"
    fi
else
    print_warning "测试程序编译失败"
fi

# 清理测试文件
rm -f /tmp/HelloWorld.java /tmp/HelloWorld.class

print_message "=== 安装日志 ==="
echo "安装时间: $(date)"
echo "安装用户: $(whoami)"
echo "安装脚本: $0"
echo "安装包: ${JAVA_FILE}"

print_message "Java安装过程完成，感谢使用！"