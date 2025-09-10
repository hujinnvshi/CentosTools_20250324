# 1. CPU使用率_Checked
sum by (instance)(
    node_cpu_scaling_frequency_hertz{instance="172.16.47.63:9100"}/node_cpu_frequency_max_hertz{instance="172.16.47.63:9100"}
)
# 2. CPU_Checked
sum by (instance)(
    node_cpu_scaling_frequency_hertz{instance="172.16.47.63:9100"}
)

# =============================================
# 内存监控 (对应 vSphere 内存指标) Checked
# =============================================

# 1. 内存使用率百分比
( node_memory_MemTotal_bytes{instance="172.16.47.63:9100"} - node_memory_MemFree_bytes{instance="172.16.47.63:9100"} 
- node_memory_Buffers_bytes{instance="172.16.47.63:9100"} - node_memory_Cached_bytes{instance="172.16.47.63:9100"}) 
/ node_memory_MemTotal_bytes{instance="172.16.47.63:9100"} * 100

# 2. Swap 使用量 (GB)
(node_memory_SwapTotal_bytes{instance="172.16.47.63:9100"} - node_memory_SwapFree_bytes{instance="172.16.47.63:9100"})/ 1024/1024/1024

# 3. 已消耗内存 (GB)
(node_memory_MemTotal_bytes{instance="172.16.47.63:9100"} - node_memory_MemFree_bytes{instance="172.16.47.63:9100"}) / 1024/1024/1024

# 4. 活跃内存 (GB)
node_memory_Active_bytes{instance="172.16.47.63:9100"} / 1024/1024/1024

# 5. 共享内存 (GB)
node_memory_Shmem_bytes{instance="172.16.47.63:9100"} / 1024/1024/1024

# =============================================
# 磁盘监控 (对应 vSphere 磁盘指标)
# =============================================

# 1. 磁盘使用率百分比 (对应 vsphere_vm_disk_usage_average)
100 - (node_filesystem_avail_bytes{instance="172.16.47.63:9100",mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{instance="172.16.47.63:9100",mountpoint="/",fstype!="rootfs"} * 100)

# 2. 磁盘最大延迟 (ms) (对应 vsphere_vm_disk_maxTotalLatency_latest)
sum by (instance)(
    rate(node_disk_io_time_seconds_total{instance="172.16.47.63:9100"}[5m]) * 1000
)
# 3. 读取 IOPS
sum by (instance)(
    rate(node_disk_reads_completed_total{instance="172.16.47.63:9100"}[5m])
)
# 4. 写入 IOPS
sum by (instance)(
    rate(node_disk_writes_completed_total{instance="172.16.47.63:9100"}[5m])
)

# 5. 读取吞吐量 (MB/s)
sum by (instance)(
    rate(node_disk_read_bytes_total{instance="172.16.47.63:9100"}[5m]) /1024/1024
)
# 6. 写入吞吐量 (MB/s)
sum by (instance)(
    rate(node_disk_written_bytes_total{instance="172.16.47.63:9100"}[5m]) /1024/1024
)

# =============================================
# 网络监控 (对应 vSphere 网络指标) Checked
# =============================================

# 1. 接收吞吐量 (MB/s)
sum by (instance)(
rate(node_network_receive_bytes_total{instance="172.16.47.63:9100",device!~"lo|bond.*"}[5m]) / 1024/1024
)
# 2. 发送吞吐量 (MB/s)
sum by (instance)(
rate(node_network_transmit_bytes_total{instance="172.16.47.63:9100",device!~"lo|bond.*"}[5m]) / 1024/1024
)