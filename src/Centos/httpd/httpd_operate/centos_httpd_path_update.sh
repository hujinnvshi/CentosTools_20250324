#!/usr/bin/env bash

# 简洁优雅的目录树展示脚本
DOCUMENT_ROOT="/var/www/html"
INDEX_FILE="${DOCUMENT_ROOT}/index.html"
TREE_DEPTH=3

# 生成更美观的目录树结构
generate_tree_structure() {
    cd "$DOCUMENT_ROOT" >/dev/null 2>&1 || return
    
    # 生成树形结构的HTML
    local html_output=""
    local indent=""
    for ((i=0; i<=$TREE_DEPTH; i++)); do
        while IFS= read -r path; do
            local depth=$(echo "$path" | grep -o '/' | wc -l)
            local indent_size=$(( (depth - 1) * 30 ))
            local name=$(basename "$path")
            
            if [[ $depth == $i ]]; then
                if [ -d "$path" ]; then
                    html_output+="<div class='tree-item depth-$depth' data-depth='$depth' data-path='$path'>"
                    html_output+="  <div class='folder-header' onclick=\"toggleFolder(this.parentNode)\">"
                    html_output+="    <span class='icon'><i class='far fa-folder'></i></span>"
                    html_output+="    <span class='name'>$name/</span>"
                    html_output+="    <span class='toggle'><i class='fas fa-chevron-down'></i></span>"
                    html_output+="  </div>"
                    html_output+="  <div class='folder-content'>"
                else
                    html_output+="<div class='file-item depth-$depth' data-depth='$depth'>"
                    html_output+="  <span class='icon'><i class='far fa-file'></i></span>"
                    html_output+="  <a href='${path#$DOCUMENT_ROOT}' download class='name'>$name</a>"
                    html_output+="</div>"
                fi
            fi
        done < <(find . -maxdepth $TREE_DEPTH -mindepth 1 | sed 's|^\./||' | sort)
        
        # 关闭目录块
        if [[ $i > 0 ]]; then
            indent="</div></div>"
            html_output+=$indent
        fi
    done
    
    echo "$html_output"
}

# 生成HTML页面
generate_html_tree() {
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 获取当前目录统计信息
    local dir_count=$(find "$DOCUMENT_ROOT" -maxdepth $TREE_DEPTH -type d 2>/dev/null | wc -l)
    local file_count=$(find "$DOCUMENT_ROOT" -maxdepth $TREE_DEPTH -type f 2>/dev/null | wc -l)
    local total_size=$(du -sh "$DOCUMENT_ROOT" 2>/dev/null | awk '{print $1}')
    
    # 生成HTML内容
    cat > "$temp_file" <<HTML_HEAD
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>目录结构 | ${DOCUMENT_ROOT}</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --bg-color: #f8f9fa;
            --card-bg: #ffffff;
            --border-color: #e9ecef;
            --primary: #3a86ff;
            --secondary: #ff006e;
            --text: #212529;
            --text-secondary: #6c757d;
            --folder-open: #f5f5f5;
            --tree-indent: 30px;
        }
        
        .dark-theme {
            --bg-color: #121212;
            --card-bg: #1e1e1e;
            --border-color: #444;
            --primary: #64b5f6;
            --secondary: #ff7597;
            --text: #f8f9fa;
            --text-secondary: #adb5bd;
            --folder-open: #2a2a2a;
        }
        
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        
        body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background-color: var(--bg-color);
            color: var(--text);
            line-height: 1.6;
            padding: 1.5rem;
            transition: all 0.3s ease;
        }
        
        .container {
            max-width: 900px;
            margin: 0 auto;
        }
        
        .directory-card {
            background: var(--card-bg);
            border-radius: 8px;
            box-shadow: 0 0.25rem 0.75rem rgba(0, 0, 0, 0.05);
            overflow: hidden;
        }
        
        .card-header {
            padding: 1.5rem;
            background: linear-gradient(to right, var(--primary), #8338ec);
            color: white;
        }
        
        .header-content {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 1rem;
        }
        
        h1 {
            font-size: 1.5rem;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }
        
        h1 i {
            font-size: 1.25em;
        }
        
        .meta-stats {
            display: flex;
            gap: 1rem;
            font-size: 0.9rem;
            flex-wrap: wrap;
        }
        
        .stat-item {
            background: rgba(255, 255, 255, 0.2);
            padding: 0.5rem 0.75rem;
            border-radius: 20px;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            min-width: 120px;
        }
        
        .theme-toggle {
            background: none;
            border: none;
            color: white;
            cursor: pointer;
            font-size: 1.25rem;
            transition: transform 0.3s;
        }
        
        .theme-toggle:hover {
            transform: rotate(20deg);
        }
        
        .directory-tree {
            padding: 1.5rem;
            position: relative;
        }
        
        .tree-item, .file-item {
            margin: 0.5rem 0;
            border-radius: 4px;
            transition: all 0.2s;
        }
        
        .folder-header {
            padding: 0.75rem 1rem;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 12px;
            border-radius: 4px;
            transition: background 0.2s;
        }
        
        .folder-header:hover {
            background-color: var(--folder-open);
        }
        
        .folder-header .icon {
            width: 24px;
            text-align: center;
            color: var(--primary);
        }
        
        .folder-header .name {
            flex: 1;
        }
        
        .folder-header .toggle {
            width: 24px;
            text-align: center;
            transition: transform 0.3s;
        }
        
        .folder-content {
            padding-left: var(--tree-indent);
            border-left: 2px solid var(--border-color);
            margin-left: 12px;
        }
        
        .folder-open .folder-content {
            display: block;
        }
        
        .folder-closed .folder-content {
            display: none;
        }
        
        .folder-closed .toggle i {
            transform: rotate(-90deg);
        }
        
        .file-item {
            padding: 0.75rem 1rem;
            padding-left: 48px;
            display: flex;
            align-items: center;
            gap: 12px;
            transition: all 0.2s;
        }
        
        .file-item:hover {
            background-color: var(--folder-open);
        }
        
        .file-item .icon {
            color: var(--secondary);
            width: 24px;
            text-align: center;
        }
        
        .file-item a {
            text-decoration: none;
            color: var(--text);
            transition: color 0.2s;
        }
        
        .file-item a:hover {
            color: var(--primary);
            text-decoration: underline;
        }
        
        .footer {
            text-align: center;
            padding: 1.5rem;
            color: var(--text-secondary);
            font-size: 0.85rem;
            border-top: 1px solid var(--border-color);
        }
        
        .search-container {
            margin: 0 1.5rem 1.5rem;
        }
        
        .search-box {
            width: 100%;
            padding: 0.75rem;
            border-radius: 4px;
            border: 1px solid var(--border-color);
            background: var(--card-bg);
            color: var(--text);
            font-size: 1rem;
        }
        
        .search-box:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 0 2px rgba(58, 134, 255, 0.2);
        }
        
        @media (max-width: 768px) {
            body {
                padding: 1rem;
            }
            
            .card-header {
                padding: 1rem;
            }
            
            .header-content {
                flex-direction: column;
                align-items: flex-start;
            }
            
            .meta-stats {
                width: 100%;
                justify-content: space-between;
            }
            
            .stat-item {
                min-width: auto;
                flex: 1;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="directory-card">
            <div class="card-header">
                <div class="header-content">
                    <h1><i class="fas fa-folder-tree"></i> 目录结构: <span class="path">${DOCUMENT_ROOT}</span></h1>
                    
                    <div class="meta-stats">
                        <div class="stat-item">
                            <i class="fas fa-folder"></i>
                            <span id="directory-count">$((dir_count - 1))</span> 个目录
                        </div>
                        <div class="stat-item">
                            <i class="fas fa-file"></i>
                            <span id="file-count">${file_count}</span> 个文件
                        </div>
                        <div class="stat-item">
                            <i class="fas fa-database"></i>
                            <span id="total-size">${total_size}</span>
                        </div>
                    </div>
                    
                    <button class="theme-toggle" id="theme-toggle" aria-label="切换主题">
                        <i class="fas fa-moon" id="theme-icon"></i>
                    </button>
                </div>
            </div>
            
            <div class="search-container">
                <input 
                    type="text" 
                    id="search-box" 
                    class="search-box" 
                    placeholder="搜索文件或目录..."
                    oninput="searchItems(this.value)"
                >
            </div>
            
            <div class="directory-tree" id="tree-container">
                $(generate_tree_structure)
            </div>
            
            <div class="footer">
                最后更新: <strong id="timestamp">$(date '+%Y-%m-%d %H:%M:%S')</strong>
                | 更新间隔: 5分钟
            </div>
        </div>
    </div>
    
    <script>
        // 初始化目录树
        document.addEventListener('DOMContentLoaded', () => {
            // 设置主题切换
            const themeToggle = document.getElementById('theme-toggle');
            const themeIcon = document.getElementById('theme-icon');
            const savedTheme = localStorage.getItem('theme');
            
            if (savedTheme === 'dark') {
                document.body.classList.add('dark-theme');
                themeIcon.className = 'fas fa-sun';
            }
            
            themeToggle.addEventListener('click', () => {
                document.body.classList.toggle('dark-theme');
                
                if (document.body.classList.contains('dark-theme')) {
                    localStorage.setItem('theme', 'dark');
                    themeIcon.className = 'fas fa-sun';
                } else {
                    localStorage.setItem('theme', 'light');
                    themeIcon.className = 'fas fa-moon';
                }
            });
            
            // 设置初始文件夹状态
            const folders = document.querySelectorAll('.tree-item');
            folders.forEach(folder => {
                folder.classList.add('folder-closed');
                folder.querySelector('.folder-content')?.classList.remove('folder-open');
            });
            
            // 更新时间戳
            updateTimestamp();
            setInterval(updateTimestamp, 1000);
        });
        
        // 切换文件夹展开/折叠状态
        function toggleFolder(folderElement) {
            const currentState = folderElement.classList.contains('folder-closed');
            
            folderElement.classList.toggle('folder-closed');
            folderElement.classList.toggle('folder-open');
            
            const toggleIcon = folderElement.querySelector('.toggle i');
            if (currentState) {
                folderElement.querySelector('.folder-header .icon i').className = 'far fa-folder-open';
            } else {
                folderElement.querySelector('.folder-header .icon i').className = 'far fa-folder';
            }
        }
        
        // 搜索文件和目录
        function searchItems(query) {
            const searchTerm = query.trim().toLowerCase();
            const allItems = document.querySelectorAll('#tree-container > div');
            
            if (!searchTerm) {
                // 显示所有项
                allItems.forEach(item => {
                    item.style.display = '';
                    
                    // 重新应用折叠状态
                    if (item.classList.contains('tree-item')) {
                        item.classList.add('folder-closed');
                    }
                });
                return;
            }
            
            allItems.forEach(item => {
                const nameElement = item.querySelector('.name, .name a');
                if (nameElement) {
                    const name = nameElement.textContent.toLowerCase();
                    if (name.includes(searchTerm)) {
                        item.style.display = '';
                        
                        // 展开包含匹配项的父文件夹
                        expandParents(item);
                    } else {
                        item.style.display = 'none';
                    }
                }
            });
        }
        
        // 展开匹配项的父文件夹
        function expandParents(item) {
            let current = item.parentElement;
            while (current && current !== document.getElementById('tree-container')) {
                if (current.classList.contains('tree-item')) {
                    current.classList.remove('folder-closed');
                    current.classList.add('folder-open');
                    current.querySelector('.folder-header .icon i').className = 'far fa-folder-open';
                }
                current = current.parentElement;
            }
        }
        
        // 更新时间戳
        function updateTimestamp() {
            const now = new Date();
            document.getElementById('timestamp').textContent = 
                now.toLocaleString('zh-CN', {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit',
                    second: '2-digit',
                    hour12: false
                }).replace(/\//g, '-');
        }
        
        // 展开所有文件夹（可选）
        function expandAll() {
            document.querySelectorAll('.tree-item').forEach(folder => {
                folder.classList.remove('folder-closed');
                folder.classList.add('folder-open');
                folder.querySelector('.folder-header .icon i').className = 'far fa-folder-open';
            });
        }
    </script>
</body>
</html>
HTML_HEAD
    
    # 保存文件
    cp -f "$temp_file" "$INDEX_FILE"
    chown "$HTTPD_USER:$HTTPD_USER" "$INDEX_FILE"
    rm -f "$temp_file"
}

# 主执行函数
main() {
    generate_html_tree
    exit 0
}

main "$@"