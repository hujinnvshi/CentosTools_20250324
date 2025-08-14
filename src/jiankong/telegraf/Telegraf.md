
我在使用Centos7.9 系统，需要使用Telegraf进行监控，请给我详细操作步骤，
你是一名卓越的运维专家，帮我部署Telegraf，并完成配置，普罗米修斯和grafana已经部署完成，
请给我详细的操作步骤，要求逻辑正确，注释简洁，没有语法错误。请将一键配置部署脚本给我
Exsi 7.1 版本
172.16.48.11
172.16.48.12
172.16.48.13
172.16.48.14
172.16.48.15
172.16.48.17
172.16.48.18
root / Secsmart

# 手动测试
 telegraf --config /etc/telegraf/telegraf.d/esxi.conf --test
# 测试展示
 sum by (vcenter) (vsphere_vm_virtualDisk_write_average)
 sum by (vcenter) (vsphere_vm_virtualDisk_read_average)
 
 # 查看版本
 telegraf --version
 Telegraf 1.35.3 (git: HEAD@b66e5091)
# 配置文件
cat /etc/telegraf/telegraf.d/esxi.conf

我在使用 Telegraf 1.35.3 来时监控exsi主机，并上传到普罗米修斯，我的配置文件如下，请帮我检查我的配置是否有可以优化的点，二是还没有找到合适的grafana可视化界面，请帮我找一个。
cat /etc/telegraf/telegraf.d/esxi.conf
[agent]
  interval = "60s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "5s"

[[inputs.vsphere]]
  vcenters = [
      "https://172.16.48.11/sdk",  "https://172.16.48.12/sdk",  "https://172.16.48.13/sdk",  "https://172.16.48.14/sdk",  "https://172.16.48.15/sdk",  "https://172.16.48.17/sdk",  "https://172.16.48.18/sdk"
  ]
  
  # 认证信息
  username = "root"
  password = 'Secsmart#612'
  
  # 安全设置
  insecure_skip_verify = true
  
  # 采集间隔
  interval = "60s"
  
  # 高级设置
  max_query_metrics = 256
  timeout = "30s"
  host_include = ["/"]
  
[[outputs.prometheus_client]]
  # 监听地址和端口
  listen = "0.0.0.0:9273"
  
  # 指标格式版本
  metric_version = 2
  
  # 指标过期时间
  expiration_interval = "120s"
  
  # 添加路径
  path = "/metrics"
  
  # 添加标签
  [outputs.prometheus_client.tags]
    environment = "production"
    location = "datacenter1"

