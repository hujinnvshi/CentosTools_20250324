# 步骤2：规划镜像数据存储路径
rm -fr /data/oracle19c/oradata
mkdir -p /data/oracle19c/oradata
cd /data/oracle19c
chmod -R 777 /data/oracle19c

# 步骤3：实例化镜像参数修改
docker run -it \
--name="Oracle19c" \
--privileged \
--restart=always \
-p 15312:1521 \
-p 15313:5500 \
-v /data/oracle19c/oradata:/opt/oracle/oradata \
-e ORACLE_ALLOW_REMOTE=true \
-d heartu41/oracle19c

docker logs -f Oracle19c
docker stop Oracle19c
docker rm Oracle19c
docker exec -it Oracle19c /bin/bash

sqlplus sys/Secsmart#612@ORCLCDB as sysdba
sqlplus sys/Secsmart#612@ORCLPDB1 as sysdba
