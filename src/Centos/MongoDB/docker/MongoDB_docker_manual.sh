#!/bin/bash

export Version=4.2.14
export instance_name="mongo-${Version}"
export instance_port=6005

# 清理旧容器
docker stop ${instance_name} 2>/dev/null || true
docker rm ${instance_name} 2>/dev/null || true

# 创建目录结构
rm -fr /data/mdb/${instance_name} 2>/dev/null || true
mkdir -p /data/mdb/${instance_name}/{db,configdb,logs,run}

# 设置权限
chown -R 1000:1000 /data/mdb/${instance_name}
chmod -R 700 /data/mdb/${instance_name}
chmod 1777 /data/mdb/${instance_name}/run

# 创建自定义入口点脚本
cat > /data/mdb/${instance_name}/custom-entrypoint.sh <<'EOF'
#!/bin/bash
set -e

# 修复/tmp权限
chmod 1777 /tmp

# 执行原始入口点
exec /usr/local/bin/docker-entrypoint.sh "$@"
EOF
chmod +x /data/mdb/${instance_name}/custom-entrypoint.sh

# 启动容器
docker run -d \
  --name ${instance_name} \
  -p ${instance_port}:27017 \
  --restart=always \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD='Secsmart#612' \
  -v /data/mdb/${instance_name}/db:/data/db \
  -v /data/mdb/${instance_name}/configdb:/data/configdb \
  -v /data/mdb/${instance_name}/logs:/var/log/mongodb \
  -v /data/mdb/${instance_name}/run:/data/run \
  -v /data/mdb/${instance_name}/custom-entrypoint.sh:/custom-entrypoint.sh \
  --entrypoint=/custom-entrypoint.sh \
  mongo:${Version}

sleep 5

# docker exec -it ${instance_name} bash
# mongosh --host 192.168.20.61 --port 6012 -u admin -p 'Secsmart#612' --authenticationDatabase admin 

 Mongo_4.2.14
 0.0.0.0:6005
192.168.20.233:9002/mongo:4.2.14



 # 
docker run -it --name mongo509   --privileged   -p 6001:27017 --restart=always -e MONGO_INITDB_ROOT_USERNAME="rdb" -e MONGO_INITDB_ROOT_PASSWORD="Secsmart#612" -d mongo:5.0.9
docker run -it --name mongo4214  --privileged   -p 6001:27017 --restart=always -e MONGO_INITDB_ROOT_USERNAME="rdb" -e MONGO_INITDB_ROOT_PASSWORD="Secsmart#612" -d mongo:4.2.14
docker run -it --name mongo440   --privileged   -p 6002:27017 --restart=always -e MONGO_INITDB_ROOT_USERNAME="rdb" -e MONGO_INITDB_ROOT_PASSWORD="Secsmart#612" -d mongo:4.4.0 
docker run -it --name mongo361   --privileged   -p 9003:27017 --restart=always -e MONGO_INITDB_ROOT_USERNAME="rdb" -e MONGO_INITDB_ROOT_PASSWORD="Secsmart#612" -d mongo:3.6.1