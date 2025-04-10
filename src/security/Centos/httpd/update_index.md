我来帮你生成 `update_html_tree.sh` 脚本，这个脚本用于自动更新 httpd 服务器的目录树结构：

```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/httpd/update_html_tree.sh
#!/bin/bash

# 生成HTML格式的目录树
generate_html_tree() {
    local html_file="/var/www/html/index.html"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 创建HTML头部
    cat > $html_file << HTML_HEAD
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
    <div class="timestamp">最后更新时间: ${current_time}</div>
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
```

使用方法：
1. 将此脚本保存到 `/usr/local/bin/update_html_tree.sh`
2. 设置执行权限：`chmod +x /usr/local/bin/update_html_tree.sh`
3. 手动执行：`/usr/local/bin/update_html_tree.sh`
4. 或设置定时任务：`crontab -e` 然后添加 `* * * * * /usr/local/bin/update_html_tree.sh`

这个脚本会生成一个美观的 HTML 页面，显示 `/var/www/html/` 目录的树状结构，并包含最后更新时间。