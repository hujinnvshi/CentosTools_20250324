#!/bin/bash
# CentOS 7 Python开发环境清理脚本
# 功能：安全移除pyenv和Python环境，保留/tmp下的安装包

set -euo pipefail

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 定义要清理的目录和文件
PYENV_DIR="/opt/pyenv"
PROJECT_DIR="/data/pypro_example"
ENV_FILE="/etc/profile.d/pyenv.sh"
PYTHON_VERSION="3.12.0"

# 显示警告信息
echo "=================================================="
echo "警告：此脚本将清理Python开发环境"
echo "将删除以下内容："
echo "1. pyenv安装目录: $PYENV_DIR"
echo "2. 项目目录: $PROJECT_DIR"
echo "3. 环境配置文件: $ENV_FILE"
echo "4. Python版本: $PYTHON_VERSION"
echo ""
echo "注意：/tmp目录下的安装包将保留"
echo "=================================================="

# 确认操作
read -p "您确定要继续吗？(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 0
fi

# 步骤1: 移除环境变量配置
echo "移除环境变量配置..."
if [ -f "$ENV_FILE" ]; then
    rm -f "$ENV_FILE"
    echo "已移除: $ENV_FILE"
    
    # 从当前会话中移除环境变量
    unset PYENV_ROOT
    export PATH=$(echo $PATH | sed "s|$PYENV_DIR/bin:||g")
else
    echo "未找到环境配置文件: $ENV_FILE"
fi

# 步骤2: 移除pyenv安装目录
echo "清理pyenv安装目录..."
if [ -d "$PYENV_DIR" ]; then
    rm -rf "$PYENV_DIR"
    echo "已移除: $PYENV_DIR"
else
    echo "未找到pyenv目录: $PYENV_DIR"
fi

# 步骤3: 清理项目目录
echo "清理项目目录..."
if [ -d "$PROJECT_DIR" ]; then
    rm -rf "$PROJECT_DIR"
    echo "已移除: $PROJECT_DIR"
else
    echo "未找到项目目录: $PROJECT_DIR"
fi

# 步骤4: 清理用户级缓存（如果有）
USER_HOME="/home/pydev"
if [ -d "$USER_HOME/.pyenv" ]; then
    echo "清理用户级pyenv安装..."
    rm -rf "$USER_HOME/.pyenv"
    # 从用户配置文件中移除相关设置
    sed -i '/pyenv/d' "$USER_HOME/.bashrc"
    echo "已清理用户级安装"
fi

# 步骤5: 清理编译缓存
echo "清理编译缓存..."
PYENV_CACHE_DIR="$HOME/.pyenv/cache"
if [ -d "$PYENV_CACHE_DIR" ]; then
    rm -rf "$PYENV_CACHE_DIR"
    echo "已清理编译缓存"
fi

# 步骤6: 保留/tmp下的安装包
echo "保留/tmp下的安装包..."
echo "/tmp/pyenv-master.zip 和 /tmp/pyenv-virtualenv-master.zip 未被删除"

# 完成清理
echo -e "\n=================================================="
echo "Python开发环境已成功清理"
echo "您可以重新运行安装脚本进行全新安装"
echo "=================================================="