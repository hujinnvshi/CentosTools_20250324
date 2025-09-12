#!/bin/bash

# 创建用户和目录
USERNAME="vbe1004"
INSTALL_DIR="/usr/local/${USERNAME}"
DATA_DIR="/data/${USERNAME}"

# 创建用户
useradd ${USERNAME} || { echo "创建用户失败"; exit 1; }

# 设置密码
echo "请为 ${USERNAME} 用户设置密码："
passwd ${USERNAME} || { echo "设置密码失败"; exit 1; }

# 创建安装目录
mkdir -p ${INSTALL_DIR} || { echo "创建安装目录失败"; exit 1; }

# 创建数据目录
mkdir -p ${DATA_DIR} || { echo "创建数据目录失败"; exit 1; }

# 设置目录权限
chown -R ${USERNAME}:${USERNAME} ${INSTALL_DIR} || { echo "设置安装目录权限失败"; exit 1; }
chmod -R 755 ${INSTALL_DIR} || { echo "设置安装目录权限失败"; exit 1; }

chown -R ${USERNAME}:${USERNAME} ${DATA_DIR} || { echo "设置数据目录权限失败"; exit 1; }
chmod -R 755 ${DATA_DIR} || { echo "设置数据目录权限失败"; exit 1; }

# 切换到用户并安装
su - ${USERNAME} << 'EOF'
#!/bin/bash

# 请替换为实际的安装包路径
INSTALL_PACKAGE="/tmp/Vastbase-E100-4.0.0.2(1368)-CentOS7-x86_64-20250528.tar.gz"

# 检查安装包是否存在
if [ ! -f "$INSTALL_PACKAGE" ]; then
    echo "错误：安装包 $INSTALL_PACKAGE 不存在"
    exit 1
fi

# 解压安装包
tar -zxvf "$INSTALL_PACKAGE" || { echo "解压安装包失败"; exit 1; }

# 进入安装目录
# cd atlasdb-security-installer || { echo "进入安装目录失败"; exit 1; }

# 执行安装
# ./atlasdb_installer || { echo "执行安装程序失败"; exit 1; }

echo "安装完成准备配置"
EOF