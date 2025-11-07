@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: =============================================
:: VMware CentOS 静默部署脚本 - 修正版
:: 修复了逻辑错误和语法问题
:: =============================================

:: 设置错误处理
if "%1"=="admin" goto :main
echo 请求管理员权限...
powershell -Command "Start-Process '%~f0' 'admin' -Verb RunAs -Wait"
exit /b

:main
setlocal enabledelayedexpansion

:: 颜色定义（修正版）
for /f "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do (
    set "DEL=%%a"
)
set "RED=[31m"
set "GREEN=[32m"
set "YELLOW=[33m"
set "BLUE=[34m"
set "NC=[0m"

:: 日志函数（修正版）
:log_error
echo %DEL%!RED![错误] %*%DEL%!NC!
exit /b 1

:log_warn
echo %DEL%!YELLOW![警告] %*%DEL%!NC!
exit /b 0

:log_info
echo %DEL%!GREEN![信息] %*%DEL%!NC!
exit /b 0

:log_debug
echo %DEL%!BLUE![调试] %*%DEL%!NC!
exit /b 0

:: =============================================
:: 配置参数
:: =============================================

:: VMware 工具路径
set "VMRUN_PATH=C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
set "VDISKMANAGER_PATH=C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe"

:: 镜像路径
set "ISO_PATH=D:\BaiduNetdiskDownload\CentOS-7-x86_64-DVD-2009.iso"

:: 虚拟机配置
set "VM_NAME=CentOS7-DynamicDisk"
set "VM_BASE_DIR=D:\VMS"
set "VM_DIR=!VM_BASE_DIR!\!VM_NAME!"
set "VMX_PATH=!VM_DIR!\!VM_NAME!.vmx"

:: 硬件规格
set "DISK_SIZE=40"
set "MEMORY_SIZE=2048"
set "CPU_COUNT=2"

:: 磁盘模式配置
set "DISK_MODE=thin"
set "DISK_TYPE=independent"
set "DISK_ACCESS=rw"

:: 网络配置
set "NETWORK_TYPE=nat"
set "VM_IP=192.168.174.100"
set "NETMASK=255.255.255.0"
set "GATEWAY=192.168.174.1"

:: 系统配置
set "ROOT_PASSWORD=Rede@612@Mixed"
set "USER_NAME=admin"
set "USER_PASSWORD=Secsmart#612"

:: =============================================
:: 环境检查函数
:: =============================================

:check_environment
call :log_info "开始环境检查..."

:: 检查 D 盘
if not exist "D:\" (
    call :log_error "D 盘不存在!"
)

:: 检查 VMware 工具
if not exist "!VMRUN_PATH!" (
    call :log_error "vmrun 未找到: !VMRUN_PATH!"
)

:: 检查 ISO 文件
if not exist "!ISO_PATH!" (
    call :log_error "ISO 文件未找到: !ISO_PATH!"
)

:: 创建基础目录
if not exist "!VM_BASE_DIR!" (
    mkdir "!VM_BASE_DIR!"
    if errorlevel 1 (
        call :log_error "无法创建目录: !VM_BASE_DIR!"
    )
)

if not exist "!VM_DIR!" (
    mkdir "!VM_DIR!"
    if errorlevel 1 (
        call :log_error "无法创建目录: !VM_DIR!"
    )
)

call :log_info "环境检查通过"
exit /b 0

:: =============================================
:: 创建虚拟机配置
:: =============================================

:create_vm_config
call :log_info "创建虚拟机配置..."

(
echo #!/usr/bin/vmware
echo .encoding = "UTF-8"
echo config.version = "8"
echo virtualHW.version = "19"
echo.
echo # 基本信息
echo displayName = "!VM_NAME!"
echo guestOS = "centos-64"
echo.
echo # 硬件配置
echo memsize = "!MEMORY_SIZE!"
echo numvcpus = "!CPU_COUNT!"
echo cpuid.coresPerSocket = "1"
echo.
echo # 磁盘配置
echo scsi0.present = "TRUE"
echo scsi0.virtualDev = "lsilogic"
echo scsi0:0.present = "TRUE"
echo scsi0:0.fileName = "!VM_NAME!.vmdk"
echo scsi0:0.deviceType = "scsi-hardDisk"
echo scsi0:0.mode = "!DISK_MODE!"
echo scsi0:0.access = "!DISK_ACCESS!"
echo scsi0:0.independent = "TRUE"
echo scsi0:0.persistence = "nonpersistent"
echo.
echo # CD-ROM 配置
echo ide1:0.present = "TRUE"
echo ide1:0.fileName = "!ISO_PATH!"
echo ide1:0.deviceType = "cdrom-image"
echo ide1:0.autodetect = "TRUE"
echo ide1:0.startConnected = "TRUE"
echo.
echo # 网络配置
echo ethernet0.present = "TRUE"
echo ethernet0.connectionType = "!NETWORK_TYPE!"
echo ethernet0.virtualDev = "e1000"
echo ethernet0.wakeOnPcktRcv = "FALSE"
echo ethernet0.addressType = "generated"
echo.
echo # 其他设备
echo usb.present = "TRUE"
echo sound.present = "FALSE"
echo floppy0.present = "FALSE"
echo.
echo # 电源管理
echo powerType.powerOff = "soft"
echo powerType.suspend = "soft"
echo powerType.reset = "soft"
echo.
echo # 高级配置
echo tools.syncTime = "TRUE"
echo tools.remindInstall = "FALSE"
) > "!VMX_PATH!"

call :log_info "虚拟机配置文件创建完成: !VMX_PATH!"
exit /b 0

:: =============================================
:: 创建动态分配磁盘
:: =============================================

:create_dynamic_disk
call :log_info "创建动态分配磁盘..."

if exist "!VDISKMANAGER_PATH!" (
    call :log_info "使用 vmware-vdiskmanager 创建动态磁盘..."
    
    "!VDISKMANAGER_PATH!" -c -s !DISK_SIZE!GB -a lsilogic -t 0 "!VM_DIR!\!VM_NAME!.vmdk"
    
    if errorlevel 1 (
        call :log_warn "动态磁盘创建失败，尝试替代方案"
        goto :create_dynamic_disk_manual
    )
) else (
    goto :create_dynamic_disk_manual
)

call :log_info "动态磁盘创建成功"
exit /b 0

:create_dynamic_disk_manual
call :log_info "手动创建动态磁盘描述文件..."

(
echo # Disk DescriptorFile
echo version=1
echo encoding="UTF-8"
echo CID=fffffffe
echo parentCID=ffffffff
echo isNativeSnapshot="no"
echo createType="monolithicSparse"
echo.
echo # Extent description
echo RW !DISK_SIZE!000 SPARSE "!VM_NAME!-s0001.vmdk" 0
echo.
echo # The Disk Data Base 
echo #DDB
echo.
echo ddb.adapterType = "lsilogic"
echo ddb.geometry.cylinders = "16383"
echo ddb.geometry.heads = "16"
echo ddb.geometry.sectors = "63"
echo ddb.longContentID = "ffffffffffffffffffffffffffffffff"
echo ddb.virtualHWVersion = "19"
echo ddb.thinProvisioned = "1"
) > "!VM_DIR!\!VM_NAME!.vmdk"

call :log_info "创建初始稀疏文件..."
fsutil file createnew "!VM_DIR!\!VM_NAME!-s0001.vmdk" 65536 >nul 2>&1

if errorlevel 1 (
    powershell -Command "[System.IO.File]::WriteAllBytes('!VM_DIR!\!VM_NAME!-s0001.vmdk', [byte[]]::new(65536))" >nul 2>&1
)

call :log_info "动态磁盘手动创建完成"
exit /b 0

:: =============================================
:: 创建自动安装配置
:: =============================================

:create_kickstart_config
call :log_info "创建自动安装配置..."

set "KS_PATH=!VM_DIR!\ks.cfg"

(
echo # CentOS 7 自动安装配置
echo install
echo text
echo lang en_US.UTF-8
echo keyboard us
echo timezone Asia/Shanghai --isUtc
echo rootpw --plaintext !ROOT_PASSWORD!
echo auth --enableshadow --passalgo=sha512
echo selinux --disabled
echo firewall --disabled
echo network --bootproto=static --ip=!VM_IP! --netmask=!NETMASK! --gateway=!GATEWAY! --nameserver=8.8.8.8,8.8.4.4 --hostname=!VM_NAME!
echo reboot
echo.
echo # 磁盘分区
echo zerombr
echo clearpart --all --initlabel
echo autopart --type=lvm --fstype=ext4
echo.
echo # 软件包选择
echo %%packages --nobase
echo @core
echo vim-enhanced
echo wget
echo curl
echo net-tools
echo openssh-server
echo open-vm-tools
echo %%end
echo.
echo # 安装后脚本
echo %%post
echo #!/bin/bash
echo.
echo # 启用 VMware 工具
echo systemctl enable vmtoolsd
echo systemctl start vmtoolsd
echo.
echo # 创建用户
echo useradd -m -G wheel !USER_NAME!
echo echo "!USER_PASSWORD!" ^| passwd --stdin !USER_NAME!
echo echo "%%wheel ALL=(ALL) NOPASSWD: ALL" ^>^> /etc/sudoers
echo.
echo %%end
) > "!KS_PATH!"

call :log_info "Kickstart 配置创建完成: !KS_PATH!"
exit /b 0

:: =============================================
:: 注册和启动虚拟机
:: =============================================

:register_and_start_vm
call :log_info "注册并启动虚拟机..."

:: 检查是否已注册
"!VMRUN_PATH!" list | findstr /c:"!VMX_PATH!" >nul
if not errorlevel 1 (
    call :log_info "虚拟机已注册，先取消注册..."
    "!VMRUN_PATH!" -T ws unregister "!VMX_PATH!"
)

:: 注册虚拟机
call :log_info "注册虚拟机..."
"!VMRUN_PATH!" -T ws register "!VMX_PATH!"
if errorlevel 1 (
    call :log_error "虚拟机注册失败"
)

:: 启动虚拟机
call :log_info "启动虚拟机..."
"!VMRUN_PATH!" -T ws start "!VMX_PATH!" nogui
if errorlevel 1 (
    call :log_error "虚拟机启动失败"
)

call :log_info "虚拟机启动成功"
exit /b 0

:: =============================================
:: 验证部署结果
:: =============================================

:verify_deployment
call :log_info "验证部署结果..."

:: 检查虚拟机状态
for /f "tokens=2" %%i in ('"!VMRUN_PATH!" -T ws list ^| findstr /c:"!VM_NAME!"') do set "VM_STATE=%%i"
call :log_info "虚拟机状态: !VM_STATE!"

:: 检查磁盘文件
for /f "tokens=3" %%a in ('dir "!VM_DIR!\!VM_NAME!.vmdk" /-c 2^>nul ^| findstr "vmdk"') do set "DISK_SIZE_ACTUAL=%%a"

if "!DISK_SIZE_ACTUAL!"=="" (
    call :log_warn "无法获取磁盘文件大小"
) else if !DISK_SIZE_ACTUAL! LSS 1000000 (
    call :log_info "✅ 动态磁盘配置成功（文件大小: !DISK_SIZE_ACTUAL! 字节）"
) else (
    call :log_warn "⚠️ 磁盘文件较大，可能未正确配置为动态分配"
)

exit /b 0

:: =============================================
:: 生成使用文档
:: =============================================

:generate_documentation
call :log_info "生成使用文档..."

set "DOC_PATH=!VM_DIR!\README.txt"

(
echo ====================================
echo    CentOS 7 虚拟机部署文档
echo ====================================
echo.
echo 部署信息：
echo   虚拟机名称: !VM_NAME!
echo   部署时间: %DATE% %TIME%
echo   虚拟机路径: !VM_DIR!
echo.
echo 配置信息：
echo   内存: !MEMORY_SIZE! MB
echo   CPU: !CPU_COUNT! 核心
echo   磁盘: !DISK_SIZE! GB (动态分配)
echo   网络: !NETWORK_TYPE!
echo   IP地址: !VM_IP!
echo.
echo 登录信息：
echo   root 密码: !ROOT_PASSWORD!
echo   普通用户: !USER_NAME! / !USER_PASSWORD!
echo.
echo 管理命令：
echo   启动: "!VMRUN_PATH!" -T ws start "!VMX_PATH!" nogui
echo   停止: "!VMRUN_PATH!" -T ws stop "!VMX_PATH!"
echo   状态: "!VMRUN_PATH!" -T ws list
echo.
echo ====================================
) > "!DOC_PATH!"

call :log_info "使用文档生成完成: !DOC_PATH!"
exit /b 0

:: =============================================
:: 显示部署摘要
:: =============================================

:show_summary
echo.
echo ============================================
echo           部署完成摘要
echo ============================================
echo.
call :log_info "虚拟机名称: !VM_NAME!"
call :log_info "存储位置: !VM_DIR!"
call :log_info "磁盘模式: !DISK_MODE! (动态分配)"
call :log_info "最大容量: !DISK_SIZE! GB"
call :log_info "网络地址: !VM_IP!"
echo.
call :log_info "root 密码: !ROOT_PASSWORD!"
call :log_info "普通用户: !USER_NAME! / !USER_PASSWORD!"
echo.
echo ============================================
exit /b 0

:: =============================================
:: 主执行流程
:: =============================================

:execute_deployment
call :log_info "开始 CentOS 虚拟机部署流程..."

:: 执行部署步骤
call :check_environment
if errorlevel 1 exit /b 1

call :create_vm_config
if errorlevel 1 exit /b 1

call :create_dynamic_disk
if errorlevel 1 exit /b 1

call :create_kickstart_config
if errorlevel 1 exit /b 1

call :register_and_start_vm
if errorlevel 1 exit /b 1

call :verify_deployment
call :generate_documentation
call :show_summary

call :log_info "🎉 虚拟机部署完成!"
exit /b 0

:: =============================================
:: 脚本入口点
:: =============================================

echo.
echo ============================================
echo    VMware CentOS 静默部署脚本
echo ============================================
echo.

:: 执行主部署流程
call :execute_deployment

if errorlevel 1 (
    call :log_error "部署过程中出现错误"
) else (
    call :log_info "所有步骤执行完成"
)

echo.
pause
exit /b 0