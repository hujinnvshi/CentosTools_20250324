给我Centos添加swap的完整操作步骤

注意事项:
1. 如需关闭swap: swapoff -v /old-data/centos_swap/swapfile
2. 如需完全移除swap:
   swapoff -v /old-data/centos_swap/swapfile
   sed -i '\|^/old-data/centos_swap/swapfile|d' /etc/fstab
   rm -f /old-data/centos_swap/swapfile
3. 如需查看swap使用情况: free -h 或 swapon --show