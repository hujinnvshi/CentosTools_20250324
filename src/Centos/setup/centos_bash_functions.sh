# 一个命令行工具，用于创建和编辑文件。
createf() {
    if [ -z "$1" ]; then
        echo "Usage: createf <filename>"
        return 1
    fi
    cd /root
    touch "$1" && chmod +x "$1" && vim "$1"
}

rvim() {
    if [ -z "$1" ]; then
        echo "Usage: createf <filename>"
        return 1
    fi
    cd /root
    echo "" > "$1"
    vim "$1"
}
