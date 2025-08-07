#!/bin/bash
set -euo pipefail

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 扫描 /data 目录中的 MySQL 实例
scan_mysql_instances() {
    print_message "扫描 /data 目录中的 MySQL 实例..."
    
    # 查找所有匹配 mysql_*_v* 格式的目录
    local instances=($(find /data -maxdepth 1 -type d -name 'mysql_*_v*' -printf "%f\n"))
    
    if [ ${#instances[@]} -eq 0 ]; then
        print_warning "未找到任何 MySQL 实例"
        return
    fi
    
    # 创建输出文件
    local output_file="uninstall_commands.sh"
    echo "#!/bin/bash" > $output_file
    echo "# 自动生成的 MySQL 实例卸载脚本" >> $output_file
    echo "# 生成时间: $(date)" >> $output_file
    echo "" >> $output_file
    
    print_message "找到 ${#instances[@]} 个 MySQL 实例:"
    
    # 处理每个实例
    for instance in "${instances[@]}"; do
        # 解析版本和实例ID
        if [[ $instance =~ mysql_([0-9]+)_([0-9]+)_([0-9]+)_(v[0-9]+) ]]; then
            local version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
            local instance_id="${BASH_REMATCH[4]}"
        elif [[ $instance =~ mysql_([0-9]+)_([0-9]+)_(v[0-9]+) ]]; then
            local version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
            local instance_id="${BASH_REMATCH[3]}"
        else
            print_warning "无法解析实例名称: $instance"
            continue
        fi
        
        # 生成卸载命令
        local command="./centos_mysql_uninstall_8.x_vx.sh --version $version --instance $instance_id"
        
        # 添加到输出文件
        echo "$command" >> $output_file
        
        # 显示信息
        print_message "实例: $instance"
        print_message "版本: $version"
        print_message "实例ID: $instance_id"
        print_message "卸载命令: $command"
        echo ""
    done
    
    # 设置执行权限
    chmod +x $output_file
    
    print_message "卸载命令已保存到: $output_file"
    print_message "运行以下命令执行卸载:"
    print_message "  ./$output_file"
}

# 主函数
main() {
    scan_mysql_instances
}

# 执行主函数
main "$@"