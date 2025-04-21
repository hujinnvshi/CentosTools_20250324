使用
docker images | grep -v 'kubesphere\|other-keyword' 
查看镜像列表

将检索到的镜像
使用docker save 保存镜像,命名方式使用：REPOSITORY_TAG.tar.gz

scp拷贝到/data/docker/images_copy路径
IP地址：172.16.48.191 账户：root 密码： Secsmart#612

恢复镜像
docker load -i /data/docker/images_copy/REPOSITORY_TAG.tar.gz
镜像名称保持一致
导入完成后校验下

给我下导出，和导入的两个一键执行脚本。
注意需要有清晰的逻辑结构，和必要的注释和运行步骤。