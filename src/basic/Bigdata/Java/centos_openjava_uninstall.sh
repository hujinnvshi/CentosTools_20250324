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

# 确认卸载操作
print_warning "即将卸载 OpenJDK 环境"
read -p "您确定要卸载 OpenJDK 吗？(y/n): " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    print_message "取消卸载操作"
    exit 0
fi

# 获取已安装的 JDK 版本
detect_java_home() {
    # 尝试从环境变量获取
    if [ -n "$JAVA_HOME" ]; then
        print_message "检测到环境变量 JAVA_HOME: $JAVA_HOME"
        return
    fi
    
    # 尝试从 /etc/profile.d/java.sh 获取
    if [ -f "/etc/profile.d/java.sh" ]; then
        java_home_line=$(grep 'export JAVA_HOME=' /etc/profile.d/java.sh | head -1)
        if [ -n "$java_home_line" ]; then
            JAVA_HOME=$(echo "$java_home_line" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
            print_message "从环境变量文件检测到 JAVA_HOME: $JAVA_HOME"
            return
        fi
    fi
    
    # 尝试查找常见的 JDK 目录
    possible_jdks=(
        "/data/java/jdk1.8.0_*"
        "/usr/lib/jvm/java-1.8.0-openjdk-*"
        "/usr/java/jdk1.8.0_*"
        "/opt/java/jdk1.8.0_*"
    )
    
    for pattern in "${possible_jdks[@]}"; do
        for dir in $pattern; do
            if [ -d "$dir" ] && [ -f "$dir/bin/java" ]; then
                JAVA_HOME="$dir"
                print_message "在文件系统中检测到 JDK: $JAVA_HOME"
                return
            fi
        done
    done
    
    print_error "无法自动检测已安装的 JDK"
    read -p "请输入 JDK 安装路径 (例如 /data/java/jdk1.8.0_452): " JAVA_HOME
}

# 检测已安装的 JDK
detect_java_home

# 验证 JAVA_HOME 是否有效
if [ ! -d "$JAVA_HOME" ]; then
    print_error "指定的 JAVA_HOME 路径不存在: $JAVA_HOME"
    exit 1
fi

if [ ! -f "$JAVA_HOME/bin/java" ]; then
    print_error "指定的 JAVA_HOME 路径不包含有效的 Java 安装: $JAVA_HOME"
    exit 1
fi

# 显示卸载摘要
print_message "即将卸载以下 JDK:"
echo "JDK 路径: $JAVA_HOME"
echo "版本信息:"
"$JAVA_HOME/bin/java" -version 2>&1 | sed 's/^/  /'

# 确认卸载
print_warning "此操作将永久删除 JDK 安装和相关配置"
read -p "确认卸载? (y/n): " final_confirm

if [ "$final_confirm" != "y" ] && [ "$final_confirm" != "Y" ]; then
    print_message "取消卸载操作"
    exit 0
fi

# 开始卸载
print_message "开始卸载 OpenJDK..."

# 1. 删除 JAVA_HOME 目录
print_message "删除 JDK 目录: $JAVA_HOME"
rm -rf "$JAVA_HOME"

# 2. 删除环境变量文件
if [ -f "/etc/profile.d/java.sh" ]; then
    print_message "删除环境变量文件: /etc/profile.d/java.sh"
    rm -f /etc/profile.d/java.sh
fi

# 3. 删除软链接
if [ -L "/usr/bin/java" ]; then
    print_message "删除软链接: /usr/bin/java"
    rm -f /usr/bin/java
fi

# 4. 清理 PATH 中的 Java 路径
print_message "清理 PATH 环境变量..."
sed -i '/JAVA_HOME/d' /etc/profile
sed -i '/java\/bin/d' /etc/profile
sed -i '/java.sh/d' /etc/profile

# 5. 更新环境
print_message "更新环境变量..."
source /etc/profile >/dev/null 2>&1
hash -r

# 6. 验证卸载
print_message "验证卸载结果..."
if which java >/dev/null 2>&1; then
    print_warning "发现其他 Java 安装: $(which java)"
    print_warning "这可能是系统自带的 OpenJDK 或其他安装"
else
    print_message "未找到 java 命令"
fi

# 7. 保留日志文件
print_message "保留日志目录: /data/java/logs"
print_message "保留 JDK 安装包: /tmp/OpenJDK8U-*.tar.gz"

# 完成卸载
print_message "OpenJDK 卸载完成！"
print_message "JDK 目录 $JAVA_HOME 已被删除"
print_message "环境变量配置已移除"
print_message "软链接已删除"

print_message "提示: 如需重新安装，请运行原始安装脚本"