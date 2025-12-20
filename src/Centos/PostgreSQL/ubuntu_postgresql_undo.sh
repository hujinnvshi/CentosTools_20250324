#!/bin/bash

# PostgreSQL 撤销脚本（Ubuntu）

# 脚本使用说明
show_help() {
    echo "PostgreSQL 撤销脚本（Ubuntu）"
    echo ""'
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -v, --version    PostgreSQL 版本号 (默认: 16.3)"
    echo "  -i, --instance   实例标识 (默认: V1)"
    echo "  --help           显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -v 16.3 -i V1  # 撤销版本16.3，标识V1的实例"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            PG_VERSION="$2"
            shift 2
            ;;
        -i|--instance)
            INSTANCE_ID="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            echo "未知选项: $1"
            show_help
            ;;
    esac
done

# 设置默认值
PG_VERSION=${PG_VERSION:-"16.3"}
INSTANCE_ID=${INSTANCE_ID:-"V1"}

# 定义实例变量
PG_USER="PostgreSQL_${PG_VERSION}_${INSTANCE_ID}"
PG_ServiceName="PostgreSQL_${PG_VERSION}_${INSTANCE_ID}"
PG_HOME="/data/PostgreSQL_${PG_VERSION}_${INSTANCE_ID}"
PG_ENV_FILE="/etc/profile.d/PostgreSQL_${PG_VERSION}_${INSTANCE_ID}.sh"

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：请以root用户运行此脚本"
    exit 1
fi
echo "开始撤销 PostgreSQL 实例 $PG_VERSION-$INSTANCE_ID..."

# 停止并禁用服务
echo "停止并禁用服务 $PG_ServiceName..."
systemctl stop $PG_ServiceName 2>/dev/null
systemctl disable $PG_ServiceName 2>/dev/null

# 删除服务文件
echo "删除服务文件..."
rm -f /etc/systemd/system/$PG_ServiceName.service 2>/dev/null
systemctl daemon-reload 2>/dev/null

# 删除环境变量文件
echo "删除环境变量文件..."
rm -f $PG_ENV_FILE 2>/dev/null

# 删除用户
echo "删除用户 $PG_USER..."
userdel $PG_USER 2>/dev/null

# 删除安装目录
echo "删除安装目录 $PG_HOME..."
rm -rf $PG_HOME 2>/dev/null

echo "撤销完成！"