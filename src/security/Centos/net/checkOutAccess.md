我需要你编写一个适用于 CentOS Linux release 7.9.2009 (Core) 系统环境，且基于 Python 2.7 的脚本。该脚本需实现以下功能：

1. **网络连接信息排查**：排查当前所有外部连接的 IP 地址，以及这些外部 IP 所连接到本地的端口。需要排除本地 IP 地址，包括 IPv6 地址、127.0.0.1 和 ::1。
2. **数据整理与排序**：将获取到的外部 IP 地址及其对应的本地端口数据进行整理，按照本地端口从小到大的顺序排序，形成清晰、结构完整的格式，方便后续查看。
3. **数据保存**：把整理好的数据保存到名为 `netoutinfo_yyyymmddhh24miss.md` 的文件中，该文件需放置在 `/var/www/html` 目录下，以便其他用户查看。
4. **定时执行设置**：需要提供设置该脚本定时执行的方法，从而实现周期性地生成网络状态报告。
请提供满足上述需求的 Python 2.7 脚本。 



以下是满足您需求的 Python 2.7 脚本，生成 Markdown 格式的网络连接报告：

```python
#!/usr/bin/env python2.7
# -*- coding: utf-8 -*-
import os
import sys
import socket
import psutil
import datetime
from collections import defaultdict

def is_local_ip(ip):
    """Check if IP is local"""
    if ip == "127.0.0.1" or ip == "::1":
        return True
    
    try:
        # Check IPv6 addresses
        if ":" in ip:
            return True
        
        # Get all NIC IPs
        for interface, addrs in psutil.net_if_addrs().items():
            for addr in addrs:
                if addr.family == socket.AF_INET and addr.address == ip:
                    return True
    except:
        pass
    
    return False

def get_external_connections():
    """Get external connection info"""
    connections = defaultdict(list)
    
    for conn in psutil.net_connections(kind='inet'):
        # Only ESTABLISHED connections
        if conn.status != 'ESTABLISHED':
            continue
        
        # Validate remote address
        if not conn.raddr:
            continue
        
        # Filter local IPs
        if is_local_ip(conn.raddr.ip):
            continue
        
        # Group by local port
        local_port = conn.laddr.port
        connections[local_port].append({
            'local_port': local_port,
            'local_ip': conn.laddr.ip,
            'remote_ip': conn.raddr.ip,
            'remote_port': conn.raddr.port,
            'pid': conn.pid,
            'program': psutil.Process(conn.pid).name() if conn.pid else 'Unknown'
        })
    
    # Sort by local port
    return dict(sorted(connections.items()))

def generate_md_report(connections):
    """Generate MD report"""
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    filename = "/var/www/html/netoutinfo_{}.md".format(
        datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
    # Add UTF-8 BOM
    md_content = u"\ufeff# External Network Connections Report\n\n"
    md_content += u"**Report Time**: {}\n\n".format(current_time)
    
    if not connections:
        md_content += "## Scan Results\n\nNo external connections detected"
    else:
        # Summary
        total_connections = sum(len(conns) for conns in connections.values())
        unique_ips = set()
        for port, conns in connections.items():
            for conn in conns:
                unique_ips.add(conn['remote_ip'])
        
        md_content += "## Summary\n"
        md_content += "- Total Connections: {}\n".format(total_connections)
        md_content += "- Unique IP Count: {}\n\n".format(len(unique_ips))
        
        # Connection details
        md_content += "## Connection Details (Sorted by Local Port)\n"
        for port in sorted(connections.keys()):
            conns = connections[port]
            md_content += "### Local Port: {}\n".format(port)
            md_content += "| Local IP | Remote IP | Remote Port | PID | Program |\n"
            md_content += "|---------|-----------|-------------|-----|---------|\n"
            
            for conn in conns:
                md_content += "| {} | {} | {} | {} | {} |\n".format(
                    conn['local_ip'], 
                    conn['remote_ip'],
                    conn['remote_port'],
                    conn['pid'] if conn['pid'] else 'N/A',
                    conn['program']
                )
            md_content += "\n"
    
    try:
        import codecs
        with codecs.open(filename, 'w', encoding='utf-8') as f:
            f.write(md_content)
        return filename
    except Exception as e:
        print("Failed to save report: {}".format(e))
        return None

def main():
    """Main function"""
    try:
        # Set locale
        os.environ['LC_ALL'] = 'en_US.UTF-8'
        os.environ['LANG'] = 'en_US.UTF-8'
        
        # Check root
        if os.geteuid() != 0:
            print("Please run this script with root privileges")
            sys.exit(1)
        
        # Ensure output dir
        if not os.path.exists("/var/www/html"):
            os.makedirs("/var/www/html")
        
        # Get connections
        connections = get_external_connections()
        
        # Generate report
        filename = generate_md_report(connections)
        
        if filename:
            print("Report saved to: {}".format(filename))
            # Create symlink
            latest_link = "/var/www/html/latest_netout_report.md"
            if os.path.exists(latest_link):
                os.remove(latest_link)
            os.symlink(filename, latest_link)
            print("Latest report link: {}".format(latest_link))

    except Exception as e:
        print("Execution error: {}".format(e))
        sys.exit(1)

if __name__ == "__main__":
    main()
```

### 定时任务设置脚本
```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/net/setup_cron.sh
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 安装依赖
install_deps() {
    log "安装Python依赖..."
    pip2.7 install psutil || error "依赖安装失败"
}

# 设置定时任务
setup_cron() {
    log "配置定时任务..."
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/python2.7 /usr/local/bin/check_out_access.py") | crontab -
}

# 主流程
main() {
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        error "请使用root权限运行"
    fi
    
    install_deps
    setup_cron
    
    log "定时任务已设置（每5分钟执行一次）"
    log "最新报告位置: /var/www/html/latest_netout_report.md"
}

main
```

使用方法：
```bash
# 1. 安装依赖
sudo pip2.7 install psutil

# 2. 赋予脚本执行权限
sudo chmod +x /Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/net/check_out_access.py
sudo chmod +x /Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/net/setup_cron.sh

# 3. 设置定时任务
sudo /Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/net/setup_cron.sh
```

脚本特点：
1. 生成结构清晰的Markdown报告
2. 包含摘要统计和详细连接表格
3. 自动维护最新报告软链接
4. 每5分钟自动更新一次
5. 完整的权限检查和错误处理

生成的Markdown报告示例：
```markdown
# 外部网络连接报告

**生成时间**: 2025-04-10 11:30:45

## 摘要
- 总连接数: 8
- 唯一IP数量: 3

## 连接详情（按本地端口排序）
### 本地端口: 80
| 本地IP | 远程IP    | 远程端口 | 进程ID | 程序名   |
|--------|-----------|----------|--------|----------|
| 10.0.0.5 | 203.0.113.1 | 54321    | 1234   | curl     |
```