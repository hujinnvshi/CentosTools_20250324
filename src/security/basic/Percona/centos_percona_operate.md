以下是Percona数据库的常用维护命令：

1. 登录相关：
```bash
# 使用root用户登录
mysql -uroot -p${PERCONA_PASSWORD} -P3308 -h127.0.0.1

# 使用admin用户登录（允许远程访问）
mysql -uadmin -p'Secsmart#612' -P3308 -h127.0.0.1

# 使用test_user登录（仅本地访问）
mysql -utest_user -p'Test@123' -P3308 test_db
```

2. 密码修改：
```bash
# 登录后修改当前用户密码
ALTER USER USER() IDENTIFIED BY 'Secsmart#612';

# 修改指定用户密码
ALTER USER 'username'@'host' IDENTIFIED BY 'new_password';

# 示例：修改root密码
ALTER USER 'root'@'localhost' IDENTIFIED BY 'new_password';
FLUSH PRIVILEGES;
```

3. 服务管理：
```bash
# 启动服务
systemctl start percona

# 停止服务（温和停止）
systemctl stop percona

# 重启服务
systemctl restart percona

# 查看服务状态
systemctl status percona

# 启用开机自启
systemctl enable percona

# 禁用开机自启
systemctl disable percona
```

4. 温和关闭的其他方法：
```bash
# 方法1：使用mysqladmin（推荐）
mysqladmin -uroot -p shutdown

# 方法2：登录MySQL后执行
mysql> SHUTDOWN;

# 方法3：发送SIGTERM信号
kill $(cat /data/percona_8.4.0/tmp/mysql.pid)
```

5. 查看运行状态：
```bash
# 查看进程
ps aux | grep mysqld

# 查看端口
netstat -tuln | grep 3308

# 查看错误日志
tail -f /data/percona_8.4.0/log/error.log

# 查看慢查询日志
tail -f /data/percona_8.4.0/log/slow.log
```

6. 数据库备份恢复：
```bash
# 备份所有数据库
mysqldump -uroot -p --all-databases > backup_$(date +%Y%m%d).sql

# 备份指定数据库
mysqldump -uroot -p test_db > test_db_$(date +%Y%m%d).sql

# 恢复数据库
mysql -uroot -p < backup.sql
```

注意事项：
1. 所有命令中的密码请替换为实际使用的密码
2. 端口号3308要根据实际配置调整
3. 路径`/data/percona_8.4.0`要根据实际安装路径调整
4. 执行关键操作前建议先备份数据
5. 温和关闭会等待所有事务完成，建议优先使用