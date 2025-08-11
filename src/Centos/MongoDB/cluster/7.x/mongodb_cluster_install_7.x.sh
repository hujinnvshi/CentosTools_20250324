#!/bin/bash
#
# mongo3_repl_install.sh
# 一键在单机部署 3 节点 MongoDB 副本集 (CentOS 7.9)
#
# 优化点：
# - 适配 MongoDB 7.0.12 新特性
# - 添加端口冲突检查与自动替换功能
# - 提供详细的连接测试信息
# - 增强错误处理和日志输出
# - 修复副本集初始化认证问题
#
# 使用：
#   sudo ./mongo3_repl_install.sh
#
set -euo pipefail
IFS=$'\n\t'

### ====== 可配置项（如需修改） ======
MONGO_VERSION="7.0.12"
MONGO_PACKAGE="/tmp/mongodb-linux-x86_64-rhel70-${MONGO_VERSION}.tgz"  # 本地包路径
BASE_DIR="/data/mongo_cluster_${MONGO_VERSION}"             # 集群安装基准目录
BIN_DIR="${BASE_DIR}/bin"                                   # 二进制放置目录
USER="mongod_${MONGO_VERSION}"                              # 运行用户
REPL_NAME="rs0"                                             # 副本集名字
PORTS=(27017 27018 27019)                                   # 三个实例端口
ADMIN_USER="admin"
ADMIN_PWD="Secsmart#612"                                    # 管理员密码
MONGOSH_RPM_URL="https://downloads.mongodb.com/compass/mongodb-mongosh-2.0.1.x86_64.rpm"  # 更新为最新版mongosh

# systemd unit 名称前缀
SERVICE_PREFIX="mongod_multi_${MONGO_VERSION}"

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
ACTUAL_PORTS=()  # 存储实际使用的端口

for i in "${!PORTS[@]}"; do
  idx=$((i+1))
  port=${PORTS[i]}
  inst_dir="${BASE_DIR}/node${idx}"
  conf="${inst_dir}/conf/mongod.conf"
  log="${inst_dir}/logs/mongod.log"
  pidfile="${inst_dir}/pid/mongod.pid"
  dbpath="${inst_dir}/data"

  # 检查端口是否被占用
  original_port=$port
  while ss -tuln | grep -q ":$port "; do
    echo "警告: 端口 $port 已被占用，尝试新端口..."
    port=$((port + 1))
  done
  
  # 如果端口被替换，记录信息
  if [[ "$port" != "$original_port" ]]; then
    echo "节点 ${idx} 端口从 ${original_port} 替换为 ${port}"
  fi
  
  # 存储实际使用的端口
  ACTUAL_PORTS+=("$port")

  # MongoDB 7.0 配置
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
  keyFile: ${KEYFILE}
  authorization: disabled
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
for i in "${!ACTUAL_PORTS[@]}"; do
  idx=$((i+1))
  systemctl start "${SERVICE_PREFIX}-${idx}.service"
  sleep 1
done

# 等待实例就绪
echo "等待实例就绪（最多 20 秒）..."
for attempt in {1..20}; do
  ready=true
  for port in "${ACTUAL_PORTS[@]}"; do
    if ! ss -ltn "( sport = :${port} )" >/dev/null 2>&1; then
      ready=false
    fi
  done
  $ready && break
  sleep 1
done

### ====== 7. 创建管理员账户 ======
echo "[7/8] 创建管理员账户..."
PRIMARY_PORT=${ACTUAL_PORTS[0]}
HOST_IP=$(hostname -I | awk '{print $1}')

# 创建管理员账户（在禁用认证状态下）
mongosh --quiet --port ${PRIMARY_PORT} --eval "
try {
    db = db.getSiblingDB('admin');
    if (db.getUser('${ADMIN_USER}') == null) {
        db.createUser({user: '${ADMIN_USER}', pwd: '${ADMIN_PWD}', roles: ['root']});
        print('管理员账户创建成功');
    } else {
        print('管理员账户已存在，跳过创建');
        db.changeUserPassword('${ADMIN_USER}', '${ADMIN_PWD}');
    }
} catch (e) {
    if (e.codeName === 'Unauthorized') {
        print('检测到认证已启用，尝试使用认证创建用户');
        try {
            db.auth('${ADMIN_USER}', '${ADMIN_PWD}');
            if (db.getUser('${ADMIN_USER}') == null) {
                db.createUser({user: '${ADMIN_USER}', pwd: '${ADMIN_PWD}', roles: ['root']});
                print('管理员账户创建成功（使用认证）');
            } else {
                print('管理员账户已存在，跳过创建（使用认证）');
                db.changeUserPassword('${ADMIN_USER}', '${ADMIN_PWD}');
            }
        } catch (authErr) {
            if (authErr.codeName === 'AuthenticationFailed') {
                print('认证失败，尝试创建新用户');
                db.createUser({user: '${ADMIN_USER}', pwd: '${ADMIN_PWD}', roles: ['root']});
                print('管理员账户创建成功（使用认证）');
            } else {
                throw authErr;
            }
        }
    } else {
        print('创建用户时出错: ' + e);
        throw e;
    }
}"

### ====== 8. 启用认证并初始化副本集 ======
echo "[8/8] 启用认证并初始化副本集..."
# 启用认证
echo "启用认证并重启服务..."
for i in "${!ACTUAL_PORTS[@]}"; do
  idx=$((i+1))
  inst_dir="${BASE_DIR}/node${idx}"
  conf="${inst_dir}/conf/mongod.conf"
  
  # 修改配置文件启用认证
  sed -i 's/authorization: disabled/authorization: enabled/' "$conf"
  
  # 重启服务
  systemctl restart "${SERVICE_PREFIX}-${idx}.service"
  sleep 1
done

# 等待实例重启就绪
echo "等待实例重启就绪（最多 20 秒）..."
for attempt in {1..20}; do
  ready=true
  for port in "${ACTUAL_PORTS[@]}"; do
    if ! ss -ltn "( sport = :${port} )" >/dev/null 2>&1; then
      ready=false
    fi
  done
  $ready && break
  sleep 1
done

# 使用认证信息初始化副本集
echo "初始化副本集（若已初始化则跳过）..."
already_in_rs=false
if mongosh --quiet --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p ${ADMIN_PWD} --authenticationDatabase admin --eval "rs.status()" >/dev/null 2>&1; then
  echo "检测到副本集已初始化，跳过 rs.initiate"
  already_in_rs=true
fi

if ! $already_in_rs; then
  # 构造 members 列表
  members_js="members: ["
  for i in "${!ACTUAL_PORTS[@]}"; do
    idx=$((i))
    port=${ACTUAL_PORTS[i]}
    members_js="${members_js}{ _id: ${i}, host: \"${HOST_IP}:${port}\" },"
  done
  # 去掉末尾逗号
  members_js="${members_js%,}]"

  # 生成 js 并执行 init（使用认证）
  init_js="rs.initiate({ _id: \"${REPL_NAME}\", ${members_js} })"
  echo "执行 rs.initiate: ${init_js}"
  mongosh --quiet --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p ${ADMIN_PWD} --authenticationDatabase admin --eval "${init_js}"
  echo "等待副本集选举完成（最多 30 秒）..."
  # 等待 PRIMARY 出现
  for k in {1..30}; do
    state=$(mongosh --quiet --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p ${ADMIN_PWD} --authenticationDatabase admin --eval "rs.status().myState" 2>/dev/null || echo "")
    # myState == 1 表示 PRIMARY
    if [[ "$state" == "1" ]]; then
      echo "节点 ${HOST_IP}:${PRIMARY_PORT} 成为 PRIMARY"
      break
    fi
    sleep 1
  done
fi

# 验证认证是否生效
echo "验证认证是否生效..."
if mongosh --quiet --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p ${ADMIN_PWD} --authenticationDatabase admin --eval "db.runCommand({connectionStatus:1})" | grep -q "authenticatedUsers"; then
  echo "认证已成功启用"
else
  echo "警告: 认证可能未正确启用"
fi

echo
echo "部署完成！信息汇总："
echo "-------------------------------"
echo "Base dir: ${BASE_DIR}"
for i in "${!ACTUAL_PORTS[@]}"; do
  idx=$((i+1)); port=${ACTUAL_PORTS[i]}
  echo "Node${idx}: data=${BASE_DIR}/node${idx}/data, log=${BASE_DIR}/node${idx}/logs/mongod.log, port=${port}"
done
echo "ReplicaSet name: ${REPL_NAME}"
echo "Admin user: ${ADMIN_USER}"
echo "Admin password: ${ADMIN_PWD}"
echo "Keyfile: ${KEYFILE}"
echo
echo "管理命令示例："
for i in "${!ACTUAL_PORTS[@]}"; do
  idx=$((i+1))
  echo "  systemctl status ${SERVICE_PREFIX}-${idx}.service"
done
echo
echo "连接测试信息："
echo "1. 连接到 PRIMARY 节点:"
echo "   mongosh --host ${HOST_IP} --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p '${ADMIN_PWD}' --authenticationDatabase admin"
echo
echo "2. 副本集状态检查:"
echo "   mongosh --host ${HOST_IP} --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p '${ADMIN_PWD}' --authenticationDatabase admin --eval \"rs.status()\""
echo
echo "3. 节点列表检查:"
echo "   mongosh --host ${HOST_IP} --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p '${ADMIN_PWD}' --authenticationDatabase admin --eval \"rs.conf().members\""
echo
echo "4. 数据库列表检查:"
echo "   mongosh --host ${HOST_IP} --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p '${ADMIN_PWD}' --authenticationDatabase admin --eval \"show dbs\""
echo
echo "5. 创建测试数据库:"
echo "   mongosh --host ${HOST_IP} --port ${PRIMARY_PORT} -u ${ADMIN_USER} -p '${ADMIN_PWD}' --authenticationDatabase admin --eval \"use testdb; db.test.insertOne({name: 'test'}); db.test.find()\""
echo
echo "注意："
echo " - 脚本启用了 keyFile 与 authorization，用于生产环境更安全。"
echo " - 若要开放防火墙端口，请自行调整防火墙策略。"
echo " - 本脚本在单机上模拟三节点，生产环境建议不同物理/虚拟机部署。"
echo
# 生成 start/stop 管理脚本
cat > ${BASE_DIR}/mongo-cluster-start.sh <<EOF
#!/bin/bash
systemctl start ${SERVICE_PREFIX}-1.service
systemctl start ${SERVICE_PREFIX}-2.service
systemctl start ${SERVICE_PREFIX}-3.service
EOF
cat > ${BASE_DIR}/mongo-cluster-stop.sh <<EOF
#!/bin/bash
systemctl stop ${SERVICE_PREFIX}-3.service
systemctl stop ${SERVICE_PREFIX}-2.service
systemctl stop ${SERVICE_PREFIX}-1.service
EOF
chmod +x ${BASE_DIR}/mongo-cluster-start.sh ${BASE_DIR}/mongo-cluster-stop.sh
echo "一键启动脚本： ${BASE_DIR}/mongo-cluster-start.sh"
echo "一键停止脚本： ${BASE_DIR}/mongo-cluster-stop.sh"