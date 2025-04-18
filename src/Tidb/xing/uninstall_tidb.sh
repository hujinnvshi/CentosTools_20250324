
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

# 关闭 TiDB 集群
CLUSTER_NAME="tidb-cluster"
TIDB_HOME="/data/tidb"

print_message "关闭 TiDB 集群..."
tiup cluster stop ${CLUSTER_NAME} --yes

# 等待集群关闭
print_message "等待集群启动..."
sleep 15

# 验证集群状态
print_message "验证集群状态..."
tiup cluster display ${CLUSTER_NAME}

# 删除集群
print_message "删除 TiDB 集群..."
tiup cluster destroy ${CLUSTER_NAME} --yes

# 删除相关目录
print_message "删除相关目录..."
rm -rf ${TIDB_HOME}