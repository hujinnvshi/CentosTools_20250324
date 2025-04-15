# MySQL 常用命令

## 1. 服务管理命令
# 启动 MySQL 服务
systemctl start mysqld

# 停止 MySQL 服务
systemctl stop mysqld

# 重启 MySQL 服务
systemctl restart mysqld

# 查看 MySQL 服务状态
systemctl status mysqld

ln -s /data/mysql/mysql.sock /tmp/mysql.sock

## 2. 数据库连接命令
# 使用 root 用户连接（本地）
mysql -u root -pSecsmart#612

# 使用测试用户连接测试数据库
mysql -u testuser -pTest#123456 testdb

# 使用 socket 文件连接
mysql -u root -pSecsmart#612 --socket=/data/mysql/mysql.sock

# 使用主机名连接
mysql -h localhost -u root -pSecsmart#612

## 3. 数据库备份命令
# 备份单个数据库
mysqldump -u root -pSecsmart#612 testdb > /backup/testdb_$(date +%Y%m%d).sql

# 备份所有数据库
mysqldump -u root -pSecsmart#612 --all-databases > /backup/all_db_$(date +%Y%m%d).sql

## 4. 查看状态命令
# 查看 MySQL 版本
mysql -V

# 查看数据库运行状态
mysqladmin -u root -pSecsmart#612 status

# 查看数据库进程
mysqladmin -u root -pSecsmart#612 processlist

## 5. 安全检查命令
# 查看错误日志
tail -f /data/mysql/log/error.log

# 查看慢查询日志
tail -f /data/mysql/log/slow.log

# 查看二进制日志
ls -l /data/mysql/log/binlog/



# 1. 确保MySQL未运行
systemctl stop mysqld

# 2. 使用mysqld_safe启动MySQL
/data/mysql/base/bin/mysqld_safe --defaults-file=/data/mysql/my.cnf &

# 3. 检查MySQL是否启动成功
ps -ef | grep mysql
netstat -nltp | grep 3306

# 4. 停止MySQL
kill -TERM `cat /data/mysql/mysql.pid`