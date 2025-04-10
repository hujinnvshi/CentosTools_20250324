我希望在 CentOS Linux release 7.9.2009 (Core) 系统环境下，编写一个 Python 2.7 脚本实现以下功能：
检索当前系统所有的 IP 地址以及处于监听状态、向外暴露的端口信息。
排查当前所有外部连接的 IP 地址，以及与之对应的接入本地的端口，并按照本地端口从小到大的顺序进行排序。
将获取到的上述数据整理成清晰、结构完整的格式，方便后续查看，然后保存至名为 netinfo_yyyymmddhh24miss.txt 的文件中。
此外，后续还需要设置该脚本定时执行，以便周期性地生成网络状态报告。请帮我提供满足上述需求的 Python 2.7 脚本。

以下是满足您需求的 Python 2.7 脚本，用于检索系统的网络信息并保存到文件中：

```
#!/usr/bin/env python2.7
# -*- coding: utf-8 -*-

import os
import socket
import psutil
import datetime
from collections import defaultdict

def get_ip_addresses():
    """获取系统所有IP地址"""
    ip_list = []
    for interface, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if addr.family == socket.AF_INET:
                ip_list.append({
                    'interface': interface,
                    'ip': addr.address,
                    'netmask': addr.netmask
                })
    return ip_list

def get_listening_ports():
    """获取监听状态的端口"""
    listening_ports = []
    for conn in psutil.net_connections(kind='inet'):
        if conn.status == 'LISTEN':
            listening_ports.append({
                'port': conn.laddr.port,
                'ip': conn.laddr.ip,
                'pid': conn.pid,
                'program': psutil.Process(conn.pid).name() if conn.pid else 'Unknown'
            })
    return sorted(listening_ports, key=lambda x: x['port'])

def get_external_connections():
    """获取外部连接信息"""
    connections = defaultdict(list)
    for conn in psutil.net_connections(kind='inet'):
        if conn.status == 'ESTABLISHED' and conn.raddr:
            connections[conn.laddr.port].append({
                'local_port': conn.laddr.port,
                'local_ip': conn.laddr.ip,
                'remote_ip': conn.raddr.ip,
                'remote_port': conn.raddr.port,
                'pid': conn.pid,
                'program': psutil.Process(conn.pid).name() if conn.pid else 'Unknown'
            })
    return dict(sorted(connections.items()))

def format_report(ip_list, listening_ports, connections):
    """格式化报告内容"""
    report = []
    report.append("=" * 80)
    report.append("网络状态报告")
    report.append("生成时间: {}".format(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
    report.append("=" * 80)
    
    report.append("\n1. 系统IP地址信息:")
    report.append("-" * 40)
    for ip_info in ip_list:
        report.append("接口: {}\nIP地址: {}\n子网掩码: {}\n".format(
            ip_info['interface'], ip_info['ip'], ip_info['netmask']))
    
    report.append("\n2. 监听端口信息:")
    report.append("-" * 40)
    for port_info in listening_ports:
        report.append("端口: {}\nIP地址: {}\n程序: {} (PID: {})\n".format(
            port_info['port'], port_info['ip'], port_info['program'], port_info['pid']))
    
    report.append("\n3. 外部连接信息:")
    report.append("-" * 40)
    for local_port, conn_list in connections.items():
        for conn in conn_list:
            report.append("本地端口: {}\n本地IP: {}\n远程IP: {}:{}\n程序: {} (PID: {})\n".format(
                conn['local_port'], conn['local_ip'], 
                conn['remote_ip'], conn['remote_port'],
                conn['program'], conn['pid']))
            report.append("-" * 20)
    
    return "\n".join(report)

def save_report(content):
    """保存报告到文件"""
    filename = "netinfo_{}.txt".format(datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
    try:
        with open(filename, 'w') as f:
            f.write(content)
        return filename
    except Exception as e:
        print("保存报告失败: {}".format(e))
        return None

def main():
    """主函数"""
    try:
        # 检查权限
        if os.geteuid() != 0:
            print("请使用root权限运行此脚本")
            sys.exit(1)
            
        # 收集信息
        ip_list = get_ip_addresses()
        listening_ports = get_listening_ports()
        connections = get_external_connections()
        
        # 生成报告
        report_content = format_report(ip_list, listening_ports, connections)
        
        # 保存报告
        filename = save_report(report_content)
        if filename:
            print("报告已保存至: {}".format(filename))
            
    except Exception as e:
        print("执行出错: {}".format(e))
        sys.exit(1)

if __name__ == "__main__":
    main()
```

### 定时执行设置

要定期执行此脚本，可以使用 `cron` 设置定时任务。以下是设置步骤：

1. 打开 `crontab` 编辑器：
   ```bash
   crontab -e
   ```

2. 添加以下行以每小时执行一次脚本（假设脚本路径为 `/root/check_net_access.py`）：
   ```bash
   0 * * * * /usr/bin/python2.7 /root/check_net_access.py
   ```

3. 保存并退出编辑器。

这样，脚本将每小时自动运行一次，生成网络状态报告。请确保 `psutil` 模块已安装，可以通过以下命令安装：

```bash
pip2.7 install psutil
```

注意：请确保脚本路径和 Python 解释器路径正确。