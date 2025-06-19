# PostgreSQL 9.x SSL配置步骤

基于您现有的PostgreSQL 9.x安装脚本，我为您整理了配置SSL的操作步骤。以下是在CentOS系统上为PostgreSQL 9.x启用SSL的完整步骤：

## 1. 创建SSL证书和密钥

首先，需要创建SSL证书和密钥文件：

```bash

# 定义变量
PG_VERSION="9.4.26"
PG_USER="PostgreSQL_${PG_VERSION}_V1"
PG_HOME="/data/PostgreSQL_${PG_VERSION}_V1"
PG_PORT="6001"
PG_DATA="$PG_HOME/data"
PG_BASE="$PG_HOME/base"
PG_SOFT="$PG_HOME/soft"
PG_CONF="$PG_HOME/conf"


# 创建SSL目录
mkdir -p $PG_HOME/ssl
chown $PG_USER:$PG_USER $PG_HOME/ssl
chmod 700 $PG_HOME/ssl

# 切换到PostgreSQL用户
su - $PG_USER

# 生成自签名证书和密钥
cd $PG_HOME/ssl
openssl req -new -x509 -days 365 -nodes -text \
  -out server.crt \
  -keyout server.key \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=Secsmart/CN=postgresql-server"

# 设置正确的权限
chmod 600 server.key
chmod 644 server.crt

# 创建符号链接到数据目录
cp server.crt $PG_DATA/
cp server.key $PG_DATA/


```

## 2. 修改PostgreSQL配置文件

接下来，需要修改PostgreSQL的配置文件以启用SSL：

```bash
# 修改postgresql.conf配置文件
cat >> $PG_DATA/postgresql.conf << EOF

# SSL配置
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
EOF
```

## 3. 修改pg_hba.conf配置文件

更新客户端认证配置文件，添加SSL连接选项：

```bash
# 修改pg_hba.conf配置文件
cat >> $PG_DATA/pg_hba.conf << EOF

# SSL连接
hostssl    all             all             0.0.0.0/0               md5
EOF
```

## 4. 重启PostgreSQL服务

配置完成后，需要重启PostgreSQL服务以应用更改：

```bash
# 重启PostgreSQL服务
su - $PG_USER -c "$PG_BASE/bin/pg_ctl -D $PG_DATA restart -l $PG_HOME/logfile.log"

# 或者使用systemd重启服务
systemctl restart postgresql_$PG_VERSION
```

## 5. 验证SSL配置

最后，验证SSL配置是否生效：

```bash
# 使用psql客户端测试SSL连接
su - $PG_USER -c "$PG_BASE/bin/psql -h localhost -p $PG_PORT --dbname postgres -c \"SHOW ssl;\""

# 查看SSL连接状态
su - $PG_USER -c "$PG_BASE/bin/psql -h localhost -p $PG_PORT --dbname postgres -c \"SELECT datname, usename, ssl, client_addr FROM pg_stat_ssl JOIN pg_stat_activity ON pg_stat_ssl.pid = pg_stat_activity.pid;\""
```

## 完整的SSL配置脚本

您可以将以下脚本添加到您的PostgreSQL安装脚本中，或者作为单独的脚本运行：

```bash
#!/bin/bash

# 定义变量
PG_VERSION="9.4.26"
PG_USER="PostgreSQL_${PG_VERSION}_V1"
PG_HOME="/data/PostgreSQL_${PG_VERSION}_V1"
PG_PORT="6001"
PG_DATA="$PG_HOME/data"
PG_BASE="$PG_HOME/base"

echo "开始配置PostgreSQL SSL..."

# 创建SSL目录
mkdir -p $PG_HOME/ssl
chown $PG_USER:$PG_USER $PG_HOME/ssl
chmod 700 $PG_HOME/ssl

# 生成自签名证书和密钥
su - $PG_USER << EOF
cd $PG_HOME/ssl
openssl req -new -x509 -days 365 -nodes -text \
  -out server.crt \
  -keyout server.key \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=Secsmart/CN=postgresql-server"

chmod 600 server.key
chmod 644 server.crt

cp server.crt $PG_DATA/
cp server.key $PG_DATA/
EOF

# 修改postgresql.conf配置文件
su - $PG_USER << EOF
cat >> $PG_DATA/postgresql.conf << EOT

# SSL配置
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
EOT
EOF

# 修改pg_hba.conf配置文件
su - $PG_USER << EOF
cat >> $PG_DATA/pg_hba.conf << EOT

# SSL连接
hostssl    all             all             0.0.0.0/0               md5
EOT
EOF

# 重启PostgreSQL服务
echo "重启PostgreSQL服务..."
if command -v systemctl &> /dev/null; then
    systemctl restart postgresql_$PG_VERSION || { echo "使用systemd重启PostgreSQL服务失败"; exit 1; }
else
    su - $PG_USER -c "$PG_BASE/bin/pg_ctl -D $PG_DATA restart -l $PG_HOME/logfile.log" || { echo "重启PostgreSQL服务失败"; exit 1; }
fi

# 验证SSL配置
echo "验证SSL配置..."
sleep 5
su - $PG_USER -c "$PG_BASE/bin/psql -h localhost -p $PG_PORT --dbname postgres -c \"SHOW ssl;\"" || { echo "验证SSL配置失败"; exit 1; }

echo "PostgreSQL SSL配置完成！"
echo "SSL连接命令示例："
echo "psql \"sslmode=require host=localhost port=$PG_PORT dbname=postgres user=admin\""
```

## 客户端SSL连接示例

要使用SSL连接到PostgreSQL服务器，客户端可以使用以下命令：

```bash
# 强制使用SSL连接
psql "sslmode=require host=localhost port=$PG_PORT dbname=postgres user=admin"

# 或者使用环境变量
PGSSLMODE=require psql -h localhost -p $PG_PORT -U admin -d postgres
```

注意：在生产环境中，建议使用完整的证书链和受信任的CA签名证书，而不是自签名证书。

        