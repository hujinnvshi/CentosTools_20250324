export Version=6.0.4
export instance_name=mongo-${Version}
export instance_port=6012
echo "${instance_name}"

mkdir -p /data/mdb/${instance_name}/{db,config}
chmod -R 777 /data/mdb/${instance_name}

docker stop ${instance_name} 2>/dev/null || true
docker rm ${instance_name} 2>/dev/null || true

docker run -d \
--name ${instance_name} \
-p ${instance_port}:27017 \
--restart=always \
-e MONGO_INITDB_ROOT_USERNAME=admin \
-e MONGO_INITDB_ROOT_PASSWORD=Secsmart#612 \
-v /data/mdb/${instance_name}/db:/data/db \
-v /data/mdb/${instance_name}/config:/data/configdb \
192.168.245.10:8092/mongo:${Version}
sleep 10

docker exec -it ${instance_name} bash