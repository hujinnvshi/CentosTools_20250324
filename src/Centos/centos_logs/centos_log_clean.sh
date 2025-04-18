#!/bin/bash

# 常量定义
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'
readonly SCRIPT_DIR="/data/centos_logs_clean/logs_clean"
readonly LOG_FILE="${SCRIPT_DIR}/logs_clean_$(date +%Y%m%d_%H%M%S).log"
readonly WHITELIST_FILE="${SCRIPT_DIR}/whitelist.txt"
readonly BLACKLIST_FILE="${SCRIPT_DIR}/blacklist.txt"

# 创建必要的目录和文件
mkdir -p "${SCRIPT_DIR}"
touch "${LOG_FILE}" "${WHITELIST_FILE}" "${BLACKLIST_FILE}"

# 日志函数
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    log "${RED}请使用root用户执行此脚本${NC}"
    exit 1
fi

# 初始化白名单和黑名单
cat > "${WHITELIST_FILE}" << EOF
/var/log/lastlog
EOF

cat > "${BLACKLIST_FILE}" << EOF
/var/log/boot.log-.*
/var/log/btmp-.*
/var/log/cron-.*
/var/log/maillog-.*
/var/log/messages-.*
/var/log/secure-.*
/var/log/spooler-.*
/var/log/utmp-.*
/var/log/wtmp-.*
/var/log/yum.*
/var/log/vmware-.*
/var/log/Xorg..*
/var/log/firewall-.*
EOF

# 检查文件是否在白名单
is_whitelisted() {
    while read -r pattern; do
        if [[ $1 =~ $pattern ]]; then
            return 0
        fi
    done < "${WHITELIST_FILE}"
    return 1
}

# 检查文件是否在黑名单
is_blacklisted() {
    while read -r pattern; do
        if [[ $1 =~ $pattern ]]; then
            return 0
        fi
    done < "${BLACKLIST_FILE}"
    return 1
}

# 清理日志函数
logs_clean() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    log "${GREEN}开始清理日志文件${NC}"
    
    # 记录清理前状态
    log "清理前磁盘使用情况："
    ll -h /var/log | tee -a "${LOG_FILE}"
    
    # 处理所有文件
    find /var/log -type f -mmin +1 -print0 | while IFS= read -r -d '' file; do
        
        # 跳过白名单文件
        if is_whitelisted "$file"; then
            log "${YELLOW}跳过白名单文件: $file${NC}"
            continue
        fi
        
        # 处理黑名单文件
        if is_blacklisted "$file"; then
            log "${RED}删除黑名单文件: $file${NC}"
            rm -f "$file"
            continue
        fi
        
        if [ -w "$file" ]; then
            # 检查是否为软链接
            if [ ! -L "$file" ]; then
                # 备份文件权限
                local perms=$(stat -c %a "$file")
                local owner=$(stat -c %U:%G "$file")
                
                # 根据文件类型处理
                if [[ "$file" =~ \.(gz|bz2)$ ]]; then
                    # 删除压缩文件
                    rm -f "$file" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        log "${GREEN}成功删除压缩文件: $file${NC}"
                    else
                        log "${RED}删除压缩文件失败: $file${NC}"
                    fi
                else
                    # 尝试清空文件内容
                    truncate -s 0 "$file" 2>/dev/null || cat /dev/null > "$file" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        # 恢复文件权限
                        chmod "$perms" "$file"
                        chown "$owner" "$file"
                        log "${GREEN}成功清理文件: $file${NC}"
                    else
                        log "${YELLOW}无法清空文件(已跳过): $file${NC}"
                    fi
                fi
            else
                log "${YELLOW}跳过软链接: $file${NC}"
            fi
        else
            log "${YELLOW}文件无写入权限: $file${NC}"
        fi
    done
    
    # 记录清理后状态
    log "清理后磁盘使用情况："
    ls /var/log | tee -a "${LOG_FILE}"
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    log "${GREEN}日志清理完成${NC}"
    log "开始时间: $start_time"
    log "结束时间: $end_time"
}

# 配置定时任务
setup_cron() {
    local cron_job="*/30 * * * * /root/centos_log_clean.sh"
    if ! crontab -l | grep -q "$cron_job"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log "${GREEN}定时任务配置成功${NC}"
    else
        log "${YELLOW}定时任务已存在${NC}"
    fi
}

# 主函数
main() {
    logs_clean
    setup_cron
}

# 执行主函数
main