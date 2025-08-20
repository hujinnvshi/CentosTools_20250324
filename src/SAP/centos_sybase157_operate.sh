$SYBASE_HOME/ASE-$ASE_VERSION/bin/isql -Usa -PSecsmart#612 -SSYB_ASE

# 检查服务状态
systemctl status sybase

# 检查进程
ps -ef | grep dataserver

# 连接数据库
$SYBASE_HOME/ASE-$ASE_VERSION/bin/isql -Usa -PSecsmart#612 -SSYB_ASE