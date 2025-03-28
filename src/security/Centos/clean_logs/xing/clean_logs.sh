#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 设置日志文件
SCRIPT_DIR="/data/scripts/clean_logs"
LOG_FILE="${SCRIPT_DIR}/clean_logs.log"
EXCLUDE_FILE="${SCRIPT_DIR}/exclude_files.txt"

# 创建必要的目录和文件
mkdir -p "${SCRIPT_DIR}"
touch "${LOG_FILE}"

# 输出函数
log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    log_message "${RED}请使用root用户执行此脚本${NC}"
    exit 1
fi

# 创建排除文件列表
cat > "${EXCLUDE_FILE}" << EOF
/var/log/boot.log
EOF

# 清理日志函数
clean_logs() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_message "${GREEN}开始清理日志文件${NC}"
    
    # 记录清理前状态
    log_message "清理前磁盘使用情况："
    df -h /var/log | tee -a "${LOG_FILE}"
    
    # 先处理压缩文件
    find /var/log -type f -mmin +10 \( -name "*.gz" -o -name "*.bz2" \) -print0 | while IFS= read -r -d '' file; do
        if [ -w "$file" ]; then
            rm -f "$file" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "${GREEN}成功删除压缩文件: $file${NC}"
            else
                log_message "${RED}删除压缩文件失败: $file${NC}"
            fi
        else
            log_message "${YELLOW}文件无写入权限: $file${NC}"
        fi
    done

    # 处理普通文件
    find /var/log -type f -mmin +10 ! -name "*.gz" ! -name "*.bz2" -print0 | while IFS= read -r -d '' file; do
        # 跳过排除文件
        if grep -q "^$file$" "${EXCLUDE_FILE}"; then
            log_message "${YELLOW}跳过排除文件: $file${NC}"
            continue
        fi
        
        if [ -w "$file" ]; then
            # 检查是否为软链接
            if [ ! -L "$file" ]; then
                # 备份文件权限
                local perms=$(stat -c %a "$file")
                local owner=$(stat -c %U:%G "$file")
            
                # 使用 cat 而不是 echo 来清空文件
                cat /dev/null > "$file" 2>/dev/null
                if [ $? -eq 0 ]; then
                    # 恢复文件权限
                    chmod "$perms" "$file"
                    chown "$owner" "$file"
                    log_message "${GREEN}成功清理文件: $file${NC}"
                else
                    log_message "${RED}清理文件失败: $file${NC}"
                fi
            else
                log_message "${YELLOW}跳过软链接: $file${NC}"
            fi
        else
            log_message "${YELLOW}文件无写入权限: $file${NC}"
        fi
    done
    
    # 记录清理后状态
    log_message "清理后磁盘使用情况："
    df -h /var/log | tee -a "${LOG_FILE}"
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_message "${GREEN}日志清理完成${NC}"
    log_message "开始时间: $start_time"
    log_message "结束时间: $end_time"
}

# 执行清理
clean_logs