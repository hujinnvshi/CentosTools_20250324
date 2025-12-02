✅ GreatDB（UniDB 6.1.0）单机部署操作手册
适用版本：UniDB-6.1.0-GA
部署方式：手动安装（后续可转为 Python 自动化脚本）
目标系统：Linux（CentOS/RHEL/AlmaLinux 等，glibc ≥ 2.17）

一、约定信息

项目 值

---

用户名 / 用户组 greatdb_v1
二进制目录 /data/greatdb_v1/base
数据目录 /data/greatdb_v1/data
日志目录 /data/greatdb_v1/log
配置文件 /data/greatdb_v1/gdb.cnf
管理账号 admin
管理密码 Secsmart#612
监听端口 6108
安装包路径 /tmp/UniDB-6.1.0-GA-1-2806e9fd-Linux-glibc2.17-x86_64.tar.xz

二、创建用户与目录

bash
创建用户组和用户
groupadd greatdb_v1
useradd -g greatdb_v1 -m -s /bin/bash greatdb_v1
设置用户密码（兼容 CentOS/RHEL）
echo "greatdb_v1:Secsmart#612" chpasswd
创建所需目录
mkdir -p /data/greatdb_v1/{data,log,base}
授权并设置权限
chown -R greatdb_v1:greatdb_v1 /data/greatdb_v1
chmod 750 /data/greatdb_v1/{data,log,base}

三、解压安装包

bash
解压到 base 目录
tar -xJf /tmp/UniDB-6.1.0-GA-1-2806e9fd-Linux-glibc2.17-x86_64.tar.xz -C /data/greatdb_v1/base
创建软链接便于管理
ln -sf /data/greatdb_v1/base/UniDB-6.1.0-GA-1-2806e9fd-Linux-glibc2.17-x86_64 \
/data/greatdb_v1/base/greatdb

四、配置系统环境变量

bash
添加 bin 路径到系统 PATH
echo 'export PATH=$PATH:/data/greatdb_v1/base/greatdb/bin' >> /etc/profile
立即生效
source /etc/profile
✅ 验证：执行 which greatdb 应返回 /data/greatdb_v1/base/greatdb/bin/greatdb

五、准备配置文件

bash
cat > /data/greatdb_v1/gdb.cnf <<'EOF'
[mysqld]
基础路径
basedir = /data/greatdb_v1/base/greatdb
datadir = /data/greatdb_v1/data
port = 6108
socket = /data/greatdb_v1/log/mysql.sock
user = greatdb_v1
错误日志
log-error = /data/greatdb_v1/log/error.log
字符集
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
认证插件（兼容旧客户端）
default_authentication_plugin = mysql_native_password
InnoDB（根据实际内存调整）
innodb_buffer_pool_size = 1G
EOF
设置权限
chown greatdb_v1:greatdb_v1 /data/greatdb_v1/gdb.cnf
chmod 644 /data/greatdb_v1/gdb.cnf

六、初始化数据库（无密码模式）
⚠️ 确保 /data/greatdb_v1/data 为空！

bash
su - greatdb_v1 -c "
/data/greatdb_v1/base/greatdb/bin/greatdbd \
--defaults-file=/data/greatdb_v1/gdb.cnf \
--initialize-insecure \
--user=greatdb_v1
"
✅ 初始化成功后，会在日志中输出临时 root 密码（但 --initialize-insecure 表示无密码）。

七、启动 GreatDB 服务

bash
su - greatdb_v1 -c "
/data/greatdb_v1/base/greatdb/bin/greatdbd_safe \
--defaults-file=/data/greatdb_v1/gdb.cnf \
--user=greatdb_v1
"
✅ 后台启动，自动守护进程。
✅ 可通过 ps -ef grep greatdbd 查看进程。

八、登录并创建管理账号

1. 登录数据库（无需密码）

bash
/data/greatdb_v1/base/greatdb/bin/greatdb -h 127.0.0.1 -P 6108 -u root 2. 执行 SQL 创建 admin 账号

sql
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON . TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT;
✅ 此时可通过 admin 账号远程或本地连接。

九、验证部署

bash
检查端口监听
ss -tuln grep ':6108'
检查 socket 文件
ls -l /data/greatdb_v1/log/mysql.sock
尝试用 admin 登录
/data/greatdb_v1/base/greatdb/bin/greatdb -h 127.0.0.1 -P 6108 -u admin -p'Secsmart#612' -e "SELECT VERSION();"

预期输出类似：

+-----------+
VERSION()
+-----------+
8.0.32
+-----------+

十、（可选）配置 systemd 服务（便于管理）

如需开机自启或使用 systemctl 管理，可创建服务文件 /etc/systemd/system/greatdb_v1.service：

ini
[Unit]
Description=GreatDB v1 instance
After=network.target

[Service]
Type=forking
User=greatdb_v1
Group=greatdb_v1
ExecStart=/data/greatdb_v1/base/greatdb/bin/greatdbd_safe \
--defaults-file=/data/greatdb_v1/gdb.cnf \
--user=greatdb_v1
Restart=on-failure
RestartSec=5
TimeoutSec=300

[Install]
WantedBy=multi-user.target

启用服务：
bash
systemctl daemon-reload
systemctl enable --now greatdb_v1

✅ 部署完成！

你现在拥有一个：
独立用户运行
路径清晰分离（bin / data / log / conf）
安全权限控制
可远程管理的 GreatDB 实例
