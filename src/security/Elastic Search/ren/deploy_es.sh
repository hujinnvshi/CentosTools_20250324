#!/bin/bash

# 配置信息
ES_VERSIONS=("7.10.2" "7.6.2")
ES_PORTS=("8200" "8201")
ES_USER="es_admin"
ES_PASS="Secsmart#612"
BASE_DIR="/data"

# 创建用户
create_user() {
    useradd ${ES_USER}
    echo "${ES_PASS}" | passwd ${ES_USER} --stdin
}

# 部署单个实例
deploy_instance() {
    local version=$1
    local port=$2
    local es_home="${BASE_DIR}/es-${version}"
    
    # 创建目录
    mkdir -p ${es_home}/{data,logs,config}
    chown -R ${ES_USER}:${ES_USER} ${es_home}
    
    # 配置文件
    cat > ${es_home}/config/elasticsearch.yml << EOF
cluster.name: es-${version}
node.name: node-1
path.data: ${es_home}/data
path.logs: ${es_home}/logs
network.host: 0.0.0.0
http.port: ${port}
xpack.security.enabled: true
EOF

    # 设置权限
    chmod -R 755 ${es_home}
}

# 主函数
main() {
    # 创建用户
    create_user
    
    # 部署实例
    for i in "${!ES_VERSIONS[@]}"; do
        deploy_instance "${ES_VERSIONS[$i]}" "${ES_PORTS[$i]}"
    done
}

main