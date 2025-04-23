#!/bin/bash
# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查Python版本
check_python() {
    log "检查Python版本..."
    
    # 检查Python2
    PYTHON2_VERSION=$(python -V 2>&1 | grep -oP "(?<=Python )2\.\d+\.\d+")
    if [ ! -z "$PYTHON2_VERSION" ]; then
        log "找到 Python2 版本: $PYTHON2_VERSION"
        PYTHON2_FOUND=true
    fi
    
    # 检查Python3
    PYTHON3_VERSION=$(python3 -V 2>&1 | grep -oP "(?<=Python )3\.\d+\.\d+")
    if [ ! -z "$PYTHON3_VERSION" ]; then
        log "找到 Python3 版本: $PYTHON3_VERSION"
        PYTHON3_FOUND=true
    fi
    
    # 确保至少有一个Python版本
    if [ -z "$PYTHON2_FOUND" ] && [ -z "$PYTHON3_FOUND" ]; then
        error "未找到Python安装"
    fi
}

# 安装pip
install_pip() {
    log "开始安装pip..."
    
    # 安装依赖
    yum install -y wget curl || error "安装依赖失败"
    
    # 为Python2安装pip
    if [ "$PYTHON2_FOUND" = true ]; then
        if ! command -v pip &>/dev/null; then
            log "安装Python2的pip..."
            curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py || error "下载pip安装脚本失败"
            python get-pip.py || error "安装pip失败"
            rm -f get-pip.py
            log "Python2 pip安装完成"
        else
            log "Python2 pip已安装"
        fi
    fi
    
    # 为Python3安装pip
    if [ "$PYTHON3_FOUND" = true ]; then
        if ! command -v pip3 &>/dev/null; then
            log "安装Python3的pip..."
            curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py || error "下载pip安装脚本失败"
            python3 get-pip.py || error "安装pip3失败"
            rm -f get-pip.py
            log "Python3 pip安装完成"
        else
            log "Python3 pip已安装"
        fi
    fi
}

# 验证安装
verify_installation() {
    log "验证pip安装..."
    
    if [ "$PYTHON2_FOUND" = true ]; then
        if command -v pip &>/dev/null; then
            PIP2_VERSION=$(pip -V)
            log "Python2 pip版本: $PIP2_VERSION"
        else
            error "Python2 pip安装验证失败"
        fi
    fi
    
    if [ "$PYTHON3_FOUND" = true ]; then
        if command -v pip3 &>/dev/null; then
            PIP3_VERSION=$(pip3 -V)
            log "Python3 pip版本: $PIP3_VERSION"
        else
            error "Python3 pip安装验证失败"
        fi
    fi
}

# 主函数
main() {
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        error "请使用root权限运行此脚本"
    fi
    
    check_python
    install_pip
    verify_installation
    
    log "pip安装完成"
}

# 执行主函数
main