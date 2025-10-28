CentOS 7 添加虚拟 IP（配置文件方式）

步骤 1：确定主网络接口名称

ip addr

找到主接口名称（如 p2p2），记录备用。

步骤 2：创建虚拟接口配置文件

1. 进入配置目录：
   cd /etc/sysconfig/network-scripts/
   ➜ cat ifcfg-p2p2 
    TYPE=Ethernet
    PROXY_METHOD=none
    BROWSER_ONLY=no
    BOOTPROTO=static
    DEFROUTE=yes
    IPV4_FAILURE_FATAL=no
    IPV6INIT=yes
    IPV6_AUTOCONF=yes
    IPV6_DEFROUTE=yes
    IPV6_FAILURE_FATAL=no
    IPV6_ADDR_GEN_MODE=stable-privacy
    NAME=p2p2
    UUID=8eeda5f6-6c59-4dc2-9107-be6d72dc2c6f
    DEVICE=p2p2
    ONBOOT=yes
    IPADDR=192.168.0.4
    NETMASK=255.255.255.0

2. 复制主接口配置（以 ens33 为例）：
   cp ifcfg-p2p2 ifcfg-p2p2:0
   cp ifcfg-p2p2 ifcfg-p2p2:1
   cp ifcfg-p2p2 ifcfg-p2p2:2
   cp ifcfg-p2p2 ifcfg-p2p2:3
   

步骤 3：修改虚拟接口配置

编辑配置文件：
vi ifcfg-p2p2:0

192.168.0.4

修改以下内容（示例 IP：192.168.1.100/24）：
DEVICE=p2p2:0           # 虚拟接口名称
BOOTPROTO=static        # 静态IP
IPADDR=192.168.0.41      # 虚拟IP地址
NETMASK=255.255.255.0   # 子网掩码（或 PREFIX=24）
ONBOOT=yes              # 开机自启

DEVICE=p2p2:1           # 虚拟接口名称
BOOTPROTO=static        # 静态IP
IPADDR=192.168.0.42      # 虚拟IP地址
NETMASK=255.255.255.0   # 子网掩码（或 PREFIX=24）
ONBOOT=yes              # 开机自启

DEVICE=p2p2:2           # 虚拟接口名称
BOOTPROTO=static        # 静态IP
IPADDR=192.168.0.43      # 虚拟IP地址
NETMASK=255.255.255.0   # 子网掩码（或 PREFIX=24）
ONBOOT=yes              # 开机自启

DEVICE=p2p2:3           # 虚拟接口名称
BOOTPROTO=static        # 静态IP
IPADDR=192.168.0.44     # 虚拟IP地址
NETMASK=255.255.255.0   # 子网掩码（或 PREFIX=24）
ONBOOT=yes              # 开机自启

关键修改：
• 删除原文件中的 UUID 和 HWADDR 行（避免冲突）

• 确保 NAME 字段唯一（如 NAME="ens33-virtual"）

步骤 4：重启网络服务

systemctl restart network


步骤 5：验证配置

1. 检查虚拟 IP：
   ip addr show ens33:0
   
   输出应包含 192.168.1.100

2. 测试连通性：
   ping -c 4 192.168.1.100
   

注意事项

1. IP 冲突  
   确保虚拟 IP 未被局域网其他设备使用。

2. 子网一致性  
   虚拟 IP 必须与主接口在同一子网（如主 IP 192.168.1.10/24，虚拟 IP 192.168.1.100/24）。

3. 防火墙  
   如需通过虚拟 IP 访问服务：
   firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.100" accept' --permanent
   firewall-cmd --reload
   
4. 故障排查  
   查看日志：
   journalctl -xe -u network.service