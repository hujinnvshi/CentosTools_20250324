我需要在 CentOS Linux release 7.9.2009 (Core) 系统上部署一个 `httpd` 服务器。希望提供一个一键执行的 Bash 脚本，该脚本能够完成以下操作：
1. 自动安装并启动 `httpd` 服务器。
2. 以 `/var/www/html/index.html` 文件内容作为服务器的首页展示内容。
3. `/var/www/html/index.html` 文件的内容为 `/var/www/html/` 目录下文件和文件夹的树状结构。
4. 此树状结构可以根据 `/var/www/html/` 目录下文件夹和文件的状态实时更新。
请提供满足上述需求的一键执行 Bash 脚本。 

我来为你提供一个满足需求的一键部署 httpd 服务器的脚本，包含自动更新目录树状结构的功能：
http://172.16.48.28/

```
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用root权限运行此脚本"
    fi
}

# 安装httpd和tree工具
install_httpd() {
    log "安装httpd和依赖..."
    yum install -y httpd tree apr apr-util || error "安装httpd失败"
    yum install -y httpd httpd-tools apr apr-util apr-devel apr-util-devel || error "安装httpd失败"

    # 启动httpd服务
    systemctl start httpd
    systemctl enable httpd
    
    # 检查httpd状态
    if systemctl is-active httpd >/dev/null 2>&1; then
        log "httpd服务已成功启动"
    else
        error "httpd服务启动失败"
    fi
}

# 创建目录树生成脚本
create_tree_script() {
    log "创建目录树生成脚本..."
    cat > /usr/local/bin/update_html_tree.sh << 'EOF'
#!/bin/bash
# 生成HTML格式的目录树
generate_html_tree() {
    local html_file="/var/www/html/index.html"
    
    # 创建HTML头部
    cat > $html_file << 'HTML_HEAD'
<!DOCTYPE html>
<html>
<head>
    <title>目录结构 - /var/www/html/</title>
    <meta charset="utf-8">
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #ddd;
            padding-bottom: 10px;
        }
        pre {
            background-color: #fff;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 15px;
            overflow: auto;
            font-family: monospace;
            line-height: 1.4;
        }
        .timestamp {
            color: #666;
            font-style: italic;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <h1>目录结构: /var/www/html/</h1>
    <div class="timestamp">最后更新时间: $(date '+%Y-%m-%d %H:%M:%S')</div>
    <pre>
HTML_HEAD
    
    # 生成目录树并追加到HTML文件
    cd /var/www/html/ && tree -H "." -L 3 --noreport --charset utf-8 | tail -n +2 >> $html_file
    
    # 添加HTML尾部
    cat >> $html_file << 'HTML_FOOT'
    </pre>
</body>
</html>
HTML_FOOT
}

# 执行生成
generate_html_tree
EOF
    
    # 设置执行权限
    chmod +x /usr/local/bin/update_html_tree.sh
}

# 设置cron任务定期更新目录树
setup_cron() {
    log "设置定时更新任务..."
    
    # 创建cron任务（每分钟执行一次）
    (crontab -l 2>/dev/null | grep -v "update_html_tree.sh"; echo "* * * * * /usr/local/bin/update_html_tree.sh") | crontab -
    
    # 立即执行一次
    /usr/local/bin/update_html_tree.sh
}

# 配置SELinux和防火墙
configure_security() {
    log "配置安全设置..."
    
    # 配置SELinux
    if command -v sestatus >/dev/null 2>&1; then
        if sestatus | grep -q "enabled"; then
            log "设置SELinux允许httpd访问..."
            setsebool -P httpd_read_user_content 1
            restorecon -Rv /var/www/html/
        fi
    fi
    
    # 配置防火墙
    if systemctl is-active firewalld >/dev/null 2>&1; then
        log "配置防火墙允许http访问..."
        firewall-cmd --permanent --add-service=http
        firewall-cmd --reload
    fi
}

# 主函数
main() {
    log "开始部署httpd服务器..."
    
    check_root
    install_httpd
    create_tree_script
    setup_cron
    configure_security
    
    # 获取服务器IP地址
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    log "部署完成！"
    log "请访问 http://${SERVER_IP}/ 查看目录结构"
}

# 执行主函数
main
```

使用方法：
```bash
chmod +x install_httpd.sh
sudo ./install_httpd.sh
```

脚本功能说明：

1. 自动安装并启动 httpd 服务器
2. 创建一个更新脚本，生成美观的 HTML 格式目录树
3. 设置 cron 任务每分钟自动更新一次目录树
4. 配置必要的安全设置（SELinux 和防火墙）
5. 提供访问地址

特点：
- 目录树以美观的 HTML 格式展示
- 显示最后更新时间
- 自动定时更新，保持内容最新
- 完整的错误处理和日志输出
- 自动配置安全设置

注意：如果需要调整更新频率，可以修改 cron 设置。例如，改为每5分钟更新一次：
```bash
*/5 * * * * /usr/local/bin/update_html_tree.sh
```