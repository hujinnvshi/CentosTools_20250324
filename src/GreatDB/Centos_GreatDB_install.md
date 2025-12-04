这份为您梳理优化后的 GreatDB (UniDB 6.1.0) 单机部署手册，旨在让每一步都更清晰、更易于执行。

📝 部署基础信息

下表汇总了本次部署的核心规划，是所有后续操作的依据。

项目 约定值 说明

操作系统 CentOS/RHEL/AlmaLinux 等 需确保 glibc ≥ 2.17

运行用户/组 greatdb_v1 为数据库服务创建的专用用户

二进制目录 /data/greatdb_v1/base 存放 GreatDB 软件

数据目录 /data/greatdb_v1/data 存放数据库文件

日志目录 /data/greatdb_v1/log 存放日志文件

配置文件 /data/greatdb_v1/gdb.cnf 数据库参数文件

管理账号 admin 数据库管理员账号

监听端口 6108 数据库服务监听端口

安装包路径 /tmp/UniDB-6.1.0-GA-1-2806e9fd-Linux-glibc2.17-x86_64.tar.xz 安装包存放位置

⚙️ 逐步执行部署

以下是详细的部署步骤，请按顺序操作。

1. 创建用户与目录
   以 root 用户执行以下命令，创建专用的用户、用户组和数据目录，并设置合适的权限，这是保证系统安全性和部署规范的第一步。

# 创建用户组和用户

groupadd greatdb_v1
useradd -g greatdb_v1 -m -s /bin/bash greatdb_v1
echo "greatdb_v1:Secsmart#612" | chpasswd # 设置用户密码

# 创建所需的目录结构

mkdir -p /data/greatdb_v1/{data,log,base}

# 将目录所有者更改为 greatdb_v1 用户

chown -R greatdb_v1:greatdb_v1 /data/greatdb_v1

# 设置目录权限，确保安全

chmod 750 /data/greatdb_v1/{data,log,base}

2. 解压安装包
   将 GreatDB 安装包解压到计划好的二进制目录。

# 解压安装包

tar -xJf /tmp/UniDB-6.1.0-GA-1-2806e9fd-Linux-glibc2.17-x86_64.tar.xz -C /data/greatdb_v1/base

# 创建软链接，便于未来版本管理

ln -sf /data/greatdb_v1/base/UniDB-6.1.0-GA-1-2806e9fd-Linux-glibc2.17-x86_64 /data/greatdb_v1/base/greatdb

3. 配置系统环境
   将 GreatDB 的可执行文件路径添加到系统的 PATH 环境变量中，方便在任何位置执行数据库命令。

# 将 GreatDB 的 bin 目录添加到全局 PATH

echo 'export PATH=$PATH:/data/greatdb_v1/base/greatdb/bin' >> /etc/profile

# 重新加载配置文件，使更改立即生效

source /etc/profile

# 验证配置是否成功，该命令应返回 GreatDB 的路径

which greatdb

4. 准备配置文件
   创建数据库的配置文件 gdb.cnf。这个文件决定了数据库实例的各种行为。您可以根据服务器实际情况（尤其是内存大小）调整 innodb_buffer_pool_size 等关键参数。

# 使用 cat 命令创建并写入配置文件

cat > /data/greatdb_v1/gdb.cnf << 'EOF'
[mysqld]

# 基础路径设置

basedir = /data/greatdb_v1/base/greatdb
datadir = /data/greatdb_v1/data

# 网络与连接

port = 6108
bind-address = 0.0.0.0
socket = /data/greatdb_v1/log/mysql.sock
user = greatdb_v1
skip-name-resolve = 1

# 错误日志

log-error = /data/greatdb_v1/log/error.log

# 字符集设置

character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
default_authentication_plugin = mysql_native_password

# InnoDB 存储引擎设置（请根据实际内存调整缓冲池大小）

innodb_buffer_pool_size = 1G
EOF

# 设置配置文件的权限

chown greatdb_v1:greatdb_v1 /data/greatdb_v1/gdb.cnf
chmod 644 /data/greatdb_v1/gdb.cnf

5. 初始化数据库
   ⚠️ 初始化前，请务必确认数据目录 /data/greatdb_v1/data 是空目录，否则会失败。此操作将为数据库创建必要的系统表和初始数据结构。

# 切换到 greatdb_v1 用户并执行初始化命令

su - greatdb_v1 -c "/data/greatdb_v1/base/greatdb/bin/unidbd --defaults-file=/data/greatdb_v1/gdb.cnf --initialize-insecure --user=greatdb_v1"

注意：使用 --initialize-insecure 参数意味着 root 用户初始密码为空，在生产环境中，请在启动后立即修改密码。

6. 启动数据库服务
   使用 unidbd_safe 命令启动数据库服务，它是一个守护进程脚本，能在数据库异常退出时自动重启。

# 启动数据库服务并放入后台运行

su - greatdb_v1 -c "/data/greatdb_v1/base/greatdb/bin/unidbd_safe --defaults-file=/data/greatdb_v1/gdb.cnf --user=greatdb_v1 &"

# 检查进程是否启动成功

ps -elf | grep unidbd

7. 登录并创建管理账号
   数据库启动后，需要登录并创建一个有远程访问权限的管理员账号。
   • 登录数据库（初始时 root 用户无密码）：
   mysql -u root -p -S /data/greatdb_v1/log/mysql.sock
   /data/greatdb_v1/base/greatdb/bin/unidb -h 127.0.0.1 -P 6108 -u root

• 在数据库命令行中，执行以下 SQL 语句创建管理员账号并授权：
-- 修改系统用户密码（可选，但建议操作）
ALTER USER 'SYSTEM_DAA'@'%' IDENTIFIED BY 'Secsmart#612';
ALTER USER 'SYSTEM_DBA'@'%' IDENTIFIED BY 'Secsmart#612';
ALTER USER 'SYSTEM_DSA'@'%' IDENTIFIED BY 'Secsmart#612';

-- 创建新的管理员用户并授予全部权限
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON _._ TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES; -- 刷新权限使其生效
EXIT; -- 退出

8. 验证部署
   通过以下命令检查数据库服务是否正常运行。

# 检查端口是否正常监听

ss -tuln | grep :6108

# 检查 socket 文件是否存在

ls -l /data/greatdb_v1/log/mysql.sock

# 使用新创建的管理员账号登录并执行一个简单查询

/data/greatdb_v1/base/greatdb/bin/unidb -h 127.0.0.1 -P 6108 -u admin -p'Secsmart#612' -e "SELECT VERSION();"

如果一切正常，将会返回 GreatDB 的版本号。

🚀 可选：配置为系统服务

建议配置 systemd 服务，以便使用 systemctl 命令来高效地启动、停止、重启数据库，并实现开机自启。

1.  创建服务文件 /etc/systemd/system/greatdb_v1.service，内容如下：
    [Unit]
    Description=GreatDB v1 instance
    After=network.target
    Wants=network-online.target

    [Service]
    Type=simple
    User=greatdb_v1
    Group=greatdb_v1
    ExecStart=/data/greatdb_v1/base/greatdb/bin/unidbd_safe --defaults-file=/data/greatdb_v1/gdb.cnf --user=greatdb_v1
    Restart=on-failure
    RestartSec=5
    TimeoutSec=300
    LimitNOFILE=65536
    LimitNPROC=8192

    [Install]
    WantedBy=multi-user.target

2.  启用并启动服务：
    systemctl daemon-reload
    systemctl enable --now greatdb_v1 # --now 选项表示立即启动服务
    systemctl status greatdb_v1 # 检查服务运行状态

💎 总结

至此，您已经成功部署了一个具备以下特点的 GreatDB 数据库实例：
• 权限分明：使用专用用户运行，数据目录权限控制严格。

• 路径清晰：二进制文件、数据、日志、配置相互分离，易于维护。

• 配置可调：核心参数已配置，并留有根据硬件优化的空间（如内存参数）。

• 管理便捷：可通过 systemd 服务进行高效管理。

希望这份梳理后的手册能让您的部署过程更加顺畅！
