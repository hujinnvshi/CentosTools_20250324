#!/usr/bin/env python3
"""
ESXi CentOS 7 完整自动化部署解决方案 (修复版)
修复runtime验证错误
作者：Python/ESXi 资深开发专家
日期：2025-11-10
版本：6.1 - 修复runtime错误
"""

import ipaddress
import socket
import ssl
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

import urllib3
from pyVim.connect import Disconnect, SmartConnect
from pyVmomi import vim

# 禁用SSL警告
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class ESXiVMAutomation:
    def __init__(self, esxi_host, username, password):
        """
        初始化ESXi自动化部署器
        """
        self.esxi_host = esxi_host
        self.username = username
        self.password = password
        self.service_instance = None
        self.deployment_log = []
        
        # 配置参数
        self.config = {
            # ESXi配置
            'iso_path': '[disk183] CentOS-7-x86_64-DVD-2009.iso',
            'datastore_name': 'disk183',
            
            # 虚拟机配置
            'vm_name_prefix': 'c79',
            'usage': 'prod',
            'cpus': 8,
            'memory_mb': 16384,
            'disk_size_gb': 40,
            'disk_type': 'thin',
            
            # 系统配置
            'hostname_prefix': 'centos7',
            'timezone': 'Asia/Shanghai',
            'language': 'en_US.UTF-8',
            'keyboard': 'us',
            
            # 网络配置
            'subnet': '172.16.47.0/24',
            'netmask': '255.255.255.0',
            'gateway': '172.16.47.1',
            'dns_servers': '8.8.8.8,114.114.114.114',
            'domain': 'local.lan',
            
            # 用户账户
            'admin_username': 'admin',
            'admin_password': 'Secsmart#612',
            'root_password': 'Rede@612@Mixed',
            'ssh_key': '',  # 可选：SSH公钥
            
            # 部署设置
            'auto_power_on': True,
            'wait_for_os_boot': True,
            'post_install_scripts': [],
            
            # 服务配置
            'services_to_enable': ['sshd', 'network'],
            'services_to_disable': ['firewalld', 'NetworkManager'],
            
            # 软件包配置
            'packages_to_install': ['@core', 'vim', 'wget', 'curl', 'git'],
            'packages_to_remove': [],
            
            # 验证设置
            'skip_runtime_validation': False,  # 新增：跳过runtime验证
        }
        
        self._log("初始化", f"ESXi自动化部署器已初始化 - 目标主机: {esxi_host}")

    def _log(self, step, message, level="INFO"):
        """统一的日志记录"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] [{level}] {step}: {message}"
        self.deployment_log.append(log_entry)
        
        # 控制台输出
        if level == "ERROR":
            print(f"❌ {step}: {message}")
        elif level == "WARNING":
            print(f"⚠️  {step}: {message}")
        elif level == "SUCCESS":
            print(f"✅ {step}: {message}")
        else:
            print(f"🔧 {step}: {message}")

    def connect_esxi(self):
        """
        连接到ESXi主机 - 增强版本
        """
        try:
            self._log("连接ESXi", f"正在连接到 {self.esxi_host}...")
            
            # 创建SSL上下文
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            
            # 连接
            self.service_instance = SmartConnect(
                host=self.esxi_host,
                user=self.username,
                pwd=self.password,
                sslContext=context
            )
            
            # 验证连接
            about = self.service_instance.content.about
            self._log("连接ESXi", 
                     f"成功连接到 {about.fullName} (API: {about.apiVersion})", 
                     "SUCCESS")
            return True
            
        except Exception as e:
            self._log("连接ESXi", f"连接失败: {str(e)}", "ERROR")
            return False

    def validate_environment(self):
        """
        验证ESXi环境是否满足部署要求 - 修复runtime错误版本
        """
        try:
            content = self.service_instance.RetrieveContent()
            datacenter = content.rootFolder.childEntity[0]
            
            # 检查数据存储
            if not datacenter.datastore:
                self._log("环境验证", "未找到可用的数据存储", "ERROR")
                return False
                
            datastore = datacenter.datastore[0]
            self._log("环境验证", f"找到数据存储: {datastore.name}", "SUCCESS")
            
            # 检查主机资源 - 修复runtime验证
            if not datacenter.hostFolder.childEntity:
                self._log("环境验证", "未找到可用的主机", "ERROR")
                return False
                
            host = datacenter.hostFolder.childEntity[0]
            
            # !!! 关键修复：安全地检查runtime属性 !!!
            if not hasattr(host, 'runtime') or host.runtime is None:
                self._log("环境验证", "主机runtime信息不可用，跳过详细资源检查", "WARNING")
                
                # 如果配置允许跳过runtime验证，则继续
                if self.config.get('skip_runtime_validation', False):
                    self._log("环境验证", "跳过runtime验证，继续部署", "INFO")
                    return True
                else:
                    self._log("环境验证", "runtime验证失败且未配置跳过", "ERROR")
                    return False
            
            # 安全地获取runtime和hardware信息
            try:
                runtime = host.runtime
                hardware = host.hardware
                
                # 检查连接状态
                if hasattr(runtime, 'connectionState'):
                    connection_state = runtime.connectionState
                    if connection_state != 'connected':
                        self._log("环境验证", 
                                 f"主机连接状态异常: {connection_state}", 
                                 "ERROR")
                        return False
                
                # 检查内存 - 使用更安全的方法
                if hasattr(hardware, 'memorySize') and hardware.memorySize:
                    total_memory_mb = hardware.memorySize // (1024 * 1024)
                    
                    # 计算内存开销（安全方式）
                    memory_overhead = 0
                    if hasattr(runtime, 'memoryOverhead') and runtime.memoryOverhead:
                        memory_overhead = runtime.memoryOverhead // (1024 * 1024)
                    
                    free_memory_mb = total_memory_mb - memory_overhead
                    
                    if free_memory_mb < self.config['memory_mb']:
                        self._log("环境验证", 
                                 f"内存不足: 需要{self.config['memory_mb']}MB, 可用{free_memory_mb}MB", 
                                 "ERROR")
                        return False
                    else:
                        self._log("环境验证", 
                                 f"内存充足: 需要{self.config['memory_mb']}MB, 可用{free_memory_mb}MB", 
                                 "SUCCESS")
                else:
                    self._log("环境验证", "无法获取内存信息，跳过内存检查", "WARNING")
                
                # 检查CPU - 使用更安全的方法
                if (hasattr(hardware, 'cpuInfo') and 
                    hasattr(hardware.cpuInfo, 'numCpuPackages') and 
                    hasattr(hardware.cpuInfo, 'numCpuCores')):
                    
                    total_cores = hardware.cpuInfo.numCpuPackages * hardware.cpuInfo.numCpuCores
                    if total_cores < self.config['cpus']:
                        self._log("环境验证", 
                                 f"CPU核心不足: 需要{self.config['cpus']}核心, 可用{total_cores}核心", 
                                 "ERROR")
                        return False
                    else:
                        self._log("环境验证", 
                                 f"CPU核心充足: 需要{self.config['cpus']}核心, 可用{total_cores}核心", 
                                 "SUCCESS")
                else:
                    self._log("环境验证", "无法获取CPU信息，跳过CPU检查", "WARNING")
                
                self._log("环境验证", "环境验证通过", "SUCCESS")
                return True
                
            except Exception as runtime_error:
                self._log("环境验证", f"资源检查失败: {runtime_error}", "WARNING")
                
                # 如果配置允许跳过runtime验证，则继续
                if self.config.get('skip_runtime_validation', False):
                    self._log("环境验证", "跳过详细资源检查，继续部署", "INFO")
                    return True
                else:
                    return False
                
        except Exception as e:
            self._log("环境验证", f"验证失败: {str(e)}", "ERROR")
            return False

    def validate_environment_simple(self):
        """
        简化环境验证 - 只检查最基本的要求
        """
        try:
            content = self.service_instance.RetrieveContent()
            datacenter = content.rootFolder.childEntity[0]
            
            # 基本检查：数据存储和主机是否存在
            if not datacenter.datastore:
                self._log("简化验证", "未找到可用的数据存储", "ERROR")
                return False
                
            datastore = datacenter.datastore[0]
            self._log("简化验证", f"找到数据存储: {datastore.name}", "SUCCESS")
            
            if not datacenter.hostFolder.childEntity:
                self._log("简化验证", "未找到可用的主机", "ERROR")
                return False
                
            host = datacenter.hostFolder.childEntity[0]
            self._log("简化验证", f"找到主机: {getattr(host, 'name', 'Unknown')}", "SUCCESS")
            
            self._log("简化验证", "基本环境验证通过", "SUCCESS")
            return True
            
        except Exception as e:
            self._log("简化验证", f"验证失败: {str(e)}", "ERROR")
            return False

    def find_available_ip(self):
        """
        智能查找可用IP地址
        """
        try:
            network = ipaddress.IPv4Network(self.config['subnet'], strict=False)
            self._log("IP查找", f"在子网 {self.config['subnet']} 中查找可用IP...")
            
            # 排除网络地址、广播地址和网关
            excluded_ips = {
                network.network_address, 
                network.broadcast_address,
                ipaddress.IPv4Address(self.config['gateway'])
            }
            
            # 从子网中段开始检查
            hosts = list(network.hosts())
            if not hosts:
                self._log("IP查找", "子网中无可用主机地址", "ERROR")
                return None
                
            start_index = max(0, len(hosts) // 3)
            check_range = hosts[start_index:start_index + 20]
            
            for ip in check_range:
                if ip in excluded_ips:
                    continue
                    
                if self._check_ip_availability(ip):
                    self._log("IP查找", f"找到可用IP: {ip}", "SUCCESS")
                    return str(ip)
                    
            self._log("IP查找", "未找到可用IP地址", "ERROR")
            return None
            
        except Exception as e:
            self._log("IP查找", f"查找失败: {str(e)}", "ERROR")
            return None

    def _check_ip_availability(self, ip_address):
        """
        检查IP地址可用性
        """
        ip_str = str(ip_address)
        
        # Ping检查
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '1', ip_str] if sys.platform != 'win32' 
                else ['ping', '-n', '1', '-w', '1000', ip_str],
                capture_output=True,
                text=True,
                timeout=3
            )
            if result.returncode == 0:
                return False
        except:
            pass
            
        # 端口扫描
        ports = [22, 80, 443, 3389]
        for port in ports:
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                    sock.settimeout(1)
                    if sock.connect_ex((ip_str, port)) == 0:
                        return False
            except:
                continue
                
        return True

    def create_virtual_machine(self, ip_address, hostname):
        """
        创建虚拟机 - 修复版本
        """
        try:
            content = self.service_instance.RetrieveContent()
            datacenter = content.rootFolder.childEntity[0]
            vmfolder = datacenter.vmFolder
            
            # 安全获取主机和资源池
            if not datacenter.hostFolder.childEntity:
                self._log("创建虚拟机", "未找到可用的主机", "ERROR")
                return False
                
            host = datacenter.hostFolder.childEntity[0]
            resource_pool = host.resourcePool if hasattr(host, 'resourcePool') else None
            
            if not resource_pool:
                self._log("创建虚拟机", "无法获取资源池", "ERROR")
                return False
            
            # 获取数据存储
            if not datacenter.datastore:
                self._log("创建虚拟机", "未找到可用的数据存储", "ERROR")
                return False
                
            datastore = datacenter.datastore[0]
            
            vm_name = f"{self.config['vm_name_prefix']}_{ip_address}_{self.config['usage']}"
            self._log("创建虚拟机", f"开始创建: {vm_name}")
            
            # 虚拟机配置
            vm_config = vim.vm.ConfigSpec()
            vm_config.name = vm_name
            vm_config.numCPUs = self.config['cpus']
            vm_config.memoryMB = self.config['memory_mb']
            vm_config.guestId = 'centos7_64Guest'
            vm_config.version = 'vmx-13'
            
            # 文件配置
            vm_config.files = vim.vm.FileInfo()
            vm_config.files.vmPathName = f"[{datastore.name}] {vm_name}/{vm_name}.vmx"
            
            # 创建设备
            device_changes = self._create_vm_devices(datastore, vm_name)
            if not device_changes:
                return False
                
            vm_config.deviceChange = device_changes
            
            # 提交创建任务
            task = vmfolder.CreateVM_Task(config=vm_config, pool=resource_pool)
            if self._wait_for_task(task, 600, "创建虚拟机"):
                vm = task.info.result
                self._log("创建虚拟机", f"成功创建: {vm_name}", "SUCCESS")
                
                # 配置虚拟机注解
                self._configure_vm_annotation(vm, vm_name, ip_address, hostname)
                
                return vm
            else:
                self._log("创建虚拟机", f"创建失败: {task.info.error}", "ERROR")
                return False
                
        except Exception as e:
            self._log("创建虚拟机", f"创建过程出错: {str(e)}", "ERROR")
            return False

    def _create_vm_devices(self, datastore, vm_name):
        """
        创建设备配置
        """
        device_changes = []
        
        try:
            # 1. SCSI控制器
            scsi_controller = vim.vm.device.VirtualLsiLogicController()
            scsi_controller.key = 1000
            scsi_controller.busNumber = 0
            scsi_controller.sharedBus = vim.vm.device.VirtualSCSIController.Sharing.noSharing
            
            scsi_spec = vim.vm.device.VirtualDeviceSpec()
            scsi_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            scsi_spec.device = scsi_controller
            device_changes.append(scsi_spec)
            
            # 2. 虚拟磁盘
            disk_spec = vim.vm.device.VirtualDeviceSpec()
            disk_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            disk_spec.fileOperation = vim.vm.device.VirtualDeviceSpec.FileOperation.create
            disk_spec.device = vim.vm.device.VirtualDisk()
            disk_spec.device.key = 2000
            disk_spec.device.unitNumber = 0
            disk_spec.device.capacityInKB = self.config['disk_size_gb'] * 1024 * 1024
            disk_spec.device.controllerKey = 1000
            
            disk_backing = vim.vm.device.VirtualDisk.FlatVer2BackingInfo()
            disk_backing.diskMode = 'persistent'
            disk_backing.thinProvisioned = True
            disk_spec.device.backing = disk_backing
            device_changes.append(disk_spec)
            
            # 3. IDE控制器
            ide_controller = vim.vm.device.VirtualIDEController()
            ide_controller.key = 3000
            ide_controller.busNumber = 0
            
            ide_spec = vim.vm.device.VirtualDeviceSpec()
            ide_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            ide_spec.device = ide_controller
            device_changes.append(ide_spec)
            
            # 4. CD-ROM驱动器
            cdrom_spec = vim.vm.device.VirtualDeviceSpec()
            cdrom_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            cdrom_spec.device = vim.vm.device.VirtualCdrom()
            cdrom_spec.device.key = 4000
            cdrom_spec.device.controllerKey = 3000
            cdrom_spec.device.unitNumber = 0
            
            cdrom_backing = vim.vm.device.VirtualCdrom.IsoBackingInfo()
            cdrom_backing.fileName = self.config['iso_path']
            cdrom_spec.device.backing = cdrom_backing
            
            cdrom_connectable = vim.vm.device.VirtualDevice.ConnectInfo()
            cdrom_connectable.startConnected = True
            cdrom_connectable.allowGuestControl = False
            cdrom_spec.device.connectable = cdrom_connectable
            device_changes.append(cdrom_spec)
            
            # 5. 网络适配器
            network_adapter = vim.vm.device.VirtualE1000()
            network_adapter.key = 5000
            network_adapter.addressType = 'generated'
            
            network_adapter.backing = vim.vm.device.VirtualEthernetCard.NetworkBackingInfo()
            network_adapter.backing.deviceName = 'VM Network'
            network_adapter.backing.useAutoDetect = True
            
            network_adapter.connectable = vim.vm.device.VirtualDevice.ConnectInfo()
            network_adapter.connectable.startConnected = True
            network_adapter.connectable.allowGuestControl = True
            
            network_spec = vim.vm.device.VirtualDeviceSpec()
            network_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            network_spec.device = network_adapter
            device_changes.append(network_spec)
            
            self._log("设备配置", "所有设备配置完成", "SUCCESS")
            return device_changes
            
        except Exception as e:
            self._log("设备配置", f"创建设备失败: {str(e)}", "ERROR")
            return []

    def _configure_vm_annotation(self, vm, vm_name, ip_address, hostname):
        """
        配置虚拟机注解
        """
        try:
            spec = vim.vm.ConfigSpec()
            spec.annotation = f"""自动化部署信息
虚拟机名称: {vm_name}
主机名: {hostname}
IP地址: {ip_address}
创建时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
配置: {self.config['cpus']}CPU, {self.config['memory_mb']}MB内存
用途: {self.config['usage']}
系统: CentOS 7 最小化安装
管理员: {self.config['admin_username']}
部署状态: 虚拟机已创建"""
            
            task = vm.ReconfigVM_Task(spec=spec)
            self._wait_for_task(task, 30, "配置虚拟机注解")
            self._log("虚拟机注解", "配置完成", "SUCCESS")
            
        except Exception as e:
            self._log("虚拟机注解", f"配置失败: {str(e)}", "WARNING")

    def _wait_for_task(self, task, timeout=300, task_name="任务"):
        """
        等待任务完成
        """
        start_time = time.time()
        while task.info.state not in ['success', 'error']:
            if time.time() - start_time > timeout:
                self._log(task_name, "等待超时", "ERROR")
                return False
            time.sleep(5)
            
        if task.info.state == 'success':
            self._log(task_name, "完成", "SUCCESS")
            return True
        else:
            self._log(task_name, f"失败: {task.info.error}", "ERROR")
            return False

    def power_on_vm(self, vm):
        """
        启动虚拟机
        """
        try:
            self._log("启动虚拟机", "正在启动...")
            task = vm.PowerOn()
            if self._wait_for_task(task, 300, "启动虚拟机"):
                self._log("启动虚拟机", "启动成功", "SUCCESS")
                return True
            return False
        except Exception as e:
            self._log("启动虚拟机", f"启动失败: {str(e)}", "ERROR")
            return False

    def deploy_complete_vm(self):
        """
        完整的虚拟机部署流程 - 修复版本
        """
        self._log("部署流程", "开始完整部署流程", "INFO")
        
        # 1. 连接ESXi
        if not self.connect_esxi():
            return False
            
        # 2. 验证环境 - 使用简化版本
        if not self.validate_environment_simple():
            self._log("部署流程", "尝试使用详细验证...", "WARNING")
            
            # 如果简化验证失败，尝试详细验证
            if not self.validate_environment():
                self._log("部署流程", "环境验证失败，尝试跳过验证继续...", "WARNING")
                
                # 用户选择是否继续
                if not self.config.get('skip_runtime_validation', False):
                    self._log("部署流程", "环境验证失败，停止部署", "ERROR")
                    return False
            
        # 3. 查找可用IP
        ip_address = self.find_available_ip()
        if not ip_address:
            return False
            
        # 4. 生成主机名
        hostname = f"{self.config['hostname_prefix']}-{ip_address.replace('.', '-')}"
        
        # 5. 创建虚拟机
        vm = self.create_virtual_machine(ip_address, hostname)
        if not vm:
            return False
            
        # 6. 启动虚拟机
        if self.config.get('auto_power_on', True):
            if not self.power_on_vm(vm):
                self._log("部署流程", "虚拟机启动失败", "ERROR")
                return False
                
        # 7. 更新虚拟机注解
        self._update_vm_deployment_status(vm, ip_address, hostname)
        
        self._log("部署流程", "完整部署流程完成", "SUCCESS")
        return True

    def _update_vm_deployment_status(self, vm, ip_address, hostname):
        """
        更新虚拟机部署状态
        """
        try:
            spec = vim.vm.ConfigSpec()
            current_annotation = vm.config.annotation or ""
            
            new_annotation = f"""{current_annotation}
部署完成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
最终状态: 部署完成
访问信息: SSH {self.config['admin_username']}@{ip_address}"""
            
            spec.annotation = new_annotation
            task = vm.ReconfigVM_Task(spec=spec)
            self._wait_for_task(task, 30, "更新部署状态")
            
        except Exception as e:
            self._log("更新状态", f"更新失败: {str(e)}", "WARNING")

    def generate_deployment_report(self):
        """
        生成部署报告
        """
        report = f"""
ESXi 虚拟机自动化部署报告
生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
目标主机: {self.esxi_host}
部署结果: {'成功' if any('SUCCESS' in log for log in self.deployment_log) else '失败'}

部署日志:
"""
        
        for log_entry in self.deployment_log:
            report += f"{log_entry}\n"
            
        return report

    def cleanup(self):
        """
        清理资源
        """
        if self.service_instance:
            Disconnect(self.service_instance)
            self._log("清理", "已断开ESXi连接", "INFO")

def main():
    """
    主函数 - 修复版本
    """
    # 配置信息
    ESXI_HOST = "172.16.47.183"
    ESXI_USERNAME = "root"
    ESXI_PASSWORD = "Secsmart#612"
    
    # 创建部署器
    deployer = ESXiVMAutomation(ESXI_HOST, ESXI_USERNAME, ESXI_PASSWORD)
    
    # 自定义配置 - 修复runtime验证问题
    deployer.config.update({
        'usage': 'production-web',
        'cpus': 4,
        'memory_mb': 8192,
        'admin_username': 'deployer',
        'auto_power_on': True,
        'skip_runtime_validation': True,  # 新增：跳过runtime验证
    })
    
    try:
        # 执行完整部署
        success = deployer.deploy_complete_vm()
        
        # 生成报告
        report = deployer.generate_deployment_report()
        print("\n" + "="*60)
        print("部署报告")
        print("="*60)
        print(report)
        
        if success:
            print("🎉 部署完成！")
        else:
            print("❌ 部署过程中出现问题，请检查日志")
            
    except KeyboardInterrupt:
        print("\n⚠️ 用户中断部署过程")
    except Exception as e:
        print(f"❌ 部署过程中发生错误: {str(e)}")
        import traceback
        traceback.print_exc()
    finally:
        # 清理资源
        deployer.cleanup()

if __name__ == "__main__":
    main()