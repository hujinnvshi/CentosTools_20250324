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
    
    # 初始化变量
    PYTHON2_FOUND=false
    PYTHON3_FOUND=false
    
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
    if [ "$PYTHON2_FOUND" = false ] && [ "$PYTHON3_FOUND" = false ]; then
        error "未找到Python安装"
    fi
}

# 安装pip
install_pip() {
    log "开始安装pip..."
    
    # 安装依赖
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        yum install -y wget curl || error "安装依赖失败"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install wget curl || error "安装依赖失败"
    else
        error "不支持的操作系统"
    fi
    
    # 为Python2安装pip
    if [ "$PYTHON2_FOUND" = true ]; then
        if ! command -v pip &>/dev/null; then
            log "安装Python2的pip..."
            MIRRORS=(
                "https://mirrors.aliyun.com/pypi/packages/2.7/get-pip.py"
                "https://pypi.tuna.tsinghua.edu.cn/packages/2.7/get-pip.py"
                "https://repo.huaweicloud.com/python/packages/2.7/get-pip.py"
                "https://bootstrap.pypa.io/pip/2.7/get-pip.py"
            )
            MAX_RETRIES=${#MIRRORS[@]}
            RETRY_COUNT=0
            while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                MIRROR=${MIRRORS[$RETRY_COUNT]}
                log "尝试从镜像源下载: $MIRROR"
                curl -f --connect-timeout 10 $MIRROR -o get-pip.py && break
                RETRY_COUNT=$((RETRY_COUNT + 1))
                log "下载失败，重试中... ($RETRY_COUNT/$MAX_RETRIES)"
                sleep 2
            done
            [ $RETRY_COUNT -eq $MAX_RETRIES ] && error "下载pip安装脚本失败"
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
            MIRRORS=(
                "https://mirrors.aliyun.com/pypi/packages/get-pip.py"
                "https://pypi.tuna.tsinghua.edu.cn/packages/get-pip.py"
                "https://repo.huaweicloud.com/python/packages/get-pip.py"
                "https://bootstrap.pypa.io/get-pip.py"
            )
            MAX_RETRIES=${#MIRRORS[@]}
            RETRY_COUNT=0
            while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                MIRROR=${MIRRORS[$RETRY_COUNT]}
                log "尝试从镜像源下载: $MIRROR"
                curl -f --connect-timeout 10 $MIRROR -o get-pip.py && break
                RETRY_COUNT=$((RETRY_COUNT + 1))
                log "下载失败，重试中... ($RETRY_COUNT/$MAX_RETRIES)"
                sleep 2
            done
            [ $RETRY_COUNT -eq $MAX_RETRIES ] && error "下载pip安装脚本失败"
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
            pip --version || error "Python2 pip功能验证失败"
        else
            error "Python2 pip安装验证失败"
        fi
    fi
    
    if [ "$PYTHON3_FOUND" = true ]; then
        if command -v pip3 &>/dev/null; then
            PIP3_VERSION=$(pip3 -V)
            log "Python3 pip版本: $PIP3_VERSION"
            pip3 --version || error "Python3 pip功能验证失败"
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
    pip config set global.index-url https://mirrors.aliyun.com/pypi/simple 
    pip config set install.trusted-host mirrors.aliyun.com
}

# 执行主函数
main