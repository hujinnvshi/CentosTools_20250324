-- 创建用户并设置密码
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';

-- 授予所有数据库的所有权限
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;

-- 刷新权限使生效
FLUSH PRIVILEGES;


# 启用通用查询日志 (记录所有SQL语句)
general_log = 1
# 指定日志文件路径
general_log_file = /var/log/mysql/general.log
# 日志输出方式 (FILE/TABLE/NONE)
log_output = FILE

mysql -u admin -pSecsmart#612 -P6005
mysql -u admin -pSecsmart#612 -P6005 zn < /opt/zjk/V3_2_1__V3.2.1R200初始化整合.sql
echo "END"
mysql -u admin -pSecsmart#612 -P6005 zn < /opt/zjk/V3_2_2__V3.2.1R200插入数据.sql
echo "END"


mysql -u admin -pSecsmart#612 
mysql -u admin -pSecsmart#612  wxy < /opt/V3_2_1__V3.2.1R200初始化整合.sql
echo "END"
mysql -u admin -pSecsmart#612  wxy < /opt/V3_2_2__V3.2.1R200插入数据.sql
echo "END"