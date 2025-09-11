# 1. 启动 vmstorage 服务（3个实例）
BASE_DIR="/data/victoriametrics"   # 基础目录

# 启动 vmstorage1（输出日志到文件，保留PID）
sudo -u victoriametrics /data/victoriametrics/bin/vmstorage \
  -storageDataPath=/data/victoriametrics/data/storage1 \
  -httpListenAddr=:8482 \
  -vminsertAddr=:8400 \
  -vmselectAddr=:8401 \
  -retentionPeriod=300h \
  > /data/victoriametrics/logs/storage1/vmstorage.log \
  2> /data/victoriametrics/logs/storage1/vmstorage.error.log &
echo "vmstorage1 PID: $!"

# 启动 vmstorage2（输出日志到文件，保留PID）
sudo -u victoriametrics /data/victoriametrics/bin/vmstorage \
  -storageDataPath=/data/victoriametrics/data/storage2 \
  -httpListenAddr=:8492 \
  -retentionPeriod=300h \
  > /data/victoriametrics/logs/storage2/vmstorage.log \
  2> /data/victoriametrics/logs/storage2/vmstorage.error.log &
echo "vmstorage2 PID: $!"

# 启动 vmstorage3（输出日志到文件，保留PID）
sudo -u victoriametrics /data/victoriametrics/bin/vmstorage \
  -storageDataPath=/data/victoriametrics/data/storage3 \
  -httpListenAddr=:8502 \
  -retentionPeriod=300h \
  > /data/victoriametrics/logs/storage3/vmstorage.log \
  2> /data/victoriametrics/logs/storage3/vmstorage.error.log &
echo "vmstorage3 PID: $!"

# 等待5秒让服务启动
sleep 5

# 检查 vmstorage1 健康状态
curl -s http://localhost:8482/health | grep "OK" || echo "vmstorage1 健康检查失败"

# 检查 vmstorage2 健康状态
curl -s http://localhost:8492/health | grep "OK" || echo "vmstorage2 健康检查失败"

# 检查 vmstorage3 健康状态
curl -s http://localhost:8502/health | grep "OK" || echo "vmstorage3 健康检查失败"

# 等待storage服务启动（约5秒）
sleep 5

# 启动 vminsert1（输出日志到文件，保留PID）
sudo -u victoriametrics /data/victoriametrics/bin/vminsert \
  -httpListenAddr=:8480 \
  -storageNode=localhost:8482,localhost:8492,localhost:8502 \
  > /data/victoriametrics/logs/insert1/vminsert.log \
  2> /data/victoriametrics/logs/insert1/vminsert.error.log &
echo "vminsert1 PID: $!"

# 启动 vminsert2（输出日志到文件，保留PID）
sudo -u victoriametrics /data/victoriametrics/bin/vminsert \
  -httpListenAddr=:8490 \
  -storageNode=localhost:8482,localhost:8492,localhost:8502 \
  > /data/victoriametrics/logs/insert2/vminsert.log \
  2> /data/victoriametrics/logs/insert2/vminsert.error.log &
echo "vminsert2 PID: $!"

# 启动 vmselect1（输出日志到文件，保留PID）
sudo -u victoriametrics /data/victoriametrics/bin/vmselect \
  -httpListenAddr=:8481 \
  -storageNode=localhost:8482,localhost:8492,localhost:8502 \
  > /data/victoriametrics/logs/select1/vmselect.log \
  2> /data/victoriametrics/logs/select1/vmselect.error.log &
echo "vmselect1 PID: $!"

# 启动 vmselect2（输出日志到文件，保留PID）
sudo -u victoriametrics /data/victoriametrics/bin/vmselect \
  -httpListenAddr=:8491 \
  -storageNode=localhost:8482,localhost:8492,localhost:8502 \
  > /data/victoriametrics/logs/select2/vmselect.log \
  2> /data/victoriametrics/logs/select2/vmselect.error.log &
echo "vmselect2 PID: $!"

# 查看所有 victoriametrics 进程
ps aux | grep 'vmstorage\|vminsert\|vmselect' | grep -v grep