#!/bin/bash
set -euo pipefail

# ============================ 全局配置 ============================
# 备份根目录
BACKUP_ROOT="/backup"
# 日志文件路径
LOG_FILE="/var/log/gitlab_backup.log"
# GitLab 配置文件路径
GITLAB_RB="/etc/gitlab/gitlab.rb"
GITLAB_SECRETS="/etc/gitlab/gitlab-secrets.json"
# GitLab 11.2.3 使用旧版备份命令
GITLAB_BACKUP_CMD="gitlab-rake gitlab:backup:create SKIP=artifacts,builds,uploads"
# 备份文件命名格式
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${TIMESTAMP}_gitlab_backup"
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_NAME}"

# ============================ 日志函数 ============================
log_info() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [INFO] $1" >> "${LOG_FILE}"
    echo "INFO: $1"
}

log_error() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [ERROR] $1" >> "${LOG_FILE}"
    echo "ERROR: $1" >&2
    exit 1
}

log_warn() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [WARN] $1" >> "${LOG_FILE}"
    echo "WARN: $1"
}

# ============================ 前置检查函数 ============================
pre_check() {
    log_info "开始执行前置检查..."

    # 1. 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        log_error "脚本必须以root用户执行！"
    fi

    # 2. 检查GitLab是否安装
    if ! command -v gitlab-ctl &> /dev/null; then
        log_error "未检测到gitlab-ctl命令，GitLab可能未安装或非Omnibus版！"
    fi

    # 3. 检查GitLab版本（11.2.3特定检查）
    log_info "检测GitLab版本信息..."
    GITLAB_VERSION=$(gitlab-rake gitlab:env:info 2>/dev/null | grep -i '^Version:' | awk '{print $2}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo "GitLab版本：${GITLAB_VERSION}"
    if [ "${GITLAB_VERSION}" = "unknown" ]; then
        log_warn "无法解析GitLab具体版本，继续执行备份（建议手动确认版本）"
    else
        log_info "当前GitLab版本：${GITLAB_VERSION}"
        # 版本格式检查：11.2.3使用旧版备份格式[6](@ref)
        if ! echo "${GITLAB_VERSION}" | grep -qE '^1[0-1]\.'; then
            log_warn "检测到非11.x版本，请确认备份命令兼容性"
        fi
    fi

    # 4. 检查备份目录
    if [ ! -d "${BACKUP_ROOT}" ]; then
        log_info "创建备份目录：${BACKUP_ROOT}"
        mkdir -p "${BACKUP_ROOT}" || log_error "创建备份目录失败！"
    fi

    # 5. 检查核心配置文件
    if [ ! -f "${GITLAB_RB}" ]; then
        log_error "GitLab主配置文件${GITLAB_RB}不存在！"
    fi
    if [ ! -f "${GITLAB_SECRETS}" ]; then
        log_warn "GitLab密钥文件${GITLAB_SECRETS}不存在，跳过该文件备份"
    fi

    # 6. 检查磁盘空间
    FREE_SPACE_KB=$(df -k "${BACKUP_ROOT}" | awk 'NR==2 {print $4}')
    if [ "${FREE_SPACE_KB}" -lt 10485760 ]; then  # 10GB in KB
        log_warn "备份目录剩余空间不足10GB（当前：$((FREE_SPACE_KB/1024/1024))GB）"
    fi

    log_info "前置检查完成"
}

# ============================ 备份核心函数 ============================
backup_gitlab() {
    log_info "创建备份目录：${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}" || log_error "创建备份目录失败！"

    # 1. 备份GitLab配置文件[1,3](@ref)
    log_info "备份GitLab核心配置文件..."
    mkdir -p "${BACKUP_DIR}/config"
    cp -p "${GITLAB_RB}" "${BACKUP_DIR}/config/" || log_error "备份gitlab.rb失败！"
    if [ -f "${GITLAB_SECRETS}" ]; then
        cp -p "${GITLAB_SECRETS}" "${BACKUP_DIR}/config/" || log_error "备份gitlab-secrets.json失败！"
    fi

    # 2. 执行GitLab数据备份（GitLab 11.2.3使用旧版命令格式）[6](@ref)
    log_info "执行GitLab数据备份（版本11.2.3）..."
    
    # GitLab 11.2.3备份注意事项：[6](@ref)
    # - 使用gitlab-rake不是gitlab-backup
    # - 备份文件生成在默认路径/var/opt/gitlab/backups/
    # - 文件名格式：TIMESTAMP_YYYY_MM_DD_GitLab-version_gitlab_backup.tar
    
    # 设置备份路径为默认位置（11.2.3不支持自定义BACKUP_PATH）
    DEFAULT_BACKUP_DIR="/var/opt/gitlab/backups"
    if [ ! -d "${DEFAULT_BACKUP_DIR}" ]; then
        mkdir -p "${DEFAULT_BACKUP_DIR}"
        chown git:git "${DEFAULT_BACKUP_DIR}"
    fi

    # 执行备份（GitLab 11.2.3兼容命令）[6](@ref)
    if ! ${GITLAB_BACKUP_CMD} 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "GitLab数据备份失败！"
    fi

    # 3. 查找并移动备份文件[6](@ref)
    log_info "查找最新生成的备份文件..."
    # GitLab 11.2.3备份文件名格式：EPOCH_YYYY_MM_DD_GitLab-version[6](@ref)
    LATEST_BACKUP=$(find "${DEFAULT_BACKUP_DIR}" -name "*_gitlab_backup.tar" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -z "${LATEST_BACKUP}" ]; then
        log_error "未找到备份文件，请检查备份日志"
    fi

    if [ ! -f "${LATEST_BACKUP}" ]; then
        log_error "备份文件不存在：${LATEST_BACKUP}"
    fi

    # 移动备份文件到指定目录
    BACKUP_FILENAME=$(basename "${LATEST_BACKUP}")
    log_info "移动备份文件：${BACKUP_FILENAME}"
    mv "${LATEST_BACKUP}" "${BACKUP_DIR}/" || log_error "移动备份文件失败！"

    # 4. 设置文件权限
    log_info "设置备份文件权限..."
    chown -R root:root "${BACKUP_DIR}"
    chmod 600 "${BACKUP_DIR}"/*

    # 5. 生成MD5校验文件
    log_info "生成MD5校验文件..."
    cd "${BACKUP_DIR}" && md5sum "${BACKUP_FILENAME}" > "${BACKUP_FILENAME}.md5" || log_error "生成MD5校验失败！"

    log_info "GitLab备份完成，文件：${BACKUP_DIR}/${BACKUP_FILENAME}"
}

# ============================ 备份后校验 ============================
post_check() {
    log_info "执行备份后校验..."

    # 1. 检查备份目录内容
    if [ -z "$(ls -A "${BACKUP_DIR}")" ]; then
        log_error "备份目录为空！"
    fi

    # 2. 检查MD5校验文件
    MD5_FILE=$(find "${BACKUP_DIR}" -name "*.md5" | head -1)
    if [ -z "${MD5_FILE}" ]; then
        log_error "未找到MD5校验文件！"
    fi

    # 3. 验证MD5校验和
    if ! cd "${BACKUP_DIR}" && md5sum -c "${MD5_FILE}" &>/dev/null; then
        log_error "MD5校验失败，备份文件可能损坏！"
    fi

    # 4. 检查备份文件大小
    BACKUP_FILE=$(find "${BACKUP_DIR}" -name "*_gitlab_backup.tar" | head -1)

    if [ -n "${BACKUP_FILE}" ]; then
        FILE_SIZE=$(stat -c%s "${BACKUP_FILE}" 2>/dev/null || du -b "${BACKUP_FILE}" | cut -f1)
        if [ "${FILE_SIZE}" -lt 1024 ]; then
            log_error "备份文件大小异常（${FILE_SIZE}字节）！"
        fi
        log_info "备份文件大小：$((FILE_SIZE/1024/1024))MB"
    fi

    log_info "备份校验完成"
}

# ============================ 清理旧备份 ============================
clean_old_backups() {
    log_info "清理旧备份文件（保留最近70天）..."
    find "${BACKUP_ROOT}" -name "*_gitlab_backup*" -type f -mtime +70 -exec rm -rf {} \; 2>/dev/null && \
    log_info "旧备份清理完成" || \
    log_warn "清理旧备份时出错"
}

# ============================ 主流程 ============================
main() {
    # 初始化日志
    touch "${LOG_FILE}" || log_error "创建日志文件失败！"
    chmod 600 "${LOG_FILE}"

    log_info "开始GitLab备份流程（版本11.2.3）"
    
    pre_check
    backup_gitlab
    post_check
    clean_old_backups
    
    log_info "GitLab备份成功完成"
    log_info "备份位置：${BACKUP_DIR}"
    log_info "下次恢复命令：gitlab-rake gitlab:backup:restore BACKUP=$(basename "${BACKUP_DIR}" | cut -d'_' -f1)"
}

# 异常处理
trap 'log_error "脚本执行被中断"' INT TERM

# 执行主流程
main "$@"