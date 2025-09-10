# CPU
vsphere_vm_cpu_usage_average{vmname="C7.6-172.16.48.21-(hp.node1)"}
vsphere_vm_cpu_usagemhz_average{vmname="C7.6-172.16.48.21-(hp.node1)",cpu="instance-total"}/1000

# 内存
vsphere_vm_mem_usage_average{vmname="C7.6-172.16.48.21-(hp.node1)"}
vsphere_vm_mem_swapped_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024/1024
vsphere_vm_mem_consumed_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024/1024
vsphere_vm_mem_active_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024/1024
vsphere_vm_mem_shared_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024/1024

# 磁盘
vsphere_vm_disk_usage_average{vmname="C7.6-172.16.48.21-(hp.node1)"} / 100
vsphere_vm_disk_maxTotalLatency_latest{vmname="C7.6-172.16.48.21-(hp.node1)"}
vsphere_vm_disk_numberReadAveraged_average{vmname="C7.6-172.16.48.21-(hp.node1)"}
vsphere_vm_disk_numberWriteAveraged_average{vmname="C7.6-172.16.48.21-(hp.node1)"}
vsphere_vm_disk_read_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024
vsphere_vm_disk_write_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024

# 网络流量
sum by (vmname)(
    vsphere_vm_net_bytesRx_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024
)
sum by (vmname)(
    vsphere_vm_net_bytesTx_average{vmname="C7.6-172.16.48.21-(hp.node1)"}/1024
)