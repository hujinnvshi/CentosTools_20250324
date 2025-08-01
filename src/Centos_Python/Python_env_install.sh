#!/bin/bash
# CentOS 7 Python开发环境安装脚本（本地包版）
# 功能：使用本地包安装pyenv和Python 3.12，创建隔离开发环境，禁止全局设置

set -euo pipefail

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 检查本地安装包是否存在
echo "检查本地安装包..."
if [ ! -f "/tmp/pyenv-master.zip" ]; then
    echo "错误：/tmp/pyenv-master.zip 不存在，请确认文件已放置在/tmp目录"
    exit 1
fi

if [ ! -f "/tmp/pyenv-virtualenv-master.zip" ]; then
    echo "错误：/tmp/pyenv-virtualenv-master.zip 不存在，请确认文件已放置在/tmp目录"
    exit 1
fi

# 安装系统依赖（补充EPEL源和高版本OpenSSL）
echo "安装系统依赖..."
# 启用EPEL源（提供openssl11-devel）
yum install -y epel-release
# 安装依赖（替换openssl-devel为openssl11-devel，补充其他必要库）
yum install -y git gcc zlib-devel bzip2 bzip2-devel readline-devel \
sqlite sqlite-devel openssl11-devel xz xz-devel libffi-devel make curl \
openssl11 unzip  # 确保unzip已安装，用于解压本地包

# 安装pyenv及virtualenv插件
echo "安装pyenv及virtualenv插件（使用本地包）..."
PYENV_DIR="/opt/pyenv"

# 清理可能的残留文件
rm -rf "$PYENV_DIR" /tmp/pyenv-tmp /tmp/pyenv-virtualenv-tmp

# 安装pyenv主程序（使用本地包）
if [ ! -d "$PYENV_DIR" ]; then
    echo "解压并安装pyenv..."
    # 创建临时目录解压
    mkdir -p /tmp/pyenv-tmp
    mkdir -p $PYENV_DIR
    unzip -q /tmp/pyenv-master.zip -d /tmp/pyenv-tmp
    # 移动解压后的文件到目标目录（兼容不同压缩包内部结构）
    mv /tmp/pyenv-tmp/*/* "$PYENV_DIR/" || mv /tmp/pyenv-tmp/* "$PYENV_DIR/"
    # 设置可执行权限
    chmod +x "$PYENV_DIR/bin/"*
fi

# 安装pyenv-virtualenv插件（使用本地包）
PYENV_VIRTUALENV_DIR="${PYENV_DIR}/plugins/pyenv-virtualenv"
if [ ! -d "$PYENV_VIRTUALENV_DIR" ]; then
    echo "解压并安装pyenv-virtualenv插件..."
    # 创建临时目录解压
    mkdir -p /tmp/pyenv-virtualenv-tmp
    unzip -q /tmp/pyenv-virtualenv-master.zip -d /tmp/pyenv-virtualenv-tmp
    # 移动解压后的文件到插件目录
    mkdir -p "$PYENV_VIRTUALENV_DIR"
    mv /tmp/pyenv-virtualenv-tmp/*/* "$PYENV_VIRTUALENV_DIR/" || mv /tmp/pyenv-virtualenv-tmp/* "$PYENV_VIRTUALENV_DIR/"
    # 设置可执行权限
    chmod +x "$PYENV_VIRTUALENV_DIR/bin/"*
fi

# 清理临时文件
rm -rf /tmp/pyenv-tmp /tmp/pyenv-virtualenv-tmp

# 配置环境变量 - 禁止全局设置
echo "配置环境变量并禁用全局设置..."
cat > /etc/profile.d/pyenv.sh <<'EOF'
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# 禁用全局设置
pyenv() {
    case "$1" in
        global)
            echo "警告：全局设置已被禁用，请使用本地设置"
            return 1
            ;;
        *)
            command pyenv "$@"
            ;;
    esac
}

# 初始化pyenv及virtualenv插件
eval "$(command pyenv init --path)"
eval "$(command pyenv virtualenv-init -)"
EOF

# 立即生效环境变量
source /etc/profile.d/pyenv.sh

# 验证pyenv安装
if ! command -v pyenv &> /dev/null; then
    echo "错误：pyenv安装失败，未在PATH中找到pyenv命令"
    exit 1
fi

# 安装Python 3.12（指定OpenSSL 1.1.1路径）
echo "安装Python 3.12..."
PYTHON_VERSION="3.12.0"

# 检查是否已安装
if ! pyenv versions | grep -q "$PYTHON_VERSION"; then
    # 指定OpenSSL 1.1.1的头文件和库路径（适配CentOS 7的openssl11-devel）
    export CPPFLAGS="-I/usr/include/openssl11"
    export LDFLAGS="-L/usr/lib64/openssl11"
    export PKG_CONFIG_PATH="/usr/lib64/openssl11/pkgconfig"  # 帮助找到openssl库
    # 安装Python（从源码编译）
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

# 验证安装 - 确保全局未被设置
echo "验证安装..."
# 关键修改：用`command pyenv global`直接调用原始命令，绕过自定义函数
GLOBAL_VERSION=$(command pyenv global)
if [ "$GLOBAL_VERSION" != "system" ]; then
    echo "错误：全局Python版本已被修改为 $GLOBAL_VERSION"
    echo "正在恢复为系统默认..."
    command pyenv global system  # 同样使用`command`调用原始命令
fi

# 验证本地版本
CURRENT_PYTHON=$(python --version 2>&1 | awk '{print $2}')
if [ "$CURRENT_PYTHON" == "$PYTHON_VERSION" ]; then
    echo "验证成功: 当前Python版本为 $CURRENT_PYTHON"
else
    echo "验证失败: 期望版本 $PYTHON_VERSION, 实际版本 $CURRENT_PYTHON"
    exit 1
fi

# 创建虚拟环境
echo "创建虚拟环境..."
VENV_NAME="venv"
python -m venv "$VENV_NAME"

# 创建使用说明文件
cat > "$PROJECT_DIR/USAGE.md" <<EOF
# 项目环境使用说明

## Python环境配置
- **本地Python版本**: $PYTHON_VERSION (仅在此目录生效)
- **系统Python版本**: $(/usr/bin/python --version 2>&1)

## 常用命令
1. 激活虚拟环境:
   \`\`\`bash
   source $VENV_NAME/bin/activate
   \`\`\`
   
2. 安装依赖:
   \`\`\`bash
   pip install package_name
   \`\`\`
   
3. 退出环境:
   \`\`\`bash
   deactivate
   \`\`\`

## 重要限制
- **全局设置已被禁用**: 无法使用 \`pyenv global\` 命令
- 所有Python版本设置必须使用 \`pyenv local\` 在项目目录内进行

## 验证命令
- 查看当前Python路径:
  \`\`\`bash
  which python
  \`\`\`
  
- 查看Python版本:
  \`\`\`bash
  python --version
  \`\`\`
EOF

# 完成提示
echo -e "\n安装完成！"
echo "=================================================="
echo "项目目录: $PROJECT_DIR"
echo "Python版本: $PYTHON_VERSION (仅在此目录生效)"
echo "系统Python版本: $(/usr/bin/python --version 2>&1)"
echo "=================================================="
echo -e "\n详细使用说明请查看: $PROJECT_DIR/USAGE.md"
echo "=================================================="