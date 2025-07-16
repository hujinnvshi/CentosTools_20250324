#!/bin/bash

# 定义变量（建议使用较新版本，9.4已停止维护）
PG_VERSION="9.4.26"
PG_USER="PostgreSQL_${PG_VERSION}_V1"
PG_ServiceName="PostgreSQL_${PG_VERSION}_V1"
PG_HOME="/data/PostgreSQL_${PG_VERSION}_V1"
PG_PORT="6001"
PG_DATA="$PG_HOME/data"
PG_BASE="$PG_HOME/base"
PG_SOFT="$PG_HOME/soft"
PG_CONF="$PG_HOME/conf"
PG_SRC="$PG_SOFT/postgresql-$PG_VERSION"  # 源码目录


# 检查端口是否占用
if netstat -tulpn | grep -q ":$PG_PORT"; then
    echo "错误：端口 $PG_PORT 已被占用，请更换端口后重试"
    exit 1
fi


# 清理旧用户和目录
echo "清理旧环境..."
userdel $PG_USER 2>/dev/null
rm -rf $PG_HOME 2>/dev/null


# 创建用户和安装路径
echo "创建用户和目录结构..."
useradd $PG_USER -d $PG_HOME || { echo "创建用户失败"; exit 1; }
mkdir -p $PG_HOME/{base,data,soft,conf} || { echo "创建目录失败"; exit 1; }
chown -R $PG_USER:$PG_USER $PG_HOME || { echo "修改目录权限失败"; exit 1; }


# 安装依赖（兼容yum/dnf）
echo "安装系统依赖..."
if command -v dnf &> /dev/null; then
    PM="dnf"
else
    PM="yum"
fi
sudo $PM install -y gcc bison gcc-c++ readline readline-devel \
    zlib zlib-devel perl perl-devel libicu-devel flex \
    openssl openssl-devel net-tools || { echo "安装依赖失败"; exit 1; }


# 下载并准备源码包
echo "获取PostgreSQL源码..."
cd $PG_SOFT || { echo "进入目录 $PG_SOFT 失败"; exit 1; }

# 优先使用/tmp的安装包，不存在则下载
if [ ! -f "/tmp/postgresql-$PG_VERSION.tar.gz" ]; then
    sudo wget https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.gz \
        --no-check-certificate || { echo "下载安装包失败"; exit 1; }
else
    cp -f /tmp/postgresql-$PG_VERSION.tar.gz $PG_SOFT/
fi

# 修正安装包权限
sudo chown $PG_USER:$PG_USER postgresql-$PG_VERSION.tar.gz || { echo "修改安装包权限失败"; exit 1; }


# 解压源码并进入目录
echo "解压源码..."
su - $PG_USER -c "cd $PG_SOFT && tar -zxvf postgresql-$PG_VERSION.tar.gz" || { echo "解压安装包失败"; exit 1; }
cd $PG_SRC || { echo "进入源码目录 $PG_SRC 失败"; exit 1; }


# 编译安装（使用普通用户权限）
echo "编译安装PostgreSQL..."
su - $PG_USER -c "cd $PG_SRC && ./configure --prefix=$PG_BASE --with-openssl" || { echo "配置失败"; exit 1; }
su - $PG_USER -c "cd $PG_SRC && make" || { echo "编译失败"; exit 1; }
su - $PG_USER -c "cd $PG_SRC && make install" || { echo "安装失败"; exit 1; }


# 初始化数据库
echo "初始化数据库..."
rm -fr $PG_DATA 2>/dev/null
su - $PG_USER -c "$PG_BASE/bin/initdb -D $PG_DATA" || { echo "初始化数据库失败"; exit 1; }


# 修改配置文件（使用用户权限）
echo "配置数据库访问权限..."
# 修改pg_hba.conf允许远程连接
su - $PG_USER -c "echo 'host   all   all   0.0.0.0/0   md5' >> $PG_DATA/pg_hba.conf" || { echo "修改访问控制失败"; exit 1; }

# 修改postgresql.conf（监听地址和端口）
su - $PG_USER -c "sed -i.bak -e 's/^#listen_addresses = '\''localhost'\''/listen_addresses = '\''*'\''/' \
    -e 's/^#port = 5432/port = $PG_PORT/' $PG_DATA/postgresql.conf" || { echo "修改配置文件失败"; exit 1; }


# 配置系统服务
echo "配置系统服务..."
cat > /etc/systemd/system/$PG_ServiceName.service << EOF
[Unit]
Description=PostgreSQL $PG_VERSION Service
After=network.target

[Service]
Type=forking
User=$PG_USER
Group=$PG_USER
Environment=PGDATA=$PG_DATA
ExecStart=$PG_BASE/bin/pg_ctl start -D \$PGDATA -l $PG_HOME/logfile.log
ExecStop=$PG_BASE/bin/pg_ctl stop -D \$PGDATA -m fast
ExecReload=$PG_BASE/bin/pg_ctl reload -D \$PGDATA
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
systemctl daemon-reload || { echo "重载systemd配置失败"; exit 1; }
systemctl enable $PG_ServiceName || { echo "启用服务失败"; exit 1; }
systemctl start $PG_ServiceName || { echo "启动服务失败"; exit 1; }

# 检查服务状态
sleep 3
if ! systemctl is-active --quiet $PG_ServiceName; then
    echo "服务启动失败，查看日志："
    journalctl -u $PG_ServiceName -n 20
    exit 1
fi


# 配置环境变量
echo "配置环境变量..."
PG_ENV_FILE="/etc/profile.d/PostgreSQL_${PG_VERSION}_V1.sh"
cat > $PG_ENV_FILE << EOF
export PG_HOME=$PG_BASE
export PATH=\$PATH:\$PG_HOME/bin
EOF
chmod 644 $PG_ENV_FILE || { echo "设置环境变量权限失败"; exit 1; }
source $PG_ENV_FILE || { echo "加载环境变量失败"; }


# 创建管理员用户
echo "创建数据库管理员..."
su - $PG_USER -c "$PG_BASE/bin/psql -h localhost -p $PG_PORT --dbname postgres -c \"CREATE ROLE admin WITH LOGIN SUPERUSER CREATEDB CREATEROLE INHERIT NOREPLICATION CONNECTION LIMIT -1 PASSWORD 'Secsmart#612';\"" || { echo "创建管理员失败"; exit 1; }


# 获取本地IP
get_local_ip() {
    local ip=$(ip route get 1 | awk '{print $NF;exit}')
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}

# 输出安装结果到Readme.md
echo -e "# PostgreSQL 安装说明\n" > $PG_HOME/Readme.md
echo -e "## 基本信息" >> $PG_HOME/Readme.md
echo -e "- 版本：$PG_VERSION" >> $PG_HOME/Readme.md
echo -e "- 安装路径：$PG_HOME" >> $PG_HOME/Readme.md
echo -e "- 数据目录：$PG_DATA" >> $PG_HOME/Readme.md
echo -e "- 端口：$PG_PORT" >> $PG_HOME/Readme.md
echo -e "- 管理员用户：admin" >> $PG_HOME/Readme.md
echo -e "- 管理员密码：Secsmart#612" >> $PG_HOME/Readme.md
echo -e "- 服务名称：$PG_ServiceName" >> $PG_HOME/Readme.md

echo -e "\n## 基本操作命令" >> $PG_HOME/Readme.md
echo -e "- 启动：systemctl start $PG_ServiceName" >> $PG_HOME/Readme.md
echo -e "- 停止：systemctl stop $PG_ServiceName" >> $PG_HOME/Readme.md
echo -e "- 状态：systemctl status $PG_ServiceName" >> $PG_HOME/Readme.md
echo -e "- 重启：systemctl restart $PG_ServiceName" >> $PG_HOME/Readme.md
echo -e "- 开机启动：systemctl enable $PG_ServiceName" >> $PG_HOME/Readme.md
echo -e "- 禁用开机启动：systemctl disable $PG_ServiceName" >> $PG_HOME/Readme.md

echo -e "\n## 登录命令" >> $PG_HOME/Readme.md
echo -e "- 本地登录：psql -h localhost -p $PG_PORT -U admin -d postgres" >> $PG_HOME/Readme.md
echo -e "- 远程登录：psql -h $(get_local_ip) -p $PG_PORT -U admin -d postgres" >> $PG_HOME/Readme.md