你是一名杰出的应用开发工程师，
我需要在Centos7.9 上安装VictoriaMetrics单实例，配置为系统服务，自动开启，并配置为开机启动。
并生成基本的操作命令到readme.md文件。
帮我生成完备的一键部署安装配置的bash脚本,生成好后给我。
要求逻辑清晰，注释简洁，没有语法错误。

c

# 远程写入配置 - 这是关键！重新启动后生效
# export VM_REMOTE_WRITE_CONFIG="172.16.47.185:8428"

remote_write:
  - url: "http://http://172.16.47.185:8428/api/v1/write"
    queue_config:
      max_samples_per_send: 10000
      capacity: 10000
      max_shards: 10

修改启动文件增加：
sudo -u victoriametrics /usr/local/bin/victoria-metrics \
--httpListenAddr=:8428 \
--storageDataPath=/var/lib/victoriametrics \
--retentionPeriod=300h \
--relabelConfig=/etc/victoriametrics/relabel.yml \
--loggerFormat=json \
--kafka.topic=prometheus-metrics \
--kafka.brokers=172.16.47.185:9092