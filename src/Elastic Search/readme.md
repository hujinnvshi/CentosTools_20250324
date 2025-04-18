在Centos7系统
单机部署了Elasticsearch
现在正在后台运行，帮我整理下该进程的的部署文件夹框架
我目前希望使用api和jdbc的方式来访问该进程
请提供给我必要的访问端口，和访问示例
请提供必要的检测Bash脚本给我

# REST API
curl -XGET -u "es_admin:Secsmart#612" "http://localhost:9200/_cluster/health?pretty"

# JDBC URL
jdbc:elasticsearch://localhost:9200/?user=es_admin&password=Secsmart#612