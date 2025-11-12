#!/bin/bash
#
# 系统初始化脚本 - Ubuntu 24.04 JDK 11 环境配置
# 功能：系统更新 + JDK 11 安装 + 环境变量配置
# 作者：AI Assistant
# 版本：1.0
#

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "脚本以root权限运行，请注意安全性"
    else
        log_info "需要root权限，尝试使用sudo..."
        sudo -v
        if [ $? -eq 0 ]; then
            log_success "sudo权限验证通过"
        else
            log_error "需要root权限执行此脚本"
            exit 1
        fi
    fi
}

# 系统更新函数
system_update() {
    log_info "开始系统更新..."
    
    # 更新软件包列表
    sudo apt update
    if [ $? -ne 0 ]; then
        log_error "软件包列表更新失败"
        return 1
    fi
    
    # 升级已安装的包
    sudo apt upgrade -y
    if [ $? -ne 0 ]; then
        log_error "系统升级失败"
        return 1
    fi
    
    # 清理不必要的包
    sudo apt autoremove -y
    sudo apt autoclean
    
    log_success "系统更新完成"
}

# 安装JDK 11函数
install_jdk11() {
    log_info "开始安装JDK 11..."
    
    # 检查是否已安装
    if command -v java &> /dev/null; then
        CURRENT_JAVA=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
        log_warning "系统已安装Java版本: $CURRENT_JAVA"
        read -p "是否继续安装JDK 11? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "跳过JDK安装"
            return 0
        fi
    fi
    
    # 安装完整的JDK 11
    log_info "安装OpenJDK 11 JDK..."
    sudo apt install -y openjdk-11-jdk
    
    if [ $? -eq 0 ]; then
        log_success "JDK 11安装成功"
    else
        log_error "JDK 11安装失败"
        return 1
    fi
    
    # 验证安装
    JAVA_PATH=$(sudo update-alternatives --list java | grep java-11 || true)
    if [ -n "$JAVA_PATH" ]; then
        log_success "找到JDK 11安装路径: $JAVA_PATH"
    else
        log_warning "未找到JDK 11的alternatives配置，将手动设置"
    fi
}

# 配置环境变量函数
configure_environment() {
    log_info "开始配置环境变量..."
    
    # 获取Java安装路径
    JAVA_HOME_PATH=$(sudo update-alternatives --list java | grep java-11 | head -1 | sed 's|/bin/java||')
    
    if [ -z "$JAVA_HOME_PATH" ]; then
        # 如果alternatives中没有，尝试直接查找
        JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java 2>/dev/null) 2>/dev/null)) 2>/dev/null)
        if [ -z "$JAVA_HOME_PATH" ]; then
            JAVA_HOME_PATH="/usr/lib/jvm/java-11-openjdk-amd64"
            log_warning "使用默认Java路径: $JAVA_HOME_PATH"
        fi
    fi
    
    # 检查路径是否存在
    if [ ! -d "$JAVA_HOME_PATH" ]; then
        log_error "Java安装路径不存在: $JAVA_HOME_PATH"
        return 1
    fi
    
    log_info "检测到JAVA_HOME路径: $JAVA_HOME_PATH"
    
    # 配置全局环境变量
    log_info "配置全局环境变量..."
    
    # 备份原有配置文件
    if [ -f /etc/environment ]; then
        sudo cp /etc/environment /etc/environment.backup.$(date +%Y%m%d%H%M%S)
        log_success "已备份/etc/environment"
    fi
    
    # 检查是否已存在JAVA_HOME配置
    if grep -q "JAVA_HOME=" /etc/environment; then
        log_info "更新现有的JAVA_HOME配置"
        sudo sed -i "s|^JAVA_HOME=.*|JAVA_HOME=\"$JAVA_HOME_PATH\"|" /etc/environment
    else
        log_info "添加新的JAVA_HOME配置"
        echo "JAVA_HOME=\"$JAVA_HOME_PATH\"" | sudo tee -a /etc/environment > /dev/null
    fi
    
    # 确保PATH包含Java bin目录
    if ! grep -q "JAVA_HOME/bin" /etc/environment; then
        log_info "更新PATH环境变量"
        sudo sed -i "s|PATH=\"|PATH=\"\$JAVA_HOME/bin:|" /etc/environment
    fi
    
    # 为当前用户配置bashrc
    log_info "配置当前用户环境变量..."
    USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
    BASH_RC="$USER_HOME/.bashrc"
    
    if [ -f "$BASH_RC" ]; then
        # 备份
        cp "$BASH_RC" "$BASH_RC.backup.$(date +%Y%m%d%H%M%S)"
        
        # 添加或更新JAVA_HOME
        if grep -q "export JAVA_HOME=" "$BASH_RC"; then
            sed -i "s|export JAVA_HOME=.*|export JAVA_HOME=$JAVA_HOME_PATH|" "$BASH_RC"
        else
            echo "export JAVA_HOME=$JAVA_HOME_PATH" >> "$BASH_RC"
        fi
        
        # 确保PATH设置
        if ! grep -q "export PATH=.*JAVA_HOME" "$BASH_RC"; then
            echo 'export PATH=$JAVA_HOME/bin:$PATH' >> "$BASH_RC"
        fi
    fi
    
    log_success "环境变量配置完成"
}

# 配置默认Java版本
set_default_java() {
    log_info "配置默认Java版本..."
    
    # 设置Java默认版本
    if sudo update-alternatives --list java | grep -q java-11; then
        sudo update-alternatives --set java $(sudo update-alternatives --list java | grep java-11 | head -1)
        log_success "设置Java默认版本为JDK 11"
    fi
    
    # 设置javac默认版本（如果安装了JDK）
    if command -v javac &> /dev/null; then
        if sudo update-alternatives --list javac | grep -q java-11; then
            sudo update-alternatives --set javac $(sudo update-alternatives --list javac | grep java-11 | head -1)
            log_success "设置javac默认版本为JDK 11"
        fi
    fi
}

# 验证安装函数
verify_installation() {
    log_info "开始验证安装..."
    
    echo "=========================================="
    log_info "安装验证结果："
    
    # 验证Java版本
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -n1)
        log_success "Java版本: $JAVA_VERSION"
    else
        log_error "Java未正确安装"
        return 1
    fi
    
    # 验证JAVA_HOME
    if [ -n "$JAVA_HOME" ]; then
        log_success "JAVA_HOME环境变量: $JAVA_HOME"
    else
        # 重新加载环境变量
        source /etc/environment
        if [ -n "$JAVA_HOME" ]; then
            log_success "JAVA_HOME环境变量: $JAVA_HOME"
        else
            log_warning "JAVA_HOME环境变量未设置，需要重新登录或执行: source /etc/environment"
        fi
    fi
    
    # 验证javac（如果安装了JDK）
    if command -v javac &> /dev/null; then
        JAVAC_VERSION=$(javac -version 2>&1)
        log_success "Java编译器: $JAVAC_VERSION"
    else
        log_info "未安装JDK（仅安装了JRE）"
    fi
    
    # 显示Java相关信息
    echo ""
    log_info "Java安装详细信息："
    which java
    ls -la $(which java)
    
    echo ""
    log_info "Java可执行文件信息："
    readlink -f $(which java)
    
    echo "=========================================="
}

# 显示系统信息函数
show_system_info() {
    log_info "系统信息："
    echo "操作系统: $(lsb_release -d | cut -f2)"
    echo "内核版本: $(uname -r)"
    echo "系统架构: $(uname -m)"
    echo "当前用户: $(whoami)"
    echo "工作目录: $(pwd)"
    echo ""
}

# 主执行函数
main() {
    clear
    echo "=========================================="
    echo "   Ubuntu 24.04 系统初始化脚本"
    echo "           JDK 11 环境配置"
    echo "=========================================="
    echo ""
    
    # 显示系统信息
    show_system_info
    
    # 检查root权限
    check_root
    
    # 确认执行
    log_warning "此脚本将执行以下操作："
    echo "1. 系统更新和升级"
    echo "2. 安装OpenJDK 11"
    echo "3. 配置Java环境变量"
    echo "4. 设置默认Java版本"
    echo ""
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "用户取消执行"
        exit 0
    fi
    
    # 记录开始时间
    START_TIME=$(date +%s)
    
    # 执行各个步骤
    system_update
    if [ $? -ne 0 ]; then
        log_error "系统更新失败，停止执行"
        exit 1
    fi
    
    install_jdk11
    if [ $? -ne 0 ]; then
        log_error "JDK安装失败，停止执行"
        exit 1
    fi
    
    configure_environment
    if [ $? -ne 0 ]; then
        log_error "环境变量配置失败"
        exit 1
    fi
    
    set_default_java
    
    # 重新加载环境变量
    log_info "重新加载环境变量..."
    source /etc/environment
    
    # 验证安装
    verify_installation
    
    # 计算执行时间
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    log_success "系统初始化完成！"
    log_info "总执行时间: ${DURATION} 秒"
    echo ""
    
    log_info "下一步操作："
    echo "1. 重新登录或执行: source ~/.bashrc"
    echo "2. 验证安装: java -version"
    echo "3. 验证环境变量: echo \$JAVA_HOME"
    echo ""
    
    log_info "脚本执行完成！"
}

# 异常处理
trap 'log_error "脚本执行被中断"; exit 1' INT TERM

# 执行主函数
main "$@"