#!/bin/bash

# TiDB 集群清理脚本（仅清理，不重新安装）
# 安全清理 TiDB 集群相关资源，保留 TiUP 环境

set -euo pipefail

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 输出函数
print_message() { echo -e "${GREEN}[INFO]${NC} $*"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# 配置变量（与安装脚本保持一致）
TIDB_VERSION="v8.5.3"
TIDB_HOME="/data2/tidb"
TIDB_DEPLOY_DIR="${TIDB_HOME}/deploy"
TIDB_DATA_DIR="${TIDB_HOME}/data"
CLUSTER_NAME="tidb-cluster"
BACKUP_DIR="/tmp/tidb_cleanup_backup_$(date +%Y%m%d_%H%M%S)"

# 检查 root 权限
check_root_privilege() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
    print_message "✓ Root 权限验证通过"
}

# 显示横幅
show_banner() {
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                  TiDB 集群清理工具                          ║
║               仅执行清理，不重新安装                        ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

# 确认操作
confirm_operation() {
    echo
    echo "================================================"
    print_warning "即将执行: TiDB 集群清理"
    echo "这将影响以下资源:"
    echo "  - 集群名称: $CLUSTER_NAME"
    echo "  - 数据目录: $TIDB_DATA_DIR"
    echo "  - 部署目录: $TIDB_DEPLOY_DIR"
    echo "  - 配置目录: $TIDB_HOME/conf"
    echo ""
    echo "注意: 此操作仅清理，不会重新安装!"
    echo "================================================"
    
    read -p "确认执行清理操作? (输入 'YES' 确认): " confirmation
    if [ "$confirmation" != "YES" ]; then
        print_message "操作已取消"
        exit 0
    fi
    echo
}

# 检查集群状态
check_cluster_status() {
    print_step "1. 检查集群状态"
    
    if tiup cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        print_message "集群 $CLUSTER_NAME 存在"
        tiup cluster display "$CLUSTER_NAME" 2>/dev/null | head -20
        return 0
    else
        print_warning "集群 $CLUSTER_NAME 不存在或未在 TiUP 中注册"
        return 1
    fi
}

# 备份重要数据
backup_important_data() {
    print_step "2. 备份重要数据"
    
    mkdir -p "$BACKUP_DIR"
    print_message "创建备份目录: $BACKUP_DIR"
    
    # 备份拓扑文件
    if [ -f "${TIDB_HOME}/conf/topology.yaml" ]; then
        cp "${TIDB_HOME}/conf/topology.yaml" "$BACKUP_DIR/"
        print_message "✓ 备份拓扑文件: topology.yaml"
    else
        print_warning "⚠ 拓扑文件不存在: ${TIDB_HOME}/conf/topology.yaml"
    fi
    
    # 备份配置脚本
    if [ -d "${TIDB_HOME}/bin" ]; then
        cp -r "${TIDB_HOME}/bin" "$BACKUP_DIR/" 2>/dev/null || true
        print_message "✓ 备份脚本目录: bin/"
    fi
    
    # 备份数据库元数据
    if [ -d "${TIDB_DATA_DIR}" ]; then
        print_message "备份数据库元数据..."
        find "${TIDB_DATA_DIR}" -name "*.meta" -o -name "*.config" 2>/dev/null | head -10 | while read file; do
            cp --parents "$file" "$BACKUP_DIR/" 2>/dev/null || true
        done
    fi
    
    # 显示备份内容
    if [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_message "备份完成，内容:"
        ls -la "$BACKUP_DIR/"
    else
        print_warning "⚠ 无重要数据需要备份"
    fi
}

# 停止 TiDB 集群服务
stop_cluster_services() {
    print_step "3. 停止集群服务"
    
    # 检查集群是否存在
    if tiup cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        print_message "停止 TiDB 集群: $CLUSTER_NAME"
        
        # 优雅停止
        if tiup cluster stop "$CLUSTER_NAME" --yes 2>/dev/null; then
            print_message "✓ 集群停止成功"
        else
            print_warning "⚠ 优雅停止失败，尝试强制停止..."
            tiup cluster stop "$CLUSTER_NAME" --force --yes 2>/dev/null || true
        fi
        # 等待服务停止
        sleep 10
    else
        print_message "集群未在 TiUP 中注册，跳过停止步骤"
    fi
}

# 杀死残留进程
kill_remaining_processes() {
    print_step "4. 清理残留进程"
    
    print_message "检查并停止 TiDB 相关进程..."
    
    # 定义要清理的进程列表
    local processes=("tidb-server" "tikv-server" "pd-server" "tiflash" "prometheus" "grafana-server")
    
    local found_processes=0
    for process in "${processes[@]}"; do
        # 检查进程是否存在
        if pgrep -f "$process" > /dev/null; then
            print_message "发现进程: $process"
            pkill -f "$process" 2>/dev/null || true
            sleep 2
            
            # 如果进程仍然存在，强制杀死
            if pgrep -f "$process" > /dev/null; then
                print_warning "强制停止进程: $process"
                pkill -9 -f "$process" 2>/dev/null || true
            fi
            found_processes=$((found_processes + 1))
        fi
    done
    
    if [ $found_processes -eq 0 ]; then
        print_message "✓ 未发现运行的 TiDB 相关进程"
    else
        print_message "✓ 已清理 $found_processes 个相关进程"
    fi
    
    # 等待进程完全停止
    sleep 5
}

# 销毁 TiDB 集群
destroy_tidb_cluster() {
    print_step "5. 销毁 TiDB 集群"
    
    # 检查集群是否存在
    if tiup cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        print_message "销毁 TiDB 集群: $CLUSTER_NAME"
        
        # 销毁集群
        if tiup cluster destroy "$CLUSTER_NAME" --yes 2>/dev/null; then
            print_message "✓ 集群销毁成功"
        else
            print_warning "⚠ 集群销毁失败，尝试强制销毁..."
            tiup cluster destroy "$CLUSTER_NAME" --force --yes 2>/dev/null || true
        fi
        
        # 清理 TiUP 中的集群记录
        tiup cluster clean "$CLUSTER_NAME" --all --yes 2>/dev/null || true
    else
        print_message "集群未在 TiUP 中注册，跳过销毁步骤"
    fi
}

# 清理数据目录
clean_data_directories() {
    print_step "6. 清理数据目录"
    
    local directories=(
        "$TIDB_DEPLOY_DIR"
        "$TIDB_DATA_DIR"
        "${TIDB_HOME}/log"
    )
    
    local cleaned_dirs=0
    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            print_message "删除目录: $dir"
            if rm -rf "$dir"; then
                print_message "✓ 删除成功: $dir"
                cleaned_dirs=$((cleaned_dirs + 1))
            else
                print_error "✗ 删除失败: $dir"
            fi
        else
            print_message "目录不存在: $dir"
        fi
    done
    
    print_message "✓ 已清理 $cleaned_dirs 个数据目录"
}

# 清理配置文件（可选）
clean_config_files() {
    print_step "7. 清理配置文件（可选）"
    
    read -p "是否清理配置文件? (y/N): " clean_config
    if [[ $clean_config =~ ^[Yy]$ ]]; then
        # 清理配置目录内容（保留目录结构）
        if [ -d "${TIDB_HOME}/conf" ]; then
            rm -rf "${TIDB_HOME}/conf"/*
            print_message "✓ 清理配置目录"
        fi
        
        # 清理脚本目录内容
        if [ -d "${TIDB_HOME}/bin" ]; then
            rm -rf "${TIDB_HOME}/bin"/*
            print_message "✓ 清理脚本目录"
        fi
    else
        print_message "跳过配置文件清理"
    fi
}

# 清理端口占用
clean_port_usage() {
    print_step "8. 清理端口占用"
    
    print_message "检查端口占用情况..."
    
    local ports=("4000" "2379" "20160" "20161" "20162" "20180" "20181" "20182" "9090" "3000")
    local cleaned_ports=0
    
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            print_warning "端口 $port 被占用"
            
            # 查找占用端口的进程
            local pid_info=$(ss -tulpn | grep ":$port " | awk '{print $7}' | cut -d= -f2 | cut -d, -f1 | head -1)
            if [ -n "$pid_info" ] && [ "$pid_info" != "-" ]; then
                print_message "杀死占用端口 $port 的进程: $pid_info"
                kill -9 "$pid_info" 2>/dev/null || true
                cleaned_ports=$((cleaned_ports + 1))
            fi
        fi
    done
    
    if [ $cleaned_ports -eq 0 ]; then
        print_message "✓ 无 TiDB 相关端口占用"
    else
        print_message "✓ 已清理 $cleaned_ports 个端口占用"
    fi
}

# 验证清理结果
verify_cleanup() {
    print_step "9. 验证清理结果"
    
    local verification_passed=0
    local verification_total=0
    
    print_message "验证清理结果..."
    
    # 验证集群是否已删除
    verification_total=$((verification_total + 1))
    if ! tiup cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        print_message "✓ 集群已从 TiUP 中移除"
        verification_passed=$((verification_passed + 1))
    else
        print_error "✗ 集群仍在 TiUP 中"
    fi
    
    # 验证数据目录是否清理
    verification_total=$((verification_total + 1))
    if [ ! -d "$TIDB_DEPLOY_DIR" ] && [ ! -d "$TIDB_DATA_DIR" ]; then
        print_message "✓ 数据目录已清理"
        verification_passed=$((verification_passed + 1))
    else
        print_warning "⚠ 部分数据目录可能存在"
        [ -d "$TIDB_DEPLOY_DIR" ] && print_warning "目录存在: $TIDB_DEPLOY_DIR"
        [ -d "$TIDB_DATA_DIR" ] && print_warning "目录存在: $TIDB_DATA_DIR"
    fi
    
    # 验证进程是否清理
    verification_total=$((verification_total + 1))
    local running_processes=0
    for process in "tidb-server" "tikv-server" "pd-server"; do
        if pgrep -f "$process" > /dev/null; then
            running_processes=$((running_processes + 1))
        fi
    done
    
    if [ $running_processes -eq 0 ]; then
        print_message "✓ 无相关进程运行"
        verification_passed=$((verification_passed + 1))
    else
        print_warning "⚠ 仍有 $running_processes 个相关进程在运行"
    fi
    
    # 显示验证结果
    echo
    print_message "验证结果: $verification_passed/$verification_total 项通过"
    
    if [ $verification_passed -eq $verification_total ]; then
        print_message "✅ 清理完成"
    else
        print_warning "⚠ 清理基本完成，但存在一些残留"
    fi
}

# 显示清理总结
show_cleanup_summary() {
    print_step "清理完成总结"
    
    cat << EOF

===============================================
           TiDB 集群清理完成
===============================================

清理操作:
  ✓ 备份重要数据: ${BACKUP_DIR}
  ✓ 停止集群服务
  ✓ 清理数据目录
  ✓ 销毁 TiDB 集群

保留内容:
  - TiUP 环境 (~/.tiup)
  - 系统配置修改
  - 基础目录结构

备份信息:
  备份位置: ${BACKUP_DIR}
  包含文件: 拓扑配置、脚本文件等

如需重新安装，可运行原安装脚本。
如需完全重置，可手动删除 ${TIDB_HOME} 目录。

===============================================
EOF
}

# 显示详细清理报告
generate_cleanup_report() {
    local report_file="/tmp/tidb_cleanup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
TiDB 集群清理报告
生成时间: $(date)
执行脚本: $0
集群名称: $CLUSTER_NAME

清理项目:
1. 集群状态检查: $(tiup cluster list 2>/dev/null | grep -q "$CLUSTER_NAME" && echo "存在" || echo "不存在")
2. 数据目录清理:
   - 部署目录: $TIDB_DEPLOY_DIR ($([ -d "$TIDB_DEPLOY_DIR" ] && echo "存在" || echo "已清理"))
   - 数据目录: $TIDB_DATA_DIR ($([ -d "$TIDB_DATA_DIR" ] && echo "存在" || echo "已清理"))
3. 进程清理:
   - TiDB 进程: $(pgrep -f "tidb-server" | wc -l) 个
   - TiKV 进程: $(pgrep -f "tikv-server" | wc -l) 个
   - PD 进程: $(pgrep -f "pd-server" | wc -l) 个
4. 端口占用:
$(ss -tuln | grep -E ":4000|:2379|:20160|:20161|:20162|:9090|:3000" | sed 's/^/   - /')

备份目录: $BACKUP_DIR
$(ls -la "$BACKUP_DIR" 2>/dev/null | sed 's/^/   /')

建议:
1. 检查备份文件中的重要数据
2. 如需重新安装，确保目录权限正确
3. 如需完全清理，可手动删除 $TIDB_HOME 目录
EOF

    print_message "详细清理报告: $report_file"
}

# 主清理函数
main_cleanup() {
    show_banner
    print_message "开始 TiDB 集群清理流程..."
    
    # 确认操作
    confirm_operation
    check_root_privilege
    
    # 执行清理步骤
    check_cluster_status
    backup_important_data
    stop_cluster_services
    kill_remaining_processes
    destroy_tidb_cluster
    clean_data_directories
    clean_config_files
    clean_port_usage
    verify_cleanup
    
    # 显示结果
    show_cleanup_summary
    generate_cleanup_report
    
    print_message "✅ 清理操作完成"
}

# 快速清理模式（非交互式）
quick_cleanup() {
    print_message "快速清理模式..."
    
    # 停止集群
    tiup cluster stop "$CLUSTER_NAME" --yes 2>/dev/null || true
    tiup cluster destroy "$CLUSTER_NAME" --yes 2>/dev/null || true
    
    # 清理进程
    pkill -f "tidb-server" 2>/dev/null || true
    pkill -f "tikv-server" 2>/dev/null || true
    pkill -f "pd-server" 2>/dev/null || true
    
    # 清理目录
    rm -rf "$TIDB_DEPLOY_DIR" "$TIDB_DATA_DIR" "${TIDB_HOME}/log"
    
    print_message "快速清理完成"
}

# 仅清理数据（保留配置）
clean_data_only() {
    print_message "仅清理数据（保留配置）..."
    
    read -p "确认只清理数据目录? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_message "操作取消"
        exit 0
    fi
    
    # 停止服务
    tiup cluster stop "$CLUSTER_NAME" --yes 2>/dev/null || true
    
    # 只清理数据目录
    if [ -d "$TIDB_DATA_DIR" ]; then
        rm -rf "$TIDB_DATA_DIR"
        print_message "✓ 数据目录已清理"
    else
        print_message "数据目录不存在"
    fi
    
    # 清理日志
    if [ -d "${TIDB_HOME}/log" ]; then
        rm -rf "${TIDB_HOME}/log"
        print_message "✓ 日志目录已清理"
    fi
    
    print_message "数据清理完成，配置文件和集群定义保留"
}

# 显示使用说明
show_usage() {
    cat << EOF
TiDB 集群清理工具

用法:
  $0 [选项]

选项:
  cleanup      交互式清理（默认）
  quick        快速清理（非交互式）
  data-only    仅清理数据（保留配置）
  status       检查当前状态
  help         显示此帮助

示例:
  $0 cleanup    # 交互式清理（推荐）
  $0 quick      # 快速清理
  $0 data-only  # 仅清理数据
  $0 status     # 检查状态

说明:
  此脚本仅清理 TiDB 集群相关资源，不会重新安装。
  会保留 TiUP 环境和系统配置。

环境变量:
  TIDB_HOME     TiDB 安装目录（默认: /data2/tidb）
  CLUSTER_NAME  集群名称（默认: tidb-cluster）
EOF
}

# 检查当前状态
check_current_status() {
    show_banner
    print_message "当前 TiDB 集群状态检查"
    
    echo
    print_message "1. TiUP 集群状态:"
    tiup cluster list 2>/dev/null | grep "$CLUSTER_NAME" || echo "  集群未找到"
    
    echo
    print_message "2. 目录状态:"
    for dir in "$TIDB_DEPLOY_DIR" "$TIDB_DATA_DIR" "${TIDB_HOME}/conf" "${TIDB_HOME}/log"; do
        if [ -d "$dir" ]; then
            echo "  ✓ 存在: $dir ($(du -sh "$dir" 2>/dev/null | cut -f1) KB)"
        else
            echo "  ✗ 不存在: $dir"
        fi
    done
    
    echo
    print_message "3. 进程状态:"
    local processes=("tidb-server" "tikv-server" "pd-server")
    for process in "${processes[@]}"; do
        local count=$(pgrep -f "$process" 2>/dev/null | wc -l)
        if [ $count -gt 0 ]; then
            echo "  ⚠ 运行中: $process ($count 个进程)"
        else
            echo "  ✓ 未运行: $process"
        fi
    done
    
    echo
    print_message "4. 端口占用:"
    local ports=("4000" "2379" "20160" "20161" "20162")
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            echo "  ⚠ 占用: 端口 $port"
        else
            echo "  ✓ 空闲: 端口 $port"
        fi
    done
}

# 命令行参数处理
main() {
    case "${1:-}" in
        "quick")
            quick_cleanup
            ;;
        "data-only")
            clean_data_only
            ;;
        "status")
            check_current_status
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        "")
            main_cleanup
            ;;
        *)
            print_error "未知参数: $1"
            show_usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"