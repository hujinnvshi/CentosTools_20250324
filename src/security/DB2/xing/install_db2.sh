#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量
DB2_VERSION="11.5.8"
DB2_HOME="/data/db2"
DB2_INSTANCE="db2inst1"
DB2_FENCED="db2fenc1"
DB2_PASSWORD="Secsmart#612"
DB2_PORT="50000"
DB2_PACKAGE="v11.5.8_linuxx64_server_dec.tar.gz"

# 安装依赖包
print_message "安装依赖包..."
yum install -y \
    pam.i686 \
    libstdc++.i686 \
    ksh \
    gcc \
    gcc-c++ \
    kernel-devel \
    libstdc++ \
    libstdc++-devel \
    numactl \
    numactl-devel \
    pam-devel \
    net-tools \
    bind-utils

# 创建 ksh 链接
print_message "配置 ksh..."
if [ ! -f /bin/ksh ]; then
    ln -s /bin/bash /bin/ksh
fi

# 清理旧目录
print_message "清理旧安装..."
if [ -d "${DB2_HOME}" ]; then
    print_warning "清理旧的安装目录..."
    rm -rf ${DB2_HOME}/*
fi

# 创建必要目录
print_message "创建目录结构..."
mkdir -p ${DB2_HOME}/{instance,data,backup,log,bin}
chmod -R 755 ${DB2_HOME}

# 解压安装包到临时目录
print_message "解压安装包..."
TEMP_DIR=$(mktemp -d)
tar -xzf ${DB2_PACKAGE} -C ${TEMP_DIR}
cd ${TEMP_DIR}/server_dec

# 运行预检查
print_message "运行安装预检查..."
./db2prereqcheck -l ${DB2_HOME}/log/prereq.log
if [ $? -ne 0 ]; then
    print_warning "预检查发现一些问题，请查看日志: ${DB2_HOME}/log/prereq.log"
    sleep 5
fi

# 安装 DB2
print_message "安装 DB2..."
./db2_install -b ${DB2_HOME} -p SERVER -l ${DB2_HOME}/log/install.log -n

# 等待安装完成并检查结果
sleep 10
if [ ! -f "${DB2_HOME}/instance/db2icrt" ]; then
    print_error "DB2 安装失败，请检查安装日志: ${DB2_HOME}/log/install.log"
    exit 1
fi

# 清理临时目录
rm -rf ${TEMP_DIR}

# 验证实例创建
if ! id ${DB2_INSTANCE} >/dev/null 2>&1; then
    print_error "实例用户创建失败"
    exit 1
fi

# 创建管理脚本目录
mkdir -p ${DB2_HOME}/bin
chmod 755 ${DB2_HOME}/bin

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/db2.sh << EOF
# DB2 环境变量
export DB2_HOME=${DB2_HOME}
export DB2INSTANCE=${DB2_INSTANCE}
export DB2_PORT=${DB2_PORT}
export PATH=\$PATH:\$DB2_HOME/bin:\$DB2_HOME/adm
EOF

source /etc/profile.d/db2.sh

# 为实例用户配置环境
su - ${DB2_INSTANCE} << EOF
# 配置通信
db2set DB2COMM=TCPIP
db2 update dbm cfg using SVCENAME ${DB2_PORT}

# 启动实例
db2start

# 创建示例数据库
db2sampl

# 验证安装
db2 connect to sample

# 创建管理员用户
db2 "GRANT DBADM,CREATETAB,BINDADD,CONNECT,CREATE_NOT_FENCED,IMPLICIT_SCHEMA,LOAD ON DATABASE TO USER admin"
db2 "GRANT SYSADM,SYSCTRL,SYSMAINT,SYSMON TO USER admin"
db2 "CREATE USER admin USING Secsmart#612"
db2 "GRANT EXECUTE ON PACKAGE NULLID.SQLC2H50 TO admin"
db2 "GRANT EXECUTE ON PACKAGE NULLID.SQLC2H51 TO admin"
db2 "GRANT EXECUTE ON PACKAGE NULLID.SQLC2H52 TO admin"
db2 "GRANT EXECUTE ON PACKAGE NULLID.SQLC2H53 TO admin"
db2 "GRANT EXECUTE ON PACKAGE NULLID.SQLC2H54 TO admin"

# 更新数据库管理器配置以允许远程连接
db2 update dbm cfg using SVCENAME ${DB2_PORT}
db2set DB2COMM=TCPIP
db2 update dbm cfg using TCP_KEEPALIVE YES
db2 update dbm cfg using AUTHENTICATION SERVER

db2 terminate
EOF

# 创建管理脚本
print_message "创建管理脚本..."
cat > ${DB2_HOME}/bin/db2_start.sh << EOF
#!/bin/bash
su - ${DB2_INSTANCE} -c "db2start"
EOF

cat > ${DB2_HOME}/bin/db2_stop.sh << EOF
#!/bin/bash
su - ${DB2_INSTANCE} -c "db2stop force"
EOF

cat > ${DB2_HOME}/bin/db2_status.sh << EOF
#!/bin/bash
su - ${DB2_INSTANCE} -c "db2 get instance"
EOF

chmod +x ${DB2_HOME}/bin/db2_*.sh

print_message "DB2 安装完成！"
print_message "数据库实例: ${DB2_INSTANCE}"
print_message "数据库端口: ${DB2_PORT}"
print_message "管理员密码: ${DB2_PASSWORD}"
print_message ""
print_message "常用命令："
print_message "启动数据库: ${DB2_HOME}/bin/db2_start.sh"
print_message "停止数据库: ${DB2_HOME}/bin/db2_stop.sh"
print_message "查看状态: ${DB2_HOME}/bin/db2_status.sh"
print_message "连接数据库: db2 connect to sample user ${DB2_INSTANCE} using ${DB2_PASSWORD}"

# 在最后的提示信息中添加新用户信息
print_message "管理员用户信息："
print_message "用户名: admin"
print_message "密码: Secsmart#612"
print_message "远程连接命令: db2 connect to sample user admin using Secsmart#612"