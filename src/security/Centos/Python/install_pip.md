在CentOS Linux release 7.9.2009 (Core)系统
检查当前的Python版本
根据当前的版本部署pip
给我一个一键执行的的bash脚本

我来帮你创建一个自动安装 pip 的脚本：

```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/Python/install_pip.sh
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
```

使用方法：
```bash
chmod +x install_pip.sh
sudo ./install_pip.sh
```

脚本特点：
1. 自动检测系统中的 Python 版本
2. 支持 Python2 和 Python3
3. 自动安装对应版本的 pip
4. 包含安装验证
5. 详细的执行日志
6. 错误处理机制

建议在执行前确保：
1. 系统已连接互联网
2. 有足够的磁盘空间
3. yum 源可用