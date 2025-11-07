@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: =============================================
:: VMware Workstation CentOS 静默部署脚本 (Windows)
:: 功能：一键部署 CentOS 虚拟机，完全静默安装
:: =============================================

:: 设置错误处理
if "%1"=="admin" goto :main
echo 请求管理员权限...
powershell -Command "Start-Process '%~f0' 'admin' -Verb RunAs -Wait"
exit /b

:main
setlocal enabledelayedexpansion

:: 颜色定义
for /f "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do (
    set "DEL=%%a"
)
set "RED=[31m"
set "GREEN=[32m"
set "YELLOW=[33m"
set "BLUE=[34m"
set "NC=[0m"

:: 日志函数
set "LOG_FILE=%TEMP%\vmware_deploy.log"
echo 部署开始: %DATE% %TIME% > "%LOG_FILE%"

:log_error
echo %* >> "%LOG_FILE%"
echo %DEL%!RED![错误] %*%DEL%!NC!
exit /b 1

:log_warn
echo %* >> "%LOG_FILE%"
echo %DEL%!YELLOW![警告] %*%DEL%!NC!
exit /b 0

:log_info
echo %* >> "%LOG_FILE%"
echo %DEL%!GREEN![信息] %*%DEL%!NC!
exit /b 0

:log_debug
echo %* >> "%LOG_FILE%"
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
set "VM_NAME=CentOS7-AutoDeploy"
set "VM_DIR=%USERPROFILE%\Documents\Virtual Machines\%VM_NAME%"
set "VMX_PATH=%VM_DIR%\%VM_NAME%.vmx"

:: 硬件规格
set "DISK_SIZE=20"
set "MEMORY_SIZE=2048"
set "CPU_COUNT=2"

:: 网络配置
set "NETWORK_TYPE=nat"
set "VM_IP=192.168.137.100"
set "NETMASK=255.255.255.0"
set "GATEWAY=192.168.137.1"

:: 系统配置
set "ROOT_PASSWORD=vmware123"
set "USER_NAME=vmuser"
set "USER_PASSWORD=vmware123"

:: =============================================
:: 环境检查
:: =============================================

call :check_environment
if errorlevel 1 (
    call :log_error "环境检查失败"
    pause
    exit /b 1
)

:: =============================================
:: 主部署流程
:: =============================================

call :log_info "开始 CentOS 静默部署"
call :log_info "虚拟机名称: %VM_NAME%"
call :log_info "ISO 镜像: %ISO_PATH%"

echo.
echo ============ 部署配置 ============
echo 内存: %MEMORY_SIZE% MB
echo CPU: %CPU_COUNT% 核心
echo 磁盘: %DISK_SIZE% GB
echo 网络: %NETWORK_TYPE%
echo IP地址: %VM_IP%
echo ==================================
echo.

call :create_vm_config
call :create_virtual_disk
call :create_kickstart_config
call :register_and_start_vm
call :verify_deployment
call :generate_documentation

call :log_info "🎉 虚拟机部署完成!"
echo.
echo ============ 部署完成 ============
echo IP地址: %VM_IP%
echo SSH: ssh root@%VM_IP% (密码: %ROOT_PASSWORD%)
echo 用户: %USER_NAME% (密码: %USER_PASSWORD%)
echo.
echo 管理命令:
echo 启动: "%VMRUN_PATH%" -T ws start "%VMX_PATH%" nogui
echo 停止: "%VMRUN_PATH%" -T ws stop "%VMX_PATH%"
echo 状态: "%VMRUN_PATH%" -T ws list
echo ==================================

echo 详细日志: %LOG_FILE%
pause
exit /b 0

:: =============================================
:: 功能函数
:: =============================================

:check_environment
call :log_info "检查环境..."

:: 检查 VMware 工具
if not exist "%VMRUN_PATH%" (
    call :log_error "vmrun 未找到: %VMRUN_PATH%"
    call :log_info "请确保已安装 VMware Workstation"
    exit /b 1
)

if not exist "%VDISKMANAGER_PATH%" (
    call :log_warn "vmware-vdiskmanager 未找到，将使用替代方案"
)

:: 检查 ISO 文件
if not exist "%ISO_PATH%" (
    call :log_error "ISO 文件未找到: %ISO_PATH%"
    exit /b 1
)

:: 检查磁盘空间
for /f "tokens=3" %%a in ('dir /-c %ISO_PATH% ^| find "字节"') do set "ISO_SIZE=%%a"
set /a "ISO_SIZE_MB=ISO_SIZE/1048576"
if !ISO_SIZE_MB! lss 100 (
    call :log_error "ISO 文件可能损坏或太小: !ISO_SIZE_MB! MB"
    exit /b 1
)

call :log_info "环境检查通过"
exit /b 0

:create_vm_config
call :log_info "创建虚拟机配置..."

:: 创建虚拟机目录
if not exist "%VM_DIR%" mkdir "%VM_DIR%"
call :log_info "虚拟机目录: %VM_DIR%"

:: 创建 VMX 配置文件
(
echo #!/usr/bin/vmware
echo .encoding = "UTF-8"
echo config.version = "8"
echo virtualHW.version = "19"
echo.
echo # 基本信息
echo displayName = "%VM_NAME%"
echo guestOS = "centos-64"
echo.
echo # 硬件配置
echo memsize = "%MEMORY_SIZE%"
echo numvcpus = "%CPU_COUNT%"
echo cpuid.coresPerSocket = "1"
echo.
echo # 磁盘配置
echo scsi0.present = "TRUE"
echo scsi0.virtualDev = "lsilogic"
echo scsi0:0.present = "TRUE"
echo scsi0:0.fileName = "%VM_NAME%.vmdk"
echo scsi0:0.deviceType = "scsi-hardDisk"
echo.
echo # CD-ROM 配置
echo ide1:0.present = "TRUE"
echo ide1:0.fileName = "%ISO_PATH%"
echo ide1:0.deviceType = "cdrom-image"
echo ide1:0.autodetect = "TRUE"
echo ide1:0.startConnected = "TRUE"
echo.
echo # 网络配置
echo ethernet0.present = "TRUE"
echo ethernet0.connectionType = "%NETWORK_TYPE%"
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
echo guestInfo.iso.config = "%VM_DIR%\ks.cfg"
) > "%VMX_PATH%"

call :log_info "虚拟机配置文件创建完成"
exit /b 0

:create_virtual_disk
call :log_info "创建虚拟磁盘..."

if exist "%VDISKMANAGER_PATH%" (
    call :log_info "使用 vmware-vdiskmanager 创建磁盘"
    "%VDISKMANAGER_PATH%" -c -s %DISK_SIZE%GB -a lsilogic -t 0 "%VM_DIR%\%VM_NAME%.vmdk"
    if errorlevel 1 (
        call :log_warn "磁盘创建失败，尝试替代方案"
        goto :create_disk_manual
    )
) else (
    goto :create_disk_manual
)

call :log_info "虚拟磁盘创建完成"
exit /b 0

:create_disk_manual
call :log_info "手动创建虚拟磁盘..."

:: 创建磁盘描述文件
(
echo # Disk DescriptorFile
echo version=1
echo encoding="UTF-8"
echo CID=fffffffe
echo parentCID=ffffffff
echo isNativeSnapshot="no"
echo createType="monolithicFlat"
echo.
echo # Extent description
echo RW %DISK_SIZE%000 FLAT "%VM_NAME%-flat.vmdk" 0
echo.
echo # The Disk Data Base
echo #DDB
echo.
echo ddb.adapterType = "lsilogic"
echo ddb.geometry.cylinders = "1305"
echo ddb.geometry.heads = "255"
echo ddb.geometry.sectors = "63"
echo ddb.longContentID = "ffffffffffffffffffffffffffffffff"
echo ddb.virtualHWVersion = "19"
) > "%VM_DIR%\%VM_NAME%.vmdk"

:: 创建磁盘数据文件
call :log_info "创建磁盘数据文件 (%DISK_SIZE% GB)..."
fsutil file createnew "%VM_DIR%\%VM_NAME%-flat.vmdk" %DISK_SIZE%000000000 >nul 2>&1
if errorlevel 1 (
    call :log_warn "使用替代方法创建磁盘文件"
    powershell -Command "& {[System.IO.File]::WriteAllBytes('%VM_DIR%\%VM_NAME%-flat.vmdk', [byte[]]::new(%DISK_SIZE%000000000))}" >nul 2>&1
)

call :log_info "虚拟磁盘创建完成"
exit /b 0

:create_kickstart_config
call :log_info "创建 Kickstart 自动安装配置..."

set "KS_PATH=%VM_DIR%\ks.cfg"

(
echo # CentOS 7 自动安装配置
echo # 生成时间: %DATE% %TIME%
echo.
echo # 基本配置
echo install
echo text
echo lang en_US.UTF-8
echo keyboard us
echo timezone Asia/Shanghai --isUtc
echo rootpw --plaintext %ROOT_PASSWORD%
echo auth --enableshadow --passalgo=sha512
echo selinux --disabled
echo firewall --disabled
echo services --enabled=sshd,network
echo network --bootproto=static --ip=%VM_IP% --netmask=%NETMASK% --gateway=%GATEWAY% --nameserver=8.8.8.8,8.8.4.4 --hostname=%VM_NAME%
echo reboot --eject
echo.
echo # 磁盘分区
echo clearpart --all --initlabel
echo autopart --type=lvm
echo.
echo # 软件包选择
echo %%packages --nobase
echo @core
echo vim-enhanced
echo wget
echo curl
echo net-tools
echo openssh-clients
echo openssh-server
echo tar
echo gcc
echo make
echo kernel-devel
echo open-vm-tools
echo %%end
echo.
echo # 安装后脚本
echo %%post --log=/root/install.log
echo #!/bin/bash
echo.
echo # 设置主机名
echo echo "%VM_NAME%" ^> /etc/hostname
echo hostnamectl set-hostname "%VM_NAME%"
echo.
echo # 配置网络
echo cat ^> /etc/sysconfig/network-scripts/ifcfg-eth0 ^<^< NETEOF
echo DEVICE=eth0
echo BOOTPROTO=static
echo ONBOOT=yes
echo IPADDR=%VM_IP%
echo NETMASK=%NETMASK%
echo GATEWAY=%GATEWAY%
echo DNS1=8.8.8.8
echo DNS2=8.8.4.4
echo NETEOF
echo.
echo # 创建用户
echo useradd -m -G wheel %USER_NAME%
echo echo "%USER_PASSWORD%" ^| passwd --stdin %USER_NAME%
echo.
echo # 配置 SSH
echo sed -i 's/^#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
echo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo.
echo # 配置 sudo
echo echo "%%wheel ALL=^(ALL^) NOPASSWD: ALL" ^>^> /etc/sudoers
echo.
echo # 安装 VMware 工具
echo systemctl enable vmtoolsd
echo systemctl start vmtoolsd
echo.
echo # 更新系统
echo yum update -y
echo.
echo # 清理安装介质
echo eject
echo.
echo # 创建完成标志
echo echo "Installation completed at ^$(date^)" ^> /etc/vmware-install-complete
echo.
echo %%end
) > "%KS_PATH%"

call :log_info "Kickstart 配置创建完成"
exit /b 0

:register_and_start_vm
call :log_info "注册并启动虚拟机..."

:: 检查虚拟机是否已注册
"%VMRUN_PATH%" list | findstr /C:"%VMX_PATH%" >nul
if not errorlevel 1 (
    call :log_info "虚拟机已注册，先取消注册..."
    "%VMRUN_PATH%" -T ws unregister "%VMX_PATH%"
)

:: 注册虚拟机
call :log_info "注册虚拟机..."
"%VMRUN_PATH%" -T ws register "%VMX_PATH%"
if errorlevel 1 (
    call :log_error "虚拟机注册失败"
    exit /b 1
)

:: 启动虚拟机（静默模式）
call :log_info "启动虚拟机..."
"%VMRUN_PATH%" -T ws start "%VMX_PATH%" nogui
if errorlevel 1 (
    call :log_error "虚拟机启动失败"
    exit /b 1
)

call :log_info "虚拟机启动命令执行成功"
exit /b 0

:verify_deployment
call :log_info "验证部署结果..."

:: 检查虚拟机是否已注册
"%VMRUN_PATH%" list | findstr /C:"%VMX_PATH%" >nul
if errorlevel 1 (
    call :log_error "虚拟机未正确注册"
    exit /b 1
)

:: 检查虚拟机文件
if not exist "%VMX_PATH%" (
    call :log_error "VMX 文件未找到: %VMX_PATH%"
    exit /b 1
)

if not exist "%VM_DIR%\%VM_NAME%.vmdk" (
    call :log_error "虚拟磁盘文件未找到"
    exit /b 1
)

if not exist "%VM_DIR%\ks.cfg" (
    call :log_error "Kickstart 配置文件未找到"
    exit /b 1
)

:: 检查虚拟机状态
for /f "tokens=2" %%i in ('"%VMRUN_PATH%" -T ws list ^| findstr /C:"%VM_NAME%"') do set "VM_STATE=%%i"
call :log_info "虚拟机状态: %VM_STATE%"

:: 检查网络连通性
call :log_info "测试网络连通性..."
ping -n 1 -w 2000 %VM_IP% >nul 2>&1
if errorlevel 1 (
    call :log_warn "虚拟机网络未连通，可能仍在安装中"
) else (
    call :log_info "✅ 虚拟机网络连通性验证通过"
)

call :log_info "✅ 基础部署验证通过"
exit /b 0

:generate_documentation
call :log_info "生成使用文档..."

set "DOC_PATH=%VM_DIR%\README.txt"

(
echo ================================
echo    CentOS 7 虚拟机部署文档
echo ================================
echo.
echo 部署信息：
echo   虚拟机名称: %VM_NAME%
echo   部署时间: %DATE% %TIME%
echo   虚拟机路径: %VM_DIR%
echo   ISO 镜像: %ISO_PATH%
echo.
echo 硬件配置：
echo   内存: %MEMORY_SIZE% MB
echo   CPU: %CPU_COUNT% 核心
echo   磁盘: %DISK_SIZE% GB
echo   网络: %NETWORK_TYPE%
echo.
echo 系统信息：
echo   IP 地址: %VM_IP%
echo   子网掩码: %NETMASK%
echo   网关: %GATEWAY%
echo   root 密码: %ROOT_PASSWORD%
echo   普通用户: %USER_NAME% / %USER_PASSWORD%
echo.
echo 管理命令：
echo   启动: "%VMRUN_PATH%" -T ws start "%VMX_PATH%" nogui
echo   停止: "%VMRUN_PATH%" -T ws stop "%VMX_PATH%"
echo   暂停: "%VMRUN_PATH%" -T ws suspend "%VMX_PATH%"
echo   重启: "%VMRUN_PATH%" -T ws reset "%VMX_PATH%"
echo   状态: "%VMRUN_PATH%" -T ws list
echo.
echo 连接方式：
echo   SSH: ssh root@%VM_IP%
echo        密码: %ROOT_PASSWORD%
echo   SSH: ssh %USER_NAME%@%VM_IP%
echo        密码: %USER_PASSWORD%
echo.
echo VMware 控制台：
echo   1. 打开 VMware Workstation/Player
echo   2. 选择 "打开虚拟机"
echo   3. 浏览到: %VMX_PATH%
echo.
echo 故障排除：
echo   1. 检查 VMware 服务是否运行
echo   2. 确认有足够的内存和磁盘空间
echo   3. 查看 VMware 日志文件
echo.
echo 后续步骤：
echo   1. 安装完成后，建议移除 ISO 镜像
echo   2. 配置定期备份
echo   3. 安装必要的应用服务
echo.
echo ================================
echo   文档生成时间: %DATE% %TIME%
echo ================================
) > "%DOC_PATH%"

call :log_info "使用文档生成完成: %DOC_PATH%"
exit /b 0

:: =============================================
:: 安装监控（可选功能）
:: =============================================

:monitor_installation
call :log_info "开始监控安装进度..."
set /a "MAX_WAIT=1800"
set /a "WAIT_TIME=0"
set /a "INTERVAL=30"

call :log_info "等待虚拟机安装完成（最多等待30分钟）..."

:monitor_loop
timeout /t %INTERVAL% /nobreak >nul
set /a "WAIT_TIME+=INTERVAL"

:: 检查虚拟机状态
for /f "tokens=2" %%i in ('"%VMRUN_PATH%" -T ws list ^| findstr /C:"%VM_NAME%" 2^>nul') do set "CURRENT_STATE=%%i"

if "%CURRENT_STATE%"=="running" (
    set /a "MINUTES=WAIT_TIME/60"
    call :log_info "✅ 虚拟机正在运行 (已运行 !MINUTES! 分钟)"
) else if "%CURRENT_STATE%"=="stopped" (
    call :log_info "🔄 虚拟机已停止，可能正在重启"
) else (
    call :log_warn "⚠️ 虚拟机状态未知"
)

:: 检查网络连通性
if !WAIT_TIME! gtr 600 (
    ping -n 1 -w 2000 %VM_IP% >nul 2>&1
    if not errorlevel 1 (
        call :log_info "🎉 虚拟机网络已连通，安装可能已完成"
        goto :monitor_end
    )
)

if !WAIT_TIME! lss !MAX_WAIT! goto :monitor_loop

:monitor_end
if !WAIT_TIME! geq !MAX_WAIT! (
    call :log_warn "⚠️ 安装监控超时，但虚拟机可能仍在运行"
) else (
    call :log_info "✅ 安装监控完成"
)
exit /b 0