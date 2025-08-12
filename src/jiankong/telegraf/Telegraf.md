
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
 