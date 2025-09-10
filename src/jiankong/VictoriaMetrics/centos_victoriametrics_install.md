你是一名杰出的应用开发工程师，
我需要在Centos7.9 上安装VictoriaMetrics单实例，配置为系统服务，自动开启，并配置为开机启动。
并生成基本的操作命令到readme.md文件。
帮我生成完备的一键部署安装配置的bash脚本,生成好后给我。
要求逻辑清晰，注释简洁，没有语法错误。

sudo -u victoriametrics /usr/local/bin/victoria-metrics \
--httpListenAddr=:8428 \
--storageDataPath=/var/lib/victoriametrics \
--retentionPeriod=300h \
--relabelConfig=/etc/victoriametrics/relabel.yml \
--loggerFormat=json &