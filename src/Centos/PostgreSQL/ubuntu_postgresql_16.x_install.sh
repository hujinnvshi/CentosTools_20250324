#!/bin/bash

# 定义变量
PG_VERSION="16.3"
PG_USER="postgres_${PG_VERSION}_v1"
PG_ServiceName="postgresql_${PG_VERSION}_v1"  # 服务名称使用小写
PG_HOME="/opt/PostgreSQL_${PG_VERSION}_V1"    # 使用/opt而不是/data
PG_PORT="6003"
PG_DATA="$PG_HOME/data"
PG_BASE="$PG_HOME/base"
PG_SOFT="$PG_HOME/soft"
PG_CONF="$PG_HOME/conf"
PG_SRC="$PG_SOFT/postgresql-$PG_VERSION"  # 源码目录变量

# 检查是否为Ubuntu系统
if [ ! -f /etc/lsb-release ] && [ ! -f /etc/debian_version ]; then
    echo "错误：此脚本仅适用于Ubuntu/Debian系统"
    exit 1
fi

# 检测CPU核心数用于并行编译
if command -v nproc &> /dev/null; then
    CPU_CORES=$(nproc)
elif [ -f /proc/cpuinfo ]; then
    CPU_CORES=$(grep -c processor /proc/cpuinfo)
else
    CPU_CORES=2  # 默认使用2个核心
fi
# 限制最大并行数，避免系统负载过高
if [ $CPU_CORES -gt 28 ]; then
    CPU_CORES=28
fi

# 检查端口是否占用
if netstat -tulpn | grep -q ":$PG_PORT"; then
    echo "错误：端口 $PG_PORT 已被占用，请更换端口后重试"
    exit 1
fi

# 检查是否以root用户运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以root权限运行"
    echo "请使用 sudo $0 命令"
    exit 1
fi

# 清理旧用户和目录
echo "清理旧环境..."
if id "$PG_USER" &>/dev/null; then
    userdel -r $PG_USER 2>/dev/null
fi
rm -rf $PG_HOME 2>/dev/null

# 创建用户和安装路径
echo "创建用户和目录结构..."
useradd -m -s /bin/bash $PG_USER || { echo "创建用户失败"; exit 1; }
mkdir -p $PG_HOME/{base,data,soft,conf,logs} || { echo "创建目录失败"; exit 1; }
chown -R $PG_USER:$PG_USER $PG_HOME || { echo "修改目录权限失败"; exit 1; }

# 安装依赖（Ubuntu系统）
echo "安装系统依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update || { echo "更新软件包列表失败"; exit 1; }
apt-get install -y wget build-essential libreadline-dev zlib1g-dev \
    flex bison libxml2-dev libxslt-dev libssl-dev libicu-dev \
    pkg-config sysstat net-tools || { echo "安装依赖失败"; exit 1; }

# 下载并准备源码包
echo "获取PostgreSQL源码..."
cd $PG_SOFT || { echo "进入目录 $PG_SOFT 失败"; exit 1; }

# 优先使用/tmp的安装包，不存在则下载
if [ ! -f "/tmp/postgresql-$PG_VERSION.tar.gz" ]; then
    sudo -u $PG_USER wget https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.gz \
        --no-check-certificate || { echo "下载安装包失败"; exit 1; }
else
    cp -f /tmp/postgresql-$PG_VERSION.tar.gz $PG_SOFT/
    chown $PG_USER:$PG_USER postgresql-$PG_VERSION.tar.gz
fi

# 解压源码并进入目录
echo "解压源码..."
sudo -u $PG_USER tar -zxvf postgresql-$PG_VERSION.tar.gz || { echo "解压安装包失败"; exit 1; }
cd $PG_SRC || { echo "进入源码目录 $PG_SRC 失败"; exit 1; }

# 编译安装（使用普通用户权限，避免root权限混淆）
echo "编译安装PostgreSQL..."
# 清理旧版本（若存在）
if [ -f "configure" ]; then
    sudo -u $PG_USER ./configure --prefix=$PG_BASE --with-openssl --with-libxml --with-libxslt || { echo "旧版本配置失败"; exit 1; }
    sudo -u $PG_USER make uninstall 2>/dev/null
else
    echo "未找到旧版本配置文件，跳过清理"
fi

# 重新配置并编译（启用SSL，多核心并行编译）
sudo -u $PG_USER ./configure --prefix=$PG_BASE --with-openssl --with-libxml --with-libxslt || { echo "配置失败"; exit 1; }
echo "使用 $CPU_CORES 个核心进行并行编译..."
sudo -u $PG_USER make -j$CPU_CORES || { echo "编译失败"; exit 1; }
sudo -u $PG_USER make install || { echo "安装失败"; exit 1; }

# 初始化数据库
echo "初始化数据库..."
rm -fr $PG_DATA 2>/dev/null
sudo -u $PG_USER $PG_BASE/bin/initdb -D $PG_DATA -U $PG_USER --encoding=UTF8 --locale=C || { echo "初始化数据库失败"; exit 1; }

# 修改配置文件（使用用户权限，避免权限不足）
echo "配置数据库访问权限..."
# 修改pg_hba.conf允许远程连接
sudo -u $PG_USER echo "host   all   all   0.0.0.0/0   md5" >> $PG_DATA/pg_hba.conf || { echo "修改访问控制失败"; exit 1; }

# 修改postgresql.conf（监听地址和端口）
sudo -u $PG_USER sed -i.bak \
    -e "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" \
    -e "s/^#port = 5432/port = $PG_PORT/" \
    -e "s/^#log_line_prefix = ''/log_line_prefix = '%m [%p] %q%u@%d '/" \
    -e "s/^#logging_collector = off/logging_collector = on/" \
    -e "s|^#log_directory = 'log'|log_directory = '$PG_HOME/logs'|" \
    $PG_DATA/postgresql.conf || { echo "修改配置文件失败"; exit 1; }

# 配置系统服务
echo "配置系统服务..."
cat > /etc/systemd/system/$PG_ServiceName.service << EOF
[Unit]
Description=PostgreSQL $PG_VERSION Service
After=network.target
Documentation=https://www.postgresql.org/docs/$PG_VERSION/static/

[Service]
Type=forking
User=$PG_USER
Group=$PG_USER
Environment=PGDATA=$PG_DATA
OOMScoreAdjust=-1000
ExecStart=$PG_BASE/bin/pg_ctl start -D \$PGDATA -l $PG_HOME/logs/postgresql.log
ExecStop=$PG_BASE/bin/pg_ctl stop -D \$PGDATA -m fast
ExecReload=$PG_BASE/bin/pg_ctl reload -D \$PGDATA
Restart=on-failure
RestartSec=5
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
systemctl daemon-reload || { echo "重载systemd配置失败"; exit 1; }
systemctl enable $PG_ServiceName || { echo "启用服务失败"; exit 1; }
systemctl start $PG_ServiceName || { echo "启动服务失败"; exit 1; }

# 检查服务状态
sleep 5
if ! systemctl is-active --quiet $PG_ServiceName; then
    echo "服务启动失败，查看日志："
    journalctl -u $PG_ServiceName -n 20 --no-pager
    exit 1
fi

# 配置环境变量
echo "配置环境变量..."
PG_ENV_FILE="/etc/profile.d/postgresql_${PG_VERSION}_v1.sh"
cat > $PG_ENV_FILE << EOF
# PostgreSQL $PG_VERSION Environment
export PGHOME=$PG_BASE
export PGDATA=$PG_DATA
export PATH=\$PGHOME/bin:\$PATH
export LD_LIBRARY_PATH=\$PGHOME/lib:\$LD_LIBRARY_PATH
export MANPATH=\$PGHOME/share/man:\$MANPATH
EOF
chmod 644 $PG_ENV_FILE || { echo "设置环境变量权限失败"; exit 1; }

# 创建数据库管理员
echo "创建数据库管理员..."
sleep 3  # 等待服务完全启动
sudo -u $PG_USER $PG_BASE/bin/psql -h localhost -p $PG_PORT -d postgres -c \
    "CREATE ROLE admin WITH LOGIN SUPERUSER CREATEDB CREATEROLE INHERIT NOREPLICATION CONNECTION LIMIT -1 PASSWORD 'Secsmart#612';" \
    || { echo "创建管理员失败"; exit 1; }

# 获取本地IP
get_local_ip() {
    local ip=$(ip route get 1 2>/dev/null | awk '{print $7;exit}')
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}

# 生成Readme.md
echo "生成安装说明文档..."
README_PATH="$PG_HOME/Readme.md"
cat > "$README_PATH" << EOF
# PostgreSQL 安装说明

## 基本信息
- 版本：$PG_VERSION
- 安装路径：$PG_HOME
- 数据目录：$PG_DATA
- 端口：$PG_PORT
- 管理员用户：admin
- 管理员密码：Secsmart#612
- 服务名称：$PG_ServiceName

## 基本操作命令
- 启动：systemctl start $PG_ServiceName
- 停止：systemctl stop $PG_ServiceName
- 状态：systemctl status $PG_ServiceName
- 重启：systemctl restart $PG_ServiceName
- 开机启动：systemctl enable $PG_ServiceName
- 禁用开机启动：systemctl disable $PG_ServiceName

## 登录命令
- 本地登录：psql -h localhost -p $PG_PORT -U admin -d postgres
- 远程登录：psql -h $(get_local_ip) -p $PG_PORT -U admin -d postgres

## 环境变量
环境变量已配置在 $PG_ENV_FILE
重新登录或执行以下命令生效：
\`\`\`bash
source $PG_ENV_FILE
\`\`\`

## 日志文件
- 主日志：$PG_HOME/logs/postgresql.log
- 查看实时日志：journalctl -u $PG_ServiceName -f

## 注意事项
1. 默认配置允许远程连接，请确保防火墙已开放端口 $PG_PORT
2. 生产环境请修改默认密码
3. 数据目录：$PG_DATA
4. 配置文件：$PG_DATA/postgresql.conf 和 $PG_DATA/pg_hba.conf
EOF

# 修正文档权限
chown $PG_USER:$PG_USER "$README_PATH" || { echo "修改Readme权限失败"; exit 1; }

echo "================================================================"
echo "PostgreSQL $PG_VERSION 安装完成！"
echo "详细说明请查看：$README_PATH"
echo "管理员账号：admin"
echo "管理员密码：Secsmart#612"
echo "连接命令：psql -h $(get_local_ip) -p $PG_PORT -U admin -d postgres"
echo "================================================================"