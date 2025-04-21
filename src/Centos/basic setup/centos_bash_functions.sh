# 将以下内容追加到 ~/.bashrc 文件中
cat >> ~/.bashrc << 'EOF'

# 创建文件并编辑
createf() {
    if [ -z "$1" ]; then
        echo "Usage: createf <filename>"
        return 1
    fi
    cd /root
    touch "$1" && chmod +x "$1" && vi "$1"
}

# 清空文件并编辑
rvi() {
    if [ -z "$1" ]; then
        echo "Usage: rvi <filename>"
        return 1
    fi
    cd /root
    echo "" > "$1"
    vi "$1"
}
EOF

# 使配置生效
source ~/.bashrc