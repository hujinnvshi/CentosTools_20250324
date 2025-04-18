# 启动数据库
systemctl start mariadb

# 停止数据库
systemctl stop mariadb

# 重启数据库
systemctl restart mariadb

# 查看状态
systemctl status mariadb

# 连接数据库
mysql -uadmin -p'Secsmart#612'
mysql -uadmin -p'Secsmart#612' -h 172.16.61.225

# 连接特定数据库
mysql -uadmin -p'Secsmart#612' testdb

ln -s  /data/mariadb/mysql.sock /var/lib/mysql/mysql.sock