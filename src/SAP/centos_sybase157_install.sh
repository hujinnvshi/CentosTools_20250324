#!/bin/bash
# Sybase ASE 15.7 CentOS 一键安装部署脚本
# 版本: 1.0
# 作者: 您的名字
# 最后更新: 2023-10-15

# 检查是否以root用户运行
if [ "$(id -u)" != "0" ]; then
   echo "错误: 此脚本必须以root权限运行"
   exit 1
fi

# 设置环境变量
export SYBASE_USER="sybase157v1"
export SYBASE_GROUP="sybase157v1"
export SYBASE_HOME="/data/sybase157v1"
export ASE_VERSION="15.7"
export ASE_INSTALL_DIR="$SYBASE_HOME/ASE-$ASE_VERSION"
export ASE_DATA_DIR="$SYBASE_HOME/data"
export ASE_BACKUP_DIR="$SYBASE_HOME/backups"
export ASE_INTERFACES="$SYBASE_HOME/interfaces"
export ASE_INSTALL_FILE="ase157_linuxx86-64.tgz"  # 替换为实际文件名
export ASE_INSTALL_PATH="/tmp/$ASE_INSTALL_FILE"

# 检查安装文件是否存在
if [ ! -f "$ASE_INSTALL_PATH" ]; then
    echo "错误: Sybase安装文件未找到: $ASE_INSTALL_PATH"
    echo "请将Sybase ASE 15.7安装文件放在此路径"
    exit 1
fi

# 安装依赖包
echo "安装系统依赖包..."
yum install -y glibc.i686 libaio libaio-devel ksh compat-libstdc++-33 redhat-lsb-core

# 创建Sybase用户和组
echo "创建Sybase用户和组..."
if ! getent group $SYBASE_GROUP > /dev/null; then
    groupadd $SYBASE_GROUP
fi

if ! id -u $SYBASE_USER > /dev/null; then
    useradd -m -g $SYBASE_GROUP -d $SYBASE_HOME $SYBASE_USER
fi

# 创建目录结构
echo "创建Sybase目录结构..."
mkdir -p $SYBASE_HOME
mkdir -p $ASE_DATA_DIR
mkdir -p $ASE_BACKUP_DIR
mkdir -p $ASE_INSTALL_DIR

chown -R $SYBASE_USER:$SYBASE_GROUP $SYBASE_HOME
chmod -R 755 $SYBASE_HOME

# 解压安装文件
echo "解压Sybase安装文件..."
su - $SYBASE_USER -c "tar -xzvf $ASE_INSTALL_PATH -C $SYBASE_HOME"

# 创建响应文件
echo "创建安装响应文件..."
cat > $SYBASE_HOME/ase_install.rs << EOF
SYBROOT=$SYBASE_HOME
SYBASE_JRE=$SYBASE_HOME/shared-1_0/JRE-1_6
AGENTDIR=$SYBASE_HOME/ASE-$ASE_VERSION/ASEnterprise
ASE_DIR=$SYBASE_HOME/ASE-$ASE_VERSION
ASE_DATADIR=$ASE_DATA_DIR
ASE_BACKUPDIR=$ASE_BACKUP_DIR
SYBASE_PRODUCT_LICENSE_TYPE=DEV
SYB_LICENSE_PROPERTY_FILE=$SYBASE_HOME/SYBASE.lic
SYB_LICENSE_METHOD=FILE
SYB_LICENSE=accept
SYB_ASE_MASTER_DEV_SIZE=100
SYB_ASE_MASTER_DEV_DIRECTORY=$ASE_DATA_DIR
SYB_ASE_SYBSYSTEMPROCS_DEV_SIZE=100
SYB_ASE_SYBSYSTEMPROCS_DEV_DIRECTORY=$ASE_DATA_DIR
SYB_ASE_SYBSYSTEMDB_DEV_SIZE=100
SYB_ASE_SYBSYSTEMDB_DEV_DIRECTORY=$ASE_DATA_DIR
SYB_ASE_TEMPDB_DEV_SIZE=100
SYB_ASE_TEMPDB_DEV_DIRECTORY=$ASE_DATA_DIR
SYB_ASE_MODEL_DEV_SIZE=100
SYB_ASE_MODEL_DEV_DIRECTORY=$ASE_DATA_DIR
SYB_ASE_MASTERDB_DEV_SIZE=100
SYB_ASE_MASTERDB_DEV_DIRECTORY=$ASE_DATA_DIR
EOF

# 运行安装程序
echo "开始安装Sybase ASE 15.7..."
cd $SYBASE_HOME/ASE-$ASE_VERSION/install
./setup -console -f $SYBASE_HOME/ase_install.rs

# 配置环境变量
echo "配置环境变量..."
cat > /etc/profile.d/sybase.sh << EOF
export SYBASE=$SYBASE_HOME
export SYBASE_ASE=ASE-$ASE_VERSION
export SYBASE_OCS=OCS-15_0
export PATH=\$PATH:\$SYBASE/\$SYBASE_ASE/bin:\$SYBASE/\$SYBASE_OCS/bin
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$SYBASE/\$SYBASE_ASE/lib:\$SYBASE/\$SYBASE_OCS/lib
EOF

source /etc/profile.d/sybase.sh

# 配置interfaces文件
echo "配置interfaces文件..."
cat > $SYBASE_HOME/interfaces << EOF
SYB_ASE
    master tcp ether $(hostname -I | awk '{print $1}') 5000
    query tcp ether $(hostname -I | awk '{print $1}') 5000
EOF

# 创建服务脚本
echo "创建Sybase服务脚本..."
cat > /etc/systemd/system/sybase.service << EOF
[Unit]
Description=Sybase ASE 15.7 Database Server
After=network.target

[Service]
Type=forking
User=$SYBASE_USER
Group=$SYBASE_GROUP
Environment=SYBASE=$SYBASE_HOME
Environment=SYBASE_ASE=ASE-$ASE_VERSION
Environment=SYBASE_OCS=OCS-15_0
Environment=PATH=$SYBASE_HOME/ASE-$ASE_VERSION/bin:$SYBASE_HOME/OCS-15_0/bin:$PATH
Environment=LD_LIBRARY_PATH=$SYBASE_HOME/ASE-$ASE_VERSION/lib:$SYBASE_HOME/OCS-15_0/lib:$LD_LIBRARY_PATH

ExecStart=$SYBASE_HOME/ASE-$ASE_VERSION/install/RUN_SYB_ASE
ExecStop=$SYBASE_HOME/ASE-$ASE_VERSION/install/shutdown -y

[Install]
WantedBy=multi-user.target
EOF


# 启动Sybase服务
echo "启动Sybase服务..."
systemctl daemon-reload
systemctl enable sybase.service
systemctl start sybase.service

# 检查服务状态
echo "检查Sybase服务状态..."
if systemctl is-active --quiet sybase.service; then
    echo "Sybase ASE 15.7 已成功安装并启动！"
    echo "安装目录: $SYBASE_HOME"
    echo "数据目录: $ASE_DATA_DIR"
    echo "备份目录: $ASE_BACKUP_DIR"
    echo ""
    echo "使用以下命令管理Sybase:"
    echo "启动服务: systemctl start sybase"
    echo "停止服务: systemctl stop sybase"
    echo "查看状态: systemctl status sybase"
    echo ""
    echo "使用以下命令连接Sybase:"
    echo "isql -Usa -P -SSYB_ASE"
else
    echo "错误: Sybase服务启动失败"
    echo "请检查日志: $SYBASE_HOME/ASE-$ASE_VERSION/install/ASE.log"
    exit 1
fi

# 设置sa密码
echo "设置sa用户密码..."
$SYBASE_HOME/ASE-$ASE_VERSION/bin/isql -Usa -P -SSYB_ASE << EOF
sp_password null, 'Secsmart#612', sa
go
exit
EOF

echo "安装完成！"