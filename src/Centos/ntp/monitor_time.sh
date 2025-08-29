#!/bin/bash
# 时间监控脚本

SERVER_IP="192.168.20.199"
THRESHOLD=0.1  # 时间偏差阈值（秒）
LOG_FILE="/var/log/time_sync.log"
ALERT_EMAIL="admin@example.com"

# 获取当前主机时间
local_time=$(date +%s.%N)

# 获取NTP服务器时间
server_time=$(ssh $SERVER_IP "date +%s.%N")

# 计算时间差
time_diff=$(echo "$local_time - $server_time" | bc -l | awk '{printf "%.6f", $0}')

# 取绝对值
abs_diff=$(echo $time_diff | awk '{print ($1 < 0) ? -$1 : $1}')

# 记录日志
echo "$(date) - 时间偏差: $abs_diff 秒" >> $LOG_FILE

# 检查是否超过阈值
if (( $(echo "$abs_diff > $THRESHOLD" | bc -l) )); then
    # 强制同步时间
    ntpdate -u $SERVER_IP
    hwclock --systohc
    
    # 发送告警
    echo "主机 $(hostname) 时间偏差过大: $abs_diff 秒, 已强制同步" | mail -s "时间同步告警" $ALERT_EMAIL
    
    # 记录事件
    echo "$(date) - 时间偏差超过阈值, 已强制同步" >> $LOG_FILE
fi