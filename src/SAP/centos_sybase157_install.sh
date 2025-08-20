#!/bin/bash
# Sybase ASE 15.7 CentOS 一键安装部署脚本
# 版本: 1.2
# 作者: Rancher
# 最后更新: 2025-08-20

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

# 检查是否以root用户运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "错误: 此脚本必须以root权限运行"
        exit 1
    fi
}

# 检查安装文件是否存在
check_install_file() {
    if [ ! -f "$ASE_INSTALL_PATH" ]; then
        echo "错误: Sybase安装文件未找到: $ASE_INSTALL_PATH"
        echo "请将Sybase ASE 15.7安装文件放在此路径"
        exit 1
    fi
}

# 安装依赖包
install_dependencies() {
    echo "安装系统依赖包..."
    yum install -y glibc.i686 libaio libaio-devel ksh compat-libstdc++-33 redhat-lsb-core
}

# 创建Sybase用户和组
create_user_group() {
    echo "创建Sybase用户和组..."
    if ! getent group "$SYBASE_GROUP" >/dev/null 2>&1; then
        groupadd "$SYBASE_GROUP"
    fi

    if ! id -u "$SYBASE_USER" >/dev/null 2>&1; then
        useradd -m -g "$SYBASE_GROUP" -d "$SYBASE_HOME" "$SYBASE_USER"
    fi
}

# 创建目录结构
create_directories() {
    echo "创建Sybase目录结构..."
    mkdir -p $SYBASE_HOME
    mkdir -p $ASE_DATA_DIR
    mkdir -p $ASE_BACKUP_DIR
    mkdir -p $ASE_INSTALL_DIR

    chown -R $SYBASE_USER:$SYBASE_GROUP $SYBASE_HOME
    chmod -R 755 $SYBASE_HOME
}

# 解压安装文件
extract_install_files() {
    echo "解压Sybase安装文件..."
    su - "$SYBASE_USER" -c "tar -xzvf '$ASE_INSTALL_PATH' -C '$SYBASE_HOME'"
}

# 创建响应文件
create_response_file() {
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
}

# 运行安装程序
run_installer() {
    echo "开始安装Sybase ASE 15.7..."
    cd $SYBASE_HOME/ASE-$ASE_VERSION/install
    ./setup -console -f $SYBASE_HOME/ase_install.rs
}

# 配置环境变量
configure_environment() {
    echo "配置环境变量..."
    cat > /etc/profile.d/sybase.sh << EOF
export SYBASE=$SYBASE_HOME
export SYBASE_ASE=ASE-$ASE_VERSION
export SYBASE_OCS=OCS-15_0
export PATH=\$PATH:\$SYBASE/\$SYBASE_ASE/bin:\$SYBASE/\$SYBASE_OCS/bin
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$SYBASE/\$SYBASE_ASE/lib:\$SYBASE/\$SYBASE_OCS/lib
EOF

    source /etc/profile.d/sybase.sh
}

# 配置interfaces文件
configure_interfaces() {
    echo "配置interfaces文件..."
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')
    cat > $SYBASE_HOME/interfaces << EOF
SYB_ASE
    master tcp ether $ip_address 5000
    query tcp ether $ip_address 5000
EOF
}

# 创建服务脚本
create_service() {
    echo "创建Sybase服务脚本..."
    cat > /etc/systemd/system/sybase157v1.service << EOF
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
}

# 设置内核参数
configure_kernel_parameters() {
    echo "优化系统内核参数..."
    cat >> /etc/sysctl.conf << EOF
# Sybase ASE 优化参数
kernel.sem = 250 32000 100 142
kernel.shmmax = 4294967296
kernel.shmall = 4194304
kernel.shmmni = 4096
vm.swappiness = 10
EOF

    sysctl -p
}

# 设置资源限制
configure_resource_limits() {
    echo "设置资源限制..."
    cat >> /etc/security/limits.conf << EOF
# Sybase ASE 资源限制
$SYBASE_USER soft nofile 65536
$SYBASE_USER hard nofile 65536
$SYBASE_USER soft nproc 16384
$SYBASE_USER hard nproc 16384
EOF
}

# 启动Sybase服务
start_service() {
    echo "启动Sybase服务..."
    systemctl daemon-reload
    systemctl enable sybase157v1.service
    systemctl start sybase157v1.service
}

# 检查服务状态
check_service_status() {
    echo "检查Sybase服务状态..."
    if systemctl is-active --quiet sybase157v1.service; then
        echo "Sybase ASE 15.7 已成功安装并启动！"
        echo "安装目录: $SYBASE_HOME"
        echo "数据目录: $ASE_DATA_DIR"
        echo "备份目录: $ASE_BACKUP_DIR"
        echo ""
        echo "使用以下命令管理Sybase:"
        echo "启动服务: systemctl start sybase157v1"
        echo "停止服务: systemctl stop sybase157v1"
        echo "查看状态: systemctl status sybase157v1"
        echo ""
        echo "使用以下命令连接Sybase:"
        echo "isql -Usa -P -SSYB_ASE"
    else
        echo "错误: Sybase服务启动失败"
        echo "请检查日志: $SYBASE_HOME/ASE-$ASE_VERSION/install/ASE.log"
        exit 1
    fi
}

# 设置sa密码
set_sa_password() {
    echo "设置sa用户密码..."
    $SYBASE_HOME/ASE-$ASE_VERSION/bin/isql -Usa -P -SSYB_ASE << EOF
sp_password null, 'Secsmart#612', sa
go
exit
EOF
}

# 主函数
main() {
    check_root
    check_install_file
    install_dependencies
    create_user_group
    create_directories
    extract_install_files
    create_response_file
    run_installer
    # configure_environment
    # configure_interfaces
    create_service
    configure_kernel_parameters
    configure_resource_limits
    start_service
    check_service_status
    set_sa_password
    echo "安装完成！"
}

# 执行主函数
main "$@"