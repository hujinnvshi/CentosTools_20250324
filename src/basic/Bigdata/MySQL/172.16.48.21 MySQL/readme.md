# 当前的MySQL启动命令
su - MySQL5739_6003 -c "nohup /data2/MySQL5739_6003/base/bin/mysqld_safe --defaults-file=/data2/MySQL5739_6003/base/my.cnf --user=MySQL5739_6003 &"
# Mysql 安装路径
/data2/MySQL5739_6003/base
# 本地连接
 mysql -uroot -h127.0.0.1 -P6003 -p"Secsmart#612" -S /data2/MySQL5739_6003/data/mysql.sock
 
查看系统的cpu,内存信息
