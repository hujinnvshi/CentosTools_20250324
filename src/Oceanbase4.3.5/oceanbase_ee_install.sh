# 如部署 OAT 失败，按本⽂档最后 "删除 OAT Docker" ，重新运⾏如下步骤
# 输出 oat image 的名字，如未输出任何内容检查 docker images
oat_image=`docker images | grep oat | awk '{printf $1":"$2"\n"}'` && echo $oat_image

# 注意以下⼏⾏是⼀个命令，⼀起复制即可
docker run -d --net=host --name oat \
 -v /data/docker_oat_data1:/data \
 -p 7000:7000 \
 --restart on-failure:5 \
 $oat_image

docker ps

# 查看 OAT ⽇志，或 docker logs <CONTAINER ID>
docker logs -f oat

# 等⼏分钟后，7000 在监控后进⾏⼀步
netstat -tlnp|grep 7000