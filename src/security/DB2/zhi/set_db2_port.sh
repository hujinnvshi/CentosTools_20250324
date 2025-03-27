#!/bin/bash

# 切换到 DB2 实例用户
su - db2115i1 << EOF

# 停止数据库实例
db2stop force

# 清除所有现有的端口配置
db2 update dbm cfg using SVCENAME ""

# 设置新的端口号为 50000
db2 update dbm cfg using SVCENAME 50000

# 确保使用 TCP/IP 通信
db2set db2comm=tcpip

# 更新系统服务配置
if grep -q "db2c_db2115i1" /etc/services; then
    sudo sed -i '/db2c_db2115i1/d' /etc/services
fi
echo "db2c_db2115i1 50000/tcp" | sudo tee -a /etc/services

# 启动数据库实例
db2start

# 验证配置
echo "检查端口配置："
db2 get dbm cfg | grep SVCENAME
echo "检查服务配置："
cat /etc/services | grep 50000

EOF