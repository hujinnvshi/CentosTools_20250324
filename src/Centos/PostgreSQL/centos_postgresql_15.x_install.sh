#!/bin/bash

# 定义变量
PG_VERSION="15.9"
PG_USER="PostgreSQL_${PG_VERSION}_V1"
PG_HOME="/data/PostgreSQL_${PG_VERSION}_V1"
PG_PORT="6001"
PG_DATA="$PG_HOME/data"
PG_BASE="$PG_HOME/base"
PG_SOFT="$PG_HOME/soft"
PG_CONF="$PG_HOME/conf"


# 创建用户和安装路径
userdel $PG_USER 2>/dev/null
useradd $PG_USER -d $PG_HOME || { echo "创建用户失败"; exit 1; }
mkdir -p $PG_HOME/{base,data,soft,conf} || { echo "创建目录失败"; exit 1; }
chown -R $PG_USER:$PG_USER $PG_HOME || { echo "修改目录权限失败"; exit 1; }

# 下载安装包和依赖
cd $PG_SOFT || { echo "进入目录 $PG_SOFT 失败"; exit 1; }
sudo yum install gcc bison gcc-c++ readline readline-devel zlib zlib-devel perl perl-devel libicu-devel flex -y || { echo "安装依赖失败"; exit 1; }

# 检查文件是否存在，避免重复下载
cp -fr /tmp/postgresql-$PG_VERSION.tar.gz $PG_SOFT
if [ ! -f "postgresql-$PG_VERSION.tar.gz" ]; then
    sudo wget https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.gz --no-check-certificate || { echo "下载安装包失败"; exit 1; }
fi

# if [ ! -f "postgresql-$PG_VERSION.tar.gz.md5" ]; then
#     sudo wget https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.gz.md5 --no-check-certificate || { echo "下载MD5文件失败"; exit 1; }
# fi

# 检查压缩包完整性
# md5sum -c postgresql-$PG_VERSION.tar.gz.md5 || { echo "压缩包校验失败"; exit 1; }

# 解压安装包
chown -R $PG_USER:$PG_USER $PG_HOME
su - $PG_USER -c "cd $PG_SOFT && tar -zxvf postgresql-$PG_VERSION.tar.gz" || { echo "解压安装包失败"; exit 1; }

# 编译和安装
cd $PG_SOFT/postgresql-$PG_VERSION || { echo "进入源码目录失败"; exit 1; }

# 如果存在 configure 文件，则先运行 configure，再清理旧版本
if [ -f "configure" ]; then
    sudo ./configure --prefix=$PG_BASE || { echo "配置失败"; exit 1; }
    sudo make uninstall || { echo "清理旧版本失败"; exit 1; }
else
    echo "未找到 configure 文件，跳过清理旧版本"
fi

sudo ./configure --prefix=$PG_BASE || { echo "配置失败"; exit 1; }
sudo make || { echo "编译失败"; exit 1; }
sudo make install || { echo "安装失败"; exit 1; }

# 初始化数据库
rm -fr $PG_DATA
su - $PG_USER -c "$PG_BASE/bin/initdb -D $PG_DATA" || { echo "初始化数据库失败"; exit 1; }
sleep 30

# 修改访问控制
echo "host   all   all   0.0.0.0/0   md5" >> $PG_DATA/pg_hba.conf || { echo "修改访问控制失败"; exit 1; }

# 修改 postgresql.conf 配置
sed -i.bak -e "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" \
           -e "s/^#port = 5432/port = $PG_PORT/" $PG_DATA/postgresql.conf || { echo "修改 postgresql.conf 失败"; exit 1; }

# 启动数据库
chown -R $PG_USER:$PG_USER $PG_BASE
su - $PG_USER -c "$PG_BASE/bin/pg_ctl -D $PG_DATA start -l $PG_HOME/logfile.log" || { echo "启动数据库失败"; exit 1; }
sleep 30
su - $PG_USER -c "$PG_BASE/bin/pg_ctl reload -D $PG_DATA" || { echo "重载配置失败"; exit 1; }

# 配置环境变量
PG_ENV_FILE="/etc/profile.d/PostgreSQL_${PG_VERSION}_V1.sh"
cat > $PG_ENV_FILE << EOF
export PG_HOME=$PG_BASE
export PATH=\$PATH:\$PG_HOME/bin
EOF

chmod 644 $PG_ENV_FILE || { echo "设置环境变量文件权限失败"; exit 1; }
source $PG_ENV_FILE || { echo "加载环境变量失败"; exit 1; }

# 创建特权用户
su - $PG_USER -c "$PG_BASE/bin/psql -h localhost -p $PG_PORT --dbname postgres -c \"CREATE ROLE admin WITH LOGIN SUPERUSER CREATEDB CREATEROLE INHERIT NOREPLICATION CONNECTION LIMIT -1 PASSWORD 'Secsmart#612';\"" || { echo "创建特权用户失败"; exit 1; }

# 配置自动启动
# if [ -f "/etc/rc.local" ]; then
#     cp "/etc/rc.local" "/etc/rc.local.bak" || { echo "备份自动启动文件失败"; exit 1; }
# fi
# echo "su - $PG_USER -c \"nohup $PG_BASE/bin/pg_ctl restart -D $PG_DATA &\"" >> /etc/rc.local || { echo "配置自动启动失败"; exit 1; }
# echo "PostgreSQL $PG_VERSION 安装完成！"

# 配置服务
echo "配置 PostgreSQL 服务..."
cat > /etc/systemd/system/postgresql_$PG_VERSION.service << EOF
[Unit]
Description= postgresql_$PG_VERSION
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

# 重新加载 systemd 配置
systemctl daemon-reload || { echo "重新加载 systemd 配置失败"; exit 1; }

# 启用服务
systemctl enable postgresql_$PG_VERSION || { echo "启用 PostgreSQL 服务失败"; exit 1; }

# 启动服务
# systemctl start postgresql_$PG_VERSION || { echo "启动 PostgreSQL 服务失败"; exit 1; }

# 基本操作命令
echo "PostgreSQL 基本操作命令："
echo "启动服务：systemctl start postgresql_$PG_VERSION"
echo "停止服务：systemctl stop postgresql_$PG_VERSION"
echo "重启服务：systemctl restart postgresql_$PG_VERSION"
echo "查看状态：systemctl status postgresql_$PG_VERSION"
echo "启用开机启动：systemctl enable postgresql_$PG_VERSION"
echo "禁用开机启动：systemctl disable postgresql_$PG_VERSION"

# 获取本地 IP 地址
get_local_ip() {
    local ip=$(ip route get 1 | awk '{print $NF;exit}')
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}
# 登录命令
echo "登录 PostgreSQL 命令："
echo "本地登录：psql -h localhost -p $PG_PORT -U admin -d postgres"
echo "远程登录：psql -h $(get_local_ip) -p $PG_PORT -U admin -d postgres"
echo "密码：Secsmart#612"
echo "PostgreSQL $PG_VERSION 安装完成！"