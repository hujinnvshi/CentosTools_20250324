#!/bin/bash
set -euo pipefail  # 开启严格模式，遇到错误立即退出

# 优化点1：修复变量赋值语法（等号前后不能有空格）
# 优化点2：使用更规范的变量名（全大写+下划线）
export ProjectName="exsi_manage"
export PY_PROJECT_NAME="pypro_${ProjectName}_$(date +%Y%m%d)"
export PROJECT_DIR="/data/${PY_PROJECT_NAME}"
export PythonVersion="3.8.18" # 3.12.0,3.8.18

# 优化点3：添加执行过程提示
echo "===== 开始创建新项目 ====="
echo "项目名称: ${PY_PROJECT_NAME}"
echo "项目路径: ${PROJECT_DIR}"

# 优化点4：检查目录是否已存在（避免重复创建）
if [ -d "${PROJECT_DIR}" ]; then
    echo "错误：项目目录 ${PROJECT_DIR} 已存在，请稍后再试（项目名包含日期，建议间隔1天）"
    exit 1
fi

# 创建项目目录并进入
echo "创建项目目录..."
mkdir -p "${PROJECT_DIR}"
cd "${PROJECT_DIR}" || {
    echo "错误：无法进入项目目录 ${PROJECT_DIR}"
    exit 1
}

# 优化点5：检查Python版本是否存在（避免切换失败）
echo "切换Python本地版本..."
if ! pyenv versions | grep -q "${PythonVersion}"; then
    echo "错误：未安装Python ${PythonVersion}，请先执行 pyenv install ${PythonVersion}"
    exit 1
fi
pyenv local "${PythonVersion}" || {
    echo "错误：切换Python版本失败"
    exit 1
}

# 创建虚拟环境
echo "创建虚拟环境..."
python -m venv .venv || {
    echo "错误：虚拟环境创建失败"
    exit 1
}

# 优化点6：检查用户是否已存在（避免创建重复用户）
echo "创建项目专用用户..."
if id -u "${PY_PROJECT_NAME}" &>/dev/null; then
    echo "警告：用户 ${PY_PROJECT_NAME} 已存在，跳过创建"
else
    useradd -m -d "${PROJECT_DIR}" -s /bin/bash "${PY_PROJECT_NAME}" || {
        echo "错误：用户创建失败"
        exit 1
    }
fi

# 优化点7：添加权限确认，避免递归操作失误
echo "设置目录权限..."
chown -R "${PY_PROJECT_NAME}:${PY_PROJECT_NAME}" "${PROJECT_DIR}" || {
    echo "错误：权限设置失败"
    exit 1
}

# 优化点8：输出项目信息和后续操作提示
echo -e "\n===== 项目创建完成 ====="
echo "项目路径: ${PROJECT_DIR}"
echo "Python版本: ${PythonVersion}（本地生效）"
echo "项目用户: ${PY_PROJECT_NAME}"
echo -e "\n后续操作建议："
echo "1. 切换到项目用户：su - ${PY_PROJECT_NAME}"
echo "2. 激活虚拟环境：source .venv/bin/activate"
echo "3. 安装依赖：pip install <package>"