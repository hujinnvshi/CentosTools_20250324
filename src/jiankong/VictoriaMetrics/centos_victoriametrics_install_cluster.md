# 1. 启动 vmstorage 服务（3个实例）
BASE_DIR="/data/victoriametrics"   # 基础目录

# 1. 启动 vmstorage 服务（3个实例）
sudo -u victoriametrics $BASE_DIR/bin/vmstorage \
  -storageDataPath=$BASE_DIR/data/storage1 \
  -httpListenAddr=:8482 \
  -retentionPeriod=300h \
  > $BASE_DIR/logs/storage1/vmstorage.log 2>&1 &

sudo -u victoriametrics $BASE_DIR/bin/vmstorage \
  -storageDataPath=$BASE_DIR/data/storage2 \
  -httpListenAddr=:8492 \
  -retentionPeriod=300h \
  > $BASE_DIR/logs/storage2/vmstorage.log 2>&1 &

sudo -u victoriametrics $BASE_DIR/bin/vmstorage \
  -storageDataPath=$BASE_DIR/data/storage3 \
  -httpListenAddr=:8502 \
  -retentionPeriod=300h \
  > $BASE_DIR/logs/storage3/vmstorage.log 2>&1 &

# 等待storage服务启动（约5秒）
sleep 5

# 启动 vminsert 服务（2个实例）
sudo -u victoriametrics $BASE_DIR/bin/vminsert \
  -httpListenAddr=:8480 \
  -storageNode=localhost:8482,localhost:8492,localhost:8502 \
  > $BASE_DIR/logs/insert1/vminsert.log 2>&1 &

sudo -u victoriametrics $BASE_DIR/bin/vminsert \
  -httpListenAddr=:8490 \
  -storage-node=localhost:8482,localhost:8492,localhost:8502 \
  > $BASE_DIR/logs/insert2/vminsert.log 2>&1 &

# 3. 启动 vmselect 服务（2个实例）
sudo -u victoriametrics $BASE_DIR/bin/vmselect \
  -httpListenAddr=:8481 \
  -storage-node=localhost:8482,localhost:8492,localhost:8502 \
  > $BASE_DIR/logs/select1/vmselect.log 2>&1 &

sudo -u victoriametrics $BASE_DIR/bin/vmselect \
  -httpListenAddr=:8491 \
  -storage-node=localhost:8482,localhost:8492,localhost:8502 \
  > $BASE_DIR/logs/select2/vmselect.log 2>&1 &