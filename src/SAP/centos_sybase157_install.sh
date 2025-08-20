#!/bin/bash
# Sybase ASE 15.7 CentOS 一键安装部署脚本
# 版本: 1.3
# 作者: Rancher
# 最后更新: 2025-08-20

# 设置环境变量
export SYBASE_USER="sb157v1"  # 用户名长度不超过8字符
export SYBASE_GROUP="sb157v1" # 组名长度不超过8字符
export SYBASE_HOME="/data/sb157v1"
export ASE_VERSION="15.7"
export ASE_INSTALL_DIR="$SYBASE_HOME/ASE-$ASE_VERSION"
export ASE_DATA_DIR="$SYBASE_HOME/data"
export ASE_BACKUP_DIR="$SYBASE_HOME/backups"
export ASE_INTERFACES="$SYBASE_HOME/interfaces"
export ASE_INSTALL_FILE="ase157_linuxx86-64.tgz"
export ASE_INSTALL_PATH="/tmp/$ASE_INSTALL_FILE"
export SA_PASSWORD=${SA_PASSWORD:-"Secsmart#612"} # 可从环境变量获取密码

# 设置严格模式
set -euo pipefail

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
    
    # 检测系统版本
    if grep -q "CentOS Linux 8" /etc/os-release; then
        echo "检测到CentOS 8，启用PowerTools仓库..."
        dnf install -y epel-release
        dnf config-manager --set-enabled powertools
    fi
    
    yum install -y glibc.i686 libaio libaio-devel ksh redhat-lsb-core
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
    su - "$SYBASE_USER" -c "tar -xzvf '$ASE_INSTALL_PATH' -C '$ASE_INSTALL_DIR' --strip-components=1"
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
    cd $ASE_INSTALL_DIR/
    ./setup.bin -console -f $SYBASE_HOME/ase_install.rs
    
    # 检查安装是否成功
    if [ $? -ne 0 ]; then
        echo "错误: Sybase安装失败"
        echo "请检查日志: $SYBASE_HOME/ase_install.log"
        exit 1
    fi
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
    
    # 备份原配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    
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
    
    # 备份原配置
    cp /etc/security/limits.conf /etc/security/limits.conf.bak
    
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
    
    # 尝试启动服务，最多重试3次
    for i in {1..3}; do
        systemctl start sybase157v1.service
        if systemctl is-active --quiet sybase157v1.service; then
            break
        else
            echo "启动失败，重试 ($i/3)..."
            sleep 5
        fi
    done
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
        echo "请检查日志:"
        echo "Systemd日志: journalctl -u sybase157v1"
        echo "Sybase日志: $SYBASE_HOME/ASE-$ASE_VERSION/install/ASE.log"
        exit 1
    fi
}

# 设置sa密码
set_sa_password() {
    echo "设置sa用户密码..."
    
    # 等待服务完全启动
    echo "等待Sybase服务就绪..."
    sleep 10
    
    $SYBASE_HOME/ASE-$ASE_VERSION/bin/isql -Usa -P -SSYB_ASE << EOF
sp_password null, '$SA_PASSWORD', sa
go
exit
EOF

    # 验证密码是否设置成功
    if ! $SYBASE_HOME/ASE-$ASE_VERSION/bin/isql -Usa -P"$SA_PASSWORD" -SSYB_ASE -b -Q "select @@version" >/dev/null 2>&1; then
        echo "错误: 设置sa密码失败"
        exit 1
    fi
}

# 主函数
main() {
    echo "===== 开始安装 Sybase ASE 15.7 ====="
    check_root
    check_install_file
    install_dependencies
    create_user_group
    create_directories
    extract_install_files
    create_response_file
    run_installer
    configure_environment
    configure_interfaces
    create_service
    start_service
    check_service_status
    set_sa_password
    
    echo "===== 安装完成 ====="
    echo "SA用户密码: $SA_PASSWORD"
    echo "请尽快修改密码: isql -Usa -P'$SA_PASSWORD' -SSYB_ASE"
    echo "修改密码命令: sp_password '旧密码', '新密码', sa"
}

# 执行主函数
main "$@"