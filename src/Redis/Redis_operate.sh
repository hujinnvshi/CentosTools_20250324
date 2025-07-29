# 使用 Redis CLI 连接
INSTALL_DIR=/data/Redis_7.0.12
${INSTALL_DIR}/bin/redis-cli -h 127.0.0.1 -p 6379

# 测试连接
127.0.0.1:6379> PING
PONG  # 成功响应

# 查看服务器信息
127.0.0.1:6379> INFO SERVER