#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量
TIDB_VERSION="v6.6.0"
TIDB_HOME="/data/tidb"
TIDB_DEPLOY_DIR="${TIDB_HOME}/deploy"
TIDB_DATA_DIR="${TIDB_HOME}/data"
CLUSTER_NAME="tidb-cluster"

# 创建必要目录
print_message "创建目录..."
mkdir -p ${TIDB_HOME}/{deploy,data,backup,conf,bin,log}

# 配置系统参数
print_message "配置系统参数..."
cat >> /etc/security/limits.conf << EOF
tidb           soft    nofile          1000000
tidb           hard    nofile          1000000
tidb           soft    stack           32768
tidb           hard    stack           32768
EOF

# 配置 sshd
print_message "配置 SSH..."
sed -i 's/#MaxSessions.*/MaxSessions 20/' /etc/ssh/sshd_config
systemctl restart sshd

# 安装必要软件
print_message "安装必要软件..."
yum install -y numactl mysql wget curl

# 安装 TiUP
print_message "安装 TiUP..."
curl --proto '=https' --tlsv1.2 -sSf https://tiup-mirrors.pingcap.com/install.sh | sh

# 配置环境变量
print_message "配置环境变量..."
source ~/.bash_profile

# 安装 TiUP cluster 组件
print_message "安装 TiUP cluster 组件..."
tiup cluster
tiup update --self && tiup update cluster

# 创建拓扑文件
print_message "创建拓扑配置文件..."
cat > ${TIDB_HOME}/conf/topology.yaml << EOF
global:
  user: "tidb"
  ssh_port: 22
  deploy_dir: "${TIDB_DEPLOY_DIR}"
  data_dir: "${TIDB_DATA_DIR}"

monitored:
  node_exporter_port: 9100
  blackbox_exporter_port: 9115

server_configs:
  tidb:
    instance.tidb_slow_log_threshold: 300
  tikv:
    readpool.storage.use-unified-pool: false
    readpool.coprocessor.use-unified-pool: true
  pd:
    replication.enable-placement-rules: true
    replication.location-labels: ["host"]
  tiflash:
    logger.level: "info"

pd_servers:
  - host: 127.0.0.1

tidb_servers:
  - host: 127.0.0.1

tikv_servers:
  - host: 127.0.0.1
    port: 20160
    status_port: 20180
    config:
      server.labels: { host: "logic-host-1" }

  - host: 127.0.0.1
    port: 20161
    status_port: 20181
    config:
      server.labels: { host: "logic-host-2" }

  - host: 127.0.0.1
    port: 20162
    status_port: 20182
    config:
      server.labels: { host: "logic-host-3" }

tiflash_servers:
  - host: 127.0.0.1

monitoring_servers:
  - host: 127.0.0.1

grafana_servers:
  - host: 127.0.0.1
EOF

# 配置 SSH 密钥认证
print_message "配置 SSH 密钥认证..."
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
fi
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 部署集群
print_message "部署 TiDB 集群..."
tiup cluster deploy ${CLUSTER_NAME} ${TIDB_VERSION} ${TIDB_HOME}/conf/topology.yaml --user root --yes

# 启动集群
print_message "启动 TiDB 集群..."
tiup cluster start ${CLUSTER_NAME}

# 等待集群启动
print_message "等待集群启动..."
sleep 30

# 验证集群状态
print_message "验证集群状态..."
tiup cluster display ${CLUSTER_NAME}

# 创建验证脚本
cat > ${TIDB_HOME}/bin/check_tidb.sh << EOF
#!/bin/bash
echo "检查 TiDB 集群状态..."
mysql -h 127.0.0.1 -P 4000 -u root -e "select version();"
echo "检查 Grafana..."
curl -s http://127.0.0.1:3000 > /dev/null && echo "Grafana 运行正常" || echo "Grafana 未响应"
echo "检查 TiDB Dashboard..."
curl -s http://127.0.0.1:2379/dashboard > /dev/null && echo "Dashboard 运行正常" || echo "Dashboard 未响应"
EOF

chmod +x ${TIDB_HOME}/bin/check_tidb.sh
print_message "TiDB 集群部署完成！"
print_message "集群名称: ${CLUSTER_NAME}"
print_message "访问信息:"
print_message "TiDB: mysql -h 127.0.0.1 -P 4000 -u root"
print_message "Grafana: http://172.16.48.169:3000 (admin/admin)"
print_message "Dashboard: http://172.16.48.169:2379/dashboard"
print_message "验证脚本: ${TIDB_HOME}/bin/check_tidb.sh"

# 创建管理员用户
print_message "创建管理员用户..."
cat > ${TIDB_HOME}/bin/create_admin.sql << EOF
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# 等待 TiDB 服务就绪
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if mysql -h 127.0.0.1 -P 4000 -u root -e "SELECT 1" &>/dev/null; then
        print_message "TiDB 服务已就绪"
        # 执行 SQL 创建管理员
        mysql -h 127.0.0.1 -P 4000 -u root < ${TIDB_HOME}/bin/create_admin.sql && {
            print_message "管理员用户创建成功"
            print_message "管理员账号: admin"
            print_message "管理员密码: Secsmart#612"
        } || print_error "管理员用户创建失败"
        break
    fi
    print_message "等待 TiDB 服务就绪... $attempt/$max_attempts"
    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -gt $max_attempts ]; then
    print_error "TiDB 服务未就绪，管理员用户创建失败"
fi