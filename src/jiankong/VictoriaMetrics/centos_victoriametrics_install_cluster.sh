#!/bin/bash
# VictoriaMetrics 单机伪分布式集群部署脚本
# Author: Your Name
# Date: $(date +%Y-%m-%d)
# Version: 3.0 (优化版)

# 配置参数 - 所有关键参数集中配置
VM_VERSION="v1.125.1"             # VictoriaMetrics版本
VM_USER="victoriametrics"          # 运行用户
VM_GROUP="victoriametrics"         # 运行组
BASE_DIR="/data/victoriametrics"   # 基础目录
CONFIG_DIR="/etc/victoriametrics"  # 配置文件目录
LOG_DIR="/var/log/victoriametrics" # 日志目录
RETENTION_PERIOD="300h"            # 数据保留时间
REPLICATION_FACTOR="2"             # 数据复制因子（高可用关键）
LOCAL_PACKAGE="/tmp/victoria-metrics-linux-amd64-v1.125.1-cluster.tar.gz" # 本地安装包路径

# 组件端口配置 - 使用数组管理端口
STORAGE_PORTS=(8482 8492 8502)    # vmstorage HTTP监听端口
INSERT_PORTS=(8480 8490)          # vminsert HTTP监听端口
SELECT_PORTS=(8481 8491)           # vmselect HTTP监听端口

# 内部通信端口 - 确保不冲突
STORAGE_INSERT_PORTS=(8400 8410 8420) # vmstorage的vminsertAddr端口
STORAGE_SELECT_PORTS=(8401 8411 8421) # vmstorage的vmselectAddr端口

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须以root权限运行"
    exit 1
fi

# 验证本地安装包是否存在
if [ ! -f "$LOCAL_PACKAGE" ]; then
    echo "错误：找不到本地安装包 $LOCAL_PACKAGE"
    echo "请确保安装包已放置在指定位置"
    exit 1
fi

# 创建用户和组
echo "创建用户和组..."
if ! getent group $VM_GROUP >/dev/null; then
    groupadd -r $VM_GROUP || { echo "创建组失败"; exit 1; }
fi

if ! id -u $VM_USER >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin -g $VM_GROUP $VM_USER || { echo "创建用户失败"; exit 1; }
fi

# 创建目录结构
echo "创建目录结构..."
mkdir -p $BASE_DIR/{bin,config,data} || exit 1
mkdir -p $CONFIG_DIR || exit 1
mkdir -p $LOG_DIR || exit 1

# 为每个组件创建数据目录
for component in storage1 storage2 storage3 insert1 insert2 select1 select2; do
    mkdir -p $BASE_DIR/data/$component || exit 1
done

# 设置权限
chown -R $VM_USER:$VM_GROUP $BASE_DIR $CONFIG_DIR $LOG_DIR
chmod -R 755 $BASE_DIR $CONFIG_DIR $LOG_DIR

# 使用本地安装包
echo "安装VictoriaMetrics..."
cp "$LOCAL_PACKAGE" "$BASE_DIR/bin/vm.tar.gz" || exit 1
tar -xzf "$BASE_DIR/bin/vm.tar.gz" -C "$BASE_DIR/bin" || exit 1

# 创建组件二进制文件
echo "创建组件二进制文件..."
for component in vmstorage vminsert vmselect; do
    cp "$BASE_DIR/bin/victoria-metrics-prod" "$BASE_DIR/bin/$component" || exit 1
    chmod +x "$BASE_DIR/bin/$component"
    chown $VM_USER:$VM_GROUP "$BASE_DIR/bin/$component"
done

# 清理临时文件
rm -f "$BASE_DIR/bin/vm.tar.gz" "$BASE_DIR/bin/victoria-metrics-prod"

# 创建配置文件
echo "创建配置文件..."

## vmstorage 配置 (3个实例)
for i in {0..2}; do
    cat > "$BASE_DIR/config/storage$((i+1)).conf" <<EOF
storageDataPath=$BASE_DIR/data/storage$((i+1))
httpListenAddr=:${STORAGE_PORTS[$i]}
vminsertAddr=:${STORAGE_INSERT_PORTS[$i]}
vmselectAddr=:${STORAGE_SELECT_PORTS[$i]}
retentionPeriod=$RETENTION_PERIOD
replicationFactor=$REPLICATION_FACTOR
EOF
done

## vminsert 配置 (2个实例)
for i in {0..1}; do
    # 构建storage节点列表
    storage_nodes=$(printf "localhost:%s," "${STORAGE_INSERT_PORTS[@]}" | sed 's/,$//')
    
    cat > "$BASE_DIR/config/insert$((i+1)).conf" <<EOF
httpListenAddr=:${INSERT_PORTS[$i]}
storageNode=$storage_nodes
EOF
done

## vmselect 配置 (2个实例)
for i in {0..1}; do
    # 构建storage节点列表
    storage_nodes=$(printf "localhost:%s," "${STORAGE_SELECT_PORTS[@]}" | sed 's/,$//')
    
    cat > "$BASE_DIR/config/select$((i+1)).conf" <<EOF
httpListenAddr=:${SELECT_PORTS[$i]}
storageNode=$storage_nodes
EOF
done

# 设置配置文件权限
chown -R $VM_USER:$VM_GROUP $BASE_DIR/config
chmod 644 $BASE_DIR/config/*.conf

# 创建systemd服务文件
echo "创建systemd服务文件..."

## vmstorage 服务 (3个实例)
for i in {1..3}; do
    cat > "/etc/systemd/system/vmstorage$i.service" <<EOF
[Unit]
Description=VictoriaMetrics vmstorage $i
After=network.target

[Service]
Type=simple
User=$VM_USER
Group=$VM_GROUP
ExecStart=$BASE_DIR/bin/vmstorage -config=$BASE_DIR/config/storage$i.conf
Restart=always
RestartSec=5
StartLimitInterval=0
LimitNOFILE=65536
LimitNPROC=32000
WorkingDirectory=$BASE_DIR
StandardOutput=file:$LOG_DIR/vmstorage$i.log
StandardError=file:$LOG_DIR/vmstorage$i.error.log

[Install]
WantedBy=multi-user.target
EOF
done

## vminsert 服务 (2个实例)
for i in {1..2}; do
    cat > "/etc/systemd/system/vminsert$i.service" <<EOF
[Unit]
Description=VictoriaMetrics vminsert $i
After=network.target
Requires=vmstorage1.service vmstorage2.service vmstorage3.service
After=vmstorage1.service vmstorage2.service vmstorage3.service

[Service]
Type=simple
User=$VM_USER
Group=$VM_GROUP
ExecStart=$BASE_DIR/bin/vminsert -config=$BASE_DIR/config/insert$i.conf
Restart=always
RestartSec=5
StartLimitInterval=0
LimitNOFILE=65536
LimitNPROC=32000
WorkingDirectory=$BASE_DIR
StandardOutput=file:$LOG_DIR/vminsert$i.log
StandardError=file:$LOG_DIR/vminsert$i.error.log

[Install]
WantedBy=multi-user.target
EOF
done

## vmselect 服务 (2个实例)
for i in {1..2}; do
    cat > "/etc/systemd/system/vmselect$i.service" <<EOF
[Unit]
Description=VictoriaMetrics vmselect $i
After=network.target
Requires=vmstorage1.service vmstorage2.service vmstorage3.service
After=vmstorage1.service vmstorage2.service vmstorage3.service

[Service]
Type=simple
User=$VM_USER
Group=$VM_GROUP
ExecStart=$BASE_DIR/bin/vmselect -config=$BASE_DIR/config/select$i.conf
Restart=always
RestartSec=5
StartLimitInterval=0
LimitNOFILE=65536
LimitNPROC=32000
WorkingDirectory=$BASE_DIR
StandardOutput=file:$LOG_DIR/vmselect$i.log
StandardError=file:$LOG_DIR/vmselect$i.error.log

[Install]
WantedBy=multi-user.target
EOF
done

# 启动服务
echo "启动VictoriaMetrics集群服务..."
systemctl daemon-reload

# 启动storage服务并检查健康状态
for i in {1..3}; do
    echo "启动 vmstorage$i..."
    systemctl enable vmstorage$i
    systemctl start vmstorage$i
    
    # 等待服务启动并检查健康状态
    port=${STORAGE_PORTS[$((i-1))]}
    echo "检查 vmstorage$i 健康状态 (端口: $port)..."
    for attempt in {1..10}; do
        if curl -s "http://localhost:$port/health" | grep -q "OK"; then
            echo "vmstorage$i 健康检查通过"
            break
        else
            if [ $attempt -eq 10 ]; then
                echo "错误：vmstorage$i 健康检查失败"
                journalctl -u vmstorage$i -n 50 --no-pager
                exit 1
            fi
            sleep 2
        fi
    done
done

# 启动insert和select服务
for i in {1..2}; do
    echo "启动 vminsert$i..."
    systemctl enable vminsert$i
    systemctl start vminsert$i
    
    echo "启动 vmselect$i..."
    systemctl enable vmselect$i
    systemctl start vmselect$i
done

# 检查所有服务状态
echo "检查服务状态..."
all_services=(
    vmstorage1 vmstorage2 vmstorage3
    vminsert1 vminsert2
    vmselect1 vmselect2
)

for service in "${all_services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "$service 已成功启动"
    else
        echo "错误：$service 启动失败"
        journalctl -u $service -n 50 --no-pager
        exit 1
    fi
done

# 创建README文件
echo "创建README.md..."
SERVER_IP=$(hostname -I | awk '{print $1}' | head -1)
cat > /root/victoriametrics-README.md <<EOF
# VictoriaMetrics 单机伪分布式集群部署指南

## 集群架构
- 3个 vmstorage 节点 (数据复制因子: $REPLICATION_FACTOR)
- 2个 vminsert 节点
- 2个 vmselect 节点

## 基本信息
- **版本**: $VM_VERSION
- **基础目录**: $BASE_DIR
- **配置文件目录**: $BASE_DIR/config
- **日志目录**: $LOG_DIR
- **数据目录**: $BASE_DIR/data
- **安装包**: $LOCAL_PACKAGE

## 服务端口
- **vmstorage HTTP**: ${STORAGE_PORTS[0]}, ${STORAGE_PORTS[1]}, ${STORAGE_PORTS[2]}
- **vminsert**: ${INSERT_PORTS[0]}, ${INSERT_PORTS[1]}
- **vmselect**: ${SELECT_PORTS[0]}, ${SELECT_PORTS[1]}

## 内部通信端口
- **vmstorage vminsertAddr**: ${STORAGE_INSERT_PORTS[0]}, ${STORAGE_INSERT_PORTS[1]}, ${STORAGE_INSERT_PORTS[2]}
- **vmstorage vmselectAddr**: ${STORAGE_SELECT_PORTS[0]}, ${STORAGE_SELECT_PORTS[1]}, ${STORAGE_SELECT_PORTS[2]}

## 服务管理命令
- 启动所有服务: 
  systemctl start vmstorage{1..3} vminsert{1..2} vmselect{1..2}
- 停止所有服务: 
  systemctl stop vmselect{1..2} vminsert{1..2} vmstorage{1..3}
- 重启所有服务: 
  systemctl restart vmstorage{1..3} vminsert{1..2} vmselect{1..2}
- 查看状态: 
  systemctl status vmstorage1 vminsert1 vmselect1

## 数据访问
- **Prometheus 远程写入地址**:
  http://${SERVER_IP}:${INSERT_PORTS[0]}/insert/0/prometheus/api/v1/write
  http://${SERVER_IP}:${INSERT_PORTS[1]}/insert/0/prometheus/api/v1/write
- **Grafana 数据源地址**:
  http://${SERVER_IP}:${SELECT_PORTS[0]}/select/0/prometheus
  http://${SERVER_IP}:${SELECT_PORTS[1]}/select/0/prometheus

## 健康检查
- vmstorage: curl http://localhost:${STORAGE_PORTS[0]}/health
- vminsert: curl http://localhost:${INSERT_PORTS[0]}/health
- vmselect: curl http://localhost:${SELECT_PORTS[0]}/health

## 集群管理
1. 查看集群状态:
   curl http://localhost:${SELECT_PORTS[0]}/api/v1/status/tsdb

2. 查看节点信息:
   curl http://localhost:${STORAGE_PORTS[0]}/api/v1/status/node

## 升级指南
1. 下载新版本: 
   curl -L https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/<新版本>/victoria-metrics-linux-amd64-<新版本>.tar.gz -o /tmp/vm-new.tar.gz
   
2. 停止所有服务:
   systemctl stop vmselect{1..2} vminsert{1..2} vmstorage{1..3}
   
3. 备份旧版本:
   cp -r $BASE_DIR/bin $BASE_DIR/bin-backup-$(date +%Y%m%d)
   
4. 安装新版本:
   tar -xzf /tmp/vm-new.tar.gz -C $BASE_DIR/bin --strip-components=1
   chmod +x $BASE_DIR/bin/*
   chown $VM_USER:$VM_GROUP $BASE_DIR/bin/*
   
5. 启动服务:
   systemctl start vmstorage{1..3} vminsert{1..2} vmselect{1..2}
EOF

echo "安装完成！"
echo "VictoriaMetrics 伪分布式集群已成功部署"
echo "详细文档请查看: /root/victoriametrics-README.md"
echo "集群状态: systemctl status vmstorage1 vminsert1 vmselect1"