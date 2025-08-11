#!/bin/bash
#
# mongo3_repl_install.sh
# 一键在单机部署 3 节点 MongoDB 副本集 (CentOS 7.9)
#
# 要点：
# - 三节点端口：27017, 27018, 27019
# - 每个实例独立 data/log/conf/pid，二进制共享
# - 使用 keyFile 做节点间认证，并启用 authorization (生产应更谨慎)
# - 自动生成 systemd unit，启用并启动
#
# 使用：
#   sudo ./mongo3_repl_install.sh
#
set -euo pipefail
IFS=$'\n\t'

### ====== 可配置项（如需修改） ======
MONGO_VERSION="6.0.4"
MONGO_PACKAGE="/tmp/mongodb-linux-x86_64-rhel70-6.0.4.tgz"   # 本地包路径，修改为实际路径
BASE_DIR="/data/mongo-cluster"                              # 集群安装基准目录
BIN_DIR="${BASE_DIR}/bin"                                   # 二进制放置目录
USER="mongod"                                               # 运行用户
REPL_NAME="rs0"                                             # 副本集名字
PORTS=(27017 27018 27019)                                   # 三个实例端口
ADMIN_USER="admin"
ADMIN_PWD="Secsmart#612"                                    # 创建的管理员密码（可改）
MONGOSH_RPM_URL="https://downloads.mongodb.com/compass/mongodb-mongosh-1.10.6.x86_64.rpm"

# systemd unit 名称前缀
SERVICE_PREFIX="mongod-multi"

### ====== 基础检查 ======
if [[ "$(id -u)" -ne 0 ]]; then
  echo "请以 root 身份运行脚本"
  exit 1
fi

if [[ ! -f "$MONGO_PACKAGE" ]]; then
  echo "找不到 MongoDB 安装包: $MONGO_PACKAGE"
  exit 1
fi

echo "开始部署 MongoDB 三节点副本集（版本: $MONGO_VERSION）"
echo "基准目录: $BASE_DIR"
echo

### ====== 1. 安装依赖 & 创建运行用户 ======
echo "[1/8] 安装系统依赖并创建用户..."
yum install -y epel-release || true
yum install -y cyrus-sasl cyrus-sasl-gssapi cyrus-sasl-plain libcurl openssl xz-compat-libs || true

# 创建运行用户（如无）
if ! id "$USER" &>/dev/null; then
    groupadd -r "$USER" || true
    useradd -r -M -s /sbin/nologin -g "$USER" "$USER"
    echo "创建系统用户: $USER"
fi

### ====== 2. 创建目录结构 ======
echo "[2/8] 创建目录结构..."
mkdir -p "$BASE_DIR"
mkdir -p "$BIN_DIR"
chown -R "$USER":"$USER" "$BASE_DIR"
chmod 755 "$BASE_DIR"

# 为每个实例创建目录
for i in "${!PORTS[@]}"; do
  idx=$((i+1))
  port=${PORTS[i]}
  inst_dir="${BASE_DIR}/node${idx}"
  mkdir -p "${inst_dir}/data" "${inst_dir}/logs" "${inst_dir}/conf" "${inst_dir}/pid"
  chown -R "$USER":"$USER" "${inst_dir}"
done

### ====== 3. 解包并复制二进制 ======
echo "[3/8] 解包 MongoDB 并复制二进制..."
tmpdir=$(mktemp -d)
tar -zxf "$MONGO_PACKAGE" -C "$tmpdir"
extracted=$(find "$tmpdir" -maxdepth 1 -type d -name "mongodb-linux-*" | head -n1)
if [[ -z "$extracted" ]]; then
  echo "未找到解压目录，退出"
  rm -rf "$tmpdir"
  exit 1
fi

# 复制 bin 到 BIN_DIR
cp -r "${extracted}/bin/"* "$BIN_DIR/"
chmod +x "$BIN_DIR/"*
ln -sf "$BIN_DIR/mongod" /usr/bin/mongod
ln -sf "$BIN_DIR/mongos" /usr/bin/mongos
ln -sf "$BIN_DIR/mongosh" /usr/bin/mongosh || true  # 若包内含mongosh

rm -rf "$tmpdir"
chown -R "$USER":"$USER" "$BIN_DIR"

### ====== 4. 生成 keyFile（节点间认证） ======
echo "[4/8] 生成 keyFile..."
KEYFILE="${BASE_DIR}/keyfile"
if [[ ! -f "$KEYFILE" ]]; then
  head -c 756 /dev/urandom | openssl base64 | tr -d '\n' > "$KEYFILE"
  chmod 600 "$KEYFILE"
  chown "$USER":"$USER" "$KEYFILE"
  echo "生成 keyfile: $KEYFILE"
else
  echo "keyfile 已存在, 跳过生成"
fi

### ====== 5. 生成每个节点配置文件 & systemd unit ======
echo "[5/8] 生成实例配置与 systemd unit..."
for i in "${!PORTS[@]}"; do
  idx=$((i+1))
  port=${PORTS[i]}
  inst_dir="${BASE_DIR}/node${idx}"
  conf="${inst_dir}/conf/mongod.conf"
  log="${inst_dir}/logs/mongod.log"
  pidfile="${inst_dir}/pid/mongod.pid"
  dbpath="${inst_dir}/data"

  cat > "$conf" <<EOF
# MongoDB ${MONGO_VERSION} instance (node${idx})
storage:
  dbPath: ${dbpath}
  journal:
    enabled: true
systemLog:
  destination: file
  logAppend: true
  path: ${log}
processManagement:
  fork: false
  pidFilePath: ${pidfile}
net:
  bindIp: 0.0.0.0
  port: ${port}
replication:
  replSetName: ${REPL_NAME}
security:
  authorization: enabled
  keyFile: ${KEYFILE}
setParameter:
  enableLocalhostAuthBypass: false
EOF

  chown "$USER":"$USER" "$conf"
  chmod 600 "$conf"

  # systemd unit
  srv_file="/etc/systemd/system/${SERVICE_PREFIX}-${idx}.service"
  cat > "$srv_file" <<EOF
[Unit]
Description=MongoDB Node ${idx} (Port ${port})
After=network.target

[Service]
User=${USER}
Group=${USER}
Environment="MALLOC_ARENA_MAX=1"
ExecStart=${BIN_DIR}/mongod --config ${conf}
ExecStop=${BIN_DIR}/mongod --config ${conf} --shutdown
Restart=always
RestartSec=10
LimitNOFILE=64000
LimitNPROC=64000
LimitMEMLOCK=infinity
TasksMax=infinity
TimeoutStopSec=60
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_PREFIX}-${idx}.service"
done

### ====== 6. 启动所有实例 ======
echo "[6/8] 启动所有 mongod 实例..."
for i in "${!PORTS[@]}"; do
  idx=$((i+1))
  systemctl start "${SERVICE_PREFIX}-${idx}.service"
  sleep 1
done

# 等待实例就绪
echo "等待实例就绪（最多 20 秒）..."
for attempt in {1..20}; do
  ready=true
  for port in "${PORTS[@]}"; do
    if ! ss -ltn "( sport = :${port} )" >/dev/null 2>&1; then
      ready=false
    fi
  done
  $ready && break
  sleep 1
done

### ====== 7. 初始化副本集（如果尚未初始化） ======
echo "[7/8] 初始化副本集（若已初始化则跳过）..."
PRIMARY_PORT=${PORTS[0]}
HOST_IP=$(hostname -I | awk '{print $1}')

# 检查是否已属于副本集（从第一个节点获取 rs.status）
already_in_rs=false
if mongosh --quiet --port ${PRIMARY_PORT} --eval "rs.status()" >/dev/null 2>&1; then
  echo "检测到副本集已初始化，跳过 rs.initiate"
  already_in_rs=true
fi

if ! $already_in_rs; then
  # 构造 members 列表
  members_js="members: ["
  for i in "${!PORTS[@]}"; do
    idx=$((i))
    port=${PORTS[i]}
    members_js="${members_js}{ _id: ${i}, host: \"${HOST_IP}:${port}\" },"
  done
  # 去掉末尾逗号
  members_js="${members_js%,}]"

  # 生成 js 并执行 init
  init_js="rs.initiate({ _id: \"${REPL_NAME}\", ${members_js} })"
  echo "执行 rs.initiate ..."
  mongosh --quiet --port ${PRIMARY_PORT} --eval "${init_js}"
  echo "等待副本集选举完成（最多 30 秒）..."
  # 等待 PRIMARY 出现
  for k in {1..30}; do
    state=$(mongosh --quiet --port ${PRIMARY_PORT} --eval "rs.status().myState" 2>/dev/null || echo "")
    # myState == 1 表示 PRIMARY
    if [[ "$state" == "1" ]]; then
      echo "节点 ${HOST_IP}:${PRIMARY_PORT} 成为 PRIMARY"
      break
    fi
    sleep 1
  done
fi

### ====== 8. 创建管理员账户（如果不存在） ======
echo "[8/8] 创建管理员账户（如不存在）..."
# 使用 localhost exception 无需认证即可创建 admin（因为 keyFile 和 auth 已启用，但 localhost exception允许在本地创建首个用户）
mongosh --quiet --port ${PRIMARY_PORT} --eval "
db = db.getSiblingDB('admin');
if (db.getUser('${ADMIN_USER}') == null) {
  db.createUser({user: '${ADMIN_USER}', pwd: '${ADMIN_PWD}', roles: ['root']});
  print('管理员账户创建成功');
} else {
  print('管理员账户已存在，跳过创建');
}"

echo
echo "部署完成！信息汇总："
echo "-------------------------------"
echo "Base dir: ${BASE_DIR}"
for i in "${!PORTS[@]}"; do
  idx=$((i+1)); port=${PORTS[i]}
  echo "Node${idx}: data=${BASE_DIR}/node${idx}/data, log=${BASE_DIR}/node${idx}/logs/mongod.log, port=${port}"
done
echo "ReplicaSet name: ${REPL_NAME}"
echo "Admin user: ${ADMIN_USER}"
echo "Admin password: ${ADMIN_PWD}"
echo "Keyfile: ${KEYFILE}"
echo
echo "管理命令示例："
echo "  systemctl status ${SERVICE_PREFIX}-1.service"
echo "  systemctl status ${SERVICE_PREFIX}-2.service"
echo "  systemctl status ${SERVICE_PREFIX}-3.service"
echo "连接 PRIMARY："
echo "  mongosh --host ${HOST_IP} --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p '${ADMIN_PWD}' --authenticationDatabase admin"
echo
echo "注意："
echo " - 脚本启用了 keyFile 与 authorization，用于生产环境更安全。"
echo " - 若要开放防火墙端口，请自行调整防火墙策略。"
echo " - 本脚本在单机上模拟三节点，生产环境建议不同物理/虚拟机部署。"
echo
# 生成 start/stop 管理脚本
cat > /usr/local/bin/mongo-cluster-start.sh <<'EOF'
#!/bin/bash
systemctl start mongod-multi-1.service
systemctl start mongod-multi-2.service
systemctl start mongod-multi-3.service
EOF
cat > /usr/local/bin/mongo-cluster-stop.sh <<'EOF'
#!/bin/bash
systemctl stop mongod-multi-3.service
systemctl stop mongod-multi-2.service
systemctl stop mongod-multi-1.service
EOF
chmod +x /usr/local/bin/mongo-cluster-start.sh /usr/local/bin/mongo-cluster-stop.sh

echo "一键启动脚本： /usr/local/bin/mongo-cluster-start.sh"
echo "一键停止脚本： /usr/local/bin/mongo-cluster-stop.sh"