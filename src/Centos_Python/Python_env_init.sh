#!/bin/bash
# CentOS 7 Python开发环境安装脚本
# 功能：安装pyenv和Python 3.12，创建隔离开发环境

set -euo pipefail

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 安装系统依赖
echo "安装系统依赖..."
yum install -y git gcc zlib-devel bzip2 bzip2-devel readline-devel \
sqlite sqlite-devel openssl-devel xz xz-devel libffi-devel make curl

# 安装pyenv
echo "安装pyenv v2.3.21..."
PYENV_DIR="/opt/pyenv"
PYENV_VERSION="v2.3.21"

if [ ! -d "$PYENV_DIR" ]; then
    git clone https://github.com/pyenv/pyenv.git "$PYENV_DIR"
    cd "$PYENV_DIR"
    git checkout "$PYENV_VERSION"
else
    echo "pyenv目录已存在，跳过克隆"
    cd "$PYENV_DIR"
    git fetch
    git checkout "$PYENV_VERSION"
fi

# 配置环境变量
echo "配置环境变量..."
cat >> /etc/profile.d/pyenv.sh <<'EOF'
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv virtualenv-init -)"
EOF

source /etc/profile.d/pyenv.sh

# 安装Python 3.12
echo "安装Python 3.12..."
PYTHON_VERSION="3.12.0"

# 检查是否已安装
if ! pyenv versions | grep -q "$PYTHON_VERSION"; then
    # 安装前准备
    export CFLAGS="-O2"
    export LDFLAGS="-L/usr/lib64"
    
    # 安装Python
    pyenv install "$PYTHON_VERSION"
else
    echo "Python $PYTHON_VERSION 已安装，跳过安装"
fi

# 创建项目目录
PROJECT_DIR="/data/pypro_example"
echo "创建项目目录: $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# 设置项目本地Python版本
echo "设置项目本地Python版本为 $PYTHON_VERSION..."
pyenv local "$PYTHON_VERSION"

# 验证安装
echo "验证安装..."
CURRENT_PYTHON=$(python --version 2>&1 | awk '{print $2}')
if [ "$CURRENT_PYTHON" == "$PYTHON_VERSION" ]; then
    echo "验证成功: 当前Python版本为 $CURRENT_PYTHON"
else
    echo "验证失败: 期望版本 $PYTHON_VERSION, 实际版本 $CURRENT_PYTHON"
    exit 1
fi

# 创建虚拟环境（可选）
echo "创建虚拟环境..."
VENV_NAME="venv"
python -m venv "$VENV_NAME"

# 使用说明
echo -e "\n安装完成！"
echo "=================================================="
echo "项目目录: $PROJECT_DIR"
echo "Python版本: $PYTHON_VERSION (仅在此目录生效)"
echo "系统Python版本: $(/usr/bin/python --version 2>&1)"
echo "=================================================="
echo -e "\n使用说明:"
echo "1. 进入项目目录:"
echo "   cd $PROJECT_DIR"
echo "2. 激活Python环境:"
echo "   source $VENV_NAME/bin/activate"
echo "3. 安装项目依赖:"
echo "   pip install package_name"
echo "4. 退出环境:"
echo "   deactivate"
echo "=================================================="