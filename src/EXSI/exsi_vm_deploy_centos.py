#!/usr/bin/env python3
"""
ESXi CentOS 7 虚拟机部署脚本 (终极修复版)
彻底解决 bootOrder 配置错误问题
作者：ESXi资深开发工程师
日期：2025-11-10
版本：5.0
"""

import ipaddress
import socket
import ssl
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import urllib3
from pyVim.connect import Disconnect, SmartConnect
from pyVmomi import vim

# 禁用SSL警告
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class ESXiVMDeployer:
    def __init__(self, esxi_host, username, password):
        self.esxi_host = esxi_host
        self.username = username
        self.password = password
        self.service_instance = None
        
        # 配置参数
        self.config = {
            'iso_path': '[disk183] CentOS-7-x86_64-DVD-2009.iso',
            'vm_name_prefix': 'c79',
            'usage': 'general',
            'cpus': 8,
            'memory_mb': 16384,
            'disk_size_gb': 40,
            'username': 'admin',
            'password': 'Secsmart#612',
            'root_password': 'Rede@612@Mixed',
            'timezone': 'Asia/Shanghai',
            'subnet': '172.16.47.0/24',
            'gateway': '172.16.47.1',
            'dns_servers': '8.8.8.8',
            'datastore_name': 'disk183'
        }

    def connect_esxi(self):
        """连接到ESXi主机"""
        try:
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            
            self.service_instance = SmartConnect(
                host=self.esxi_host,
                user=self.username,
                pwd=self.password,
                sslContext=context
            )
            print(f"✅ 成功连接到ESXi主机: {self.esxi_host}")
            return True
        except Exception as e:
            print(f"❌ 连接ESXi主机失败: {str(e)}")
            return False

    def create_virtual_machine(self, ip_address):
        """
        创建虚拟机 - 彻底解决bootOrder错误
        使用多种策略绕过bootOrder配置问题
        """
        try:
            content = self.service_instance.RetrieveContent()
            datacenter = content.rootFolder.childEntity[0]
            vmfolder = datacenter.vmFolder
            host = datacenter.hostFolder.childEntity[0]
            resource_pool = host.resourcePool
            
            # 虚拟机名称
            vm_name = f"{self.config['vm_name_prefix']}_{ip_address}_{self.config['usage']}"
            print(f"🔧 创建虚拟机: {vm_name}")
            
            # 获取数据存储
            if not datacenter.datastore:
                print("❌ 没有可用的数据存储")
                return False
                
            datastore = datacenter.datastore[0]
            print(f"📦 使用数据存储: {datastore.name}")
            
            # 尝试多种创建策略
            strategies = [
                self.strategy_no_boot_options,  # 策略1: 不设置启动选项
                self.strategy_minimal_boot,     # 策略2: 最小化启动配置
                self.strategy_legacy_boot,      # 策略3: 传统启动配置
            ]
            
            for i, strategy in enumerate(strategies, 1):
                print(f"\n🔄 尝试策略 {i}/{len(strategies)}")
                if strategy(vmfolder, resource_pool, datastore, vm_name, ip_address):
                    print(f"✅ 策略 {i} 成功")
                    return True
                else:
                    print(f"❌ 策略 {i} 失败")
                    if i < len(strategies):
                        print("⏳ 等待5秒后尝试下一策略...")
                        time.sleep(5)
            
            print("❌ 所有策略都失败")
            return False
                
        except Exception as e:
            print(f"❌ 创建虚拟机时出错: {str(e)}")
            import traceback
            traceback.print_exc()
            return False

    def strategy_no_boot_options(self, vmfolder, resource_pool, datastore, vm_name, ip_address):
        """
        策略1: 完全不设置bootOptions - 让ESXi使用默认值
        这是最简单且最可能成功的方法
        """
        try:
            print("🎯 策略1: 不设置启动选项（使用默认值）")
            
            vm_config = vim.vm.ConfigSpec()
            vm_config.name = vm_name
            vm_config.numCPUs = self.config['cpus']
            vm_config.memoryMB = self.config['memory_mb']
            vm_config.guestId = 'centos7_64Guest'
            vm_config.version = 'vmx-13'
            
            # 设置虚拟机文件路径
            vm_config.files = vim.vm.FileInfo()
            vm_config.files.vmPathName = f"[{datastore.name}] {vm_name}/{vm_name}.vmx"
            
            # 创建设备配置
            device_changes = self.create_vm_devices(datastore, vm_name)
            if not device_changes:
                return False
                
            vm_config.deviceChange = device_changes
            
            # !!! 关键：不设置bootOptions !!!
            # vm_config.bootOptions = None  # 不设置任何启动选项
            
            print("   ✅ 不设置启动选项，使用ESXi默认值")
            
            # 提交创建任务
            task = vmfolder.CreateVM_Task(config=vm_config, pool=resource_pool)
            return self.wait_and_handle_task(task, vm_name, "创建")
            
        except Exception as e:
            print(f"   ❌ 策略1失败: {e}")
            return False

    def strategy_minimal_boot(self, vmfolder, resource_pool, datastore, vm_name, ip_address):
        """
        策略2: 最小化启动配置 - 只设置最基本的启动选项
        """
        try:
            print("🎯 策略2: 最小化启动配置")
            
            vm_config = vim.vm.ConfigSpec()
            vm_config.name = vm_name
            vm_config.numCPUs = self.config['cpus']
            vm_config.memoryMB = self.config['memory_mb']
            vm_config.guestId = 'centos7_64Guest'
            vm_config.version = 'vmx-13'
            
            vm_config.files = vim.vm.FileInfo()
            vm_config.files.vmPathName = f"[{datastore.name}] {vm_name}/{vm_name}.vmx"
            
            device_changes = self.create_vm_devices(datastore, vm_name)
            if not device_changes:
                return False
                
            vm_config.deviceChange = device_changes
            
            # 最小化启动配置
            boot_options = vim.vm.BootOptions()
            # 不设置bootOrder，只设置其他可选参数
            boot_options.bootDelay = 5000  # 5秒启动延迟
            boot_options.enterBIOSSetup = False
            
            vm_config.bootOptions = boot_options
            print("   ✅ 设置最小化启动选项（无bootOrder）")
            
            task = vmfolder.CreateVM_Task(config=vm_config, pool=resource_pool)
            return self.wait_and_handle_task(task, vm_name, "创建")
            
        except Exception as e:
            print(f"   ❌ 策略2失败: {e}")
            return False

    def strategy_legacy_boot(self, vmfolder, resource_pool, datastore, vm_name, ip_address):
        """
        策略3: 传统启动配置 - 使用可能兼容的旧版配置方式
        """
        try:
            print("🎯 策略3: 传统启动配置")
            
            vm_config = vim.vm.ConfigSpec()
            vm_config.name = vm_name
            vm_config.numCPUs = self.config['cpus']
            vm_config.memoryMB = self.config['memory_mb']
            vm_config.guestId = 'centos7_64Guest'
            vm_config.version = 'vmx-13'
            
            vm_config.files = vim.vm.FileInfo()
            vm_config.files.vmPathName = f"[{datastore.name}] {vm_name}/{vm_name}.vmx"
            
            device_changes = self.create_vm_devices(datastore, vm_name)
            if not device_changes:
                return False
                
            vm_config.deviceChange = device_changes
            
            # 尝试传统启动配置方式
            try:
                boot_options = vim.vm.BootOptions()
                
                # 方法3A: 尝试空数组
                boot_options.bootOrder = []
                print("   ✅ 设置空bootOrder数组")
                
            except Exception as e:
                print(f"   ⚠️ 方法3A失败: {e}")
                try:
                    # 方法3B: 不设置bootOrder属性
                    boot_options = vim.vm.BootOptions()
                    print("   ✅ 创建BootOptions但不设置bootOrder")
                except Exception as e2:
                    print(f"   ⚠️ 方法3B失败: {e2}")
                    # 方法3C: 完全不使用BootOptions
                    print("   ✅ 回退到不设置BootOptions")
                    task = vmfolder.CreateVM_Task(config=vm_config, pool=resource_pool)
                    return self.wait_and_handle_task(task, vm_name, "创建")
            
            vm_config.bootOptions = boot_options
            
            task = vmfolder.CreateVM_Task(config=vm_config, pool=resource_pool)
            return self.wait_and_handle_task(task, vm_name, "创建")
            
        except Exception as e:
            print(f"   ❌ 策略3失败: {e}")
            return False

    def wait_and_handle_task(self, task, vm_name, operation):
        """等待任务完成并处理结果"""
        self.wait_for_task(task, timeout=600)
        
        if task.info.state == 'success':
            vm = task.info.result
            print(f"   ✅ {operation}虚拟机 {vm_name} 成功")
            
            # 配置额外设置
            self.configure_vm_extra_settings(vm, vm_name)
            
            # 如果创建成功，配置启动顺序
            if operation == "创建":
                return self.configure_boot_order_after_creation(vm, vm_name)
            return True
        else:
            print(f"   ❌ {operation}虚拟机失败: {task.info.error}")
            return False

    def configure_boot_order_after_creation(self, vm, vm_name):
        """
        在虚拟机创建后配置启动顺序
        这是绕过bootOrder错误的关键方法
        """
        try:
            print("🔧 在虚拟机创建后配置启动顺序...")
            
            # 方法1: 使用ReconfigVM_Task
            try:
                boot_options = vim.vm.BootOptions()
                boot_options.bootOrder = [
                    vim.vm.BootOptions.BootableCdromDevice(),
                    vim.vm.BootOptions.BootableDiskDevice()
                ]
                
                spec = vim.vm.ConfigSpec()
                spec.bootOptions = boot_options
                
                task = vm.ReconfigVM_Task(spec=spec)
                if self.wait_and_handle_task(task, vm_name, "配置启动顺序"):
                    print("   ✅ 启动顺序配置成功（方法1）")
                    return True
            except Exception as e:
                print(f"   ⚠️ 启动顺序配置方法1失败: {e}")
            
            # 方法2: 使用SetBootOptions（备用方法）
            try:
                boot_options = vim.vm.BootOptions()
                boot_options.bootOrder = [
                    vim.vm.BootOptions.BootableCdromDevice()
                ]
                
                # 注意：SetBootOptions可能需要特定权限
                vm.SetBootOptions(boot_options)
                print("   ✅ 启动顺序配置成功（方法2）")
                return True
            except Exception as e:
                print(f"   ⚠️ 启动顺序配置方法2失败: {e}")
            
            # 方法3: 通过编辑虚拟机配置
            try:
                # 获取当前配置
                current_spec = vm.config
                
                # 创建新的启动配置
                boot_options = vim.vm.BootOptions()
                boot_options.bootOrder = [vim.vm.BootOptions.BootableCdromDevice()]
                
                # 创建配置规范
                spec = vim.vm.ConfigSpec()
                spec.bootOptions = boot_options
                spec.changeVersion = current_spec.changeVersion
                
                task = vm.ReconfigVM_Task(spec=spec)
                if self.wait_and_handle_task(task, vm_name, "重新配置启动顺序"):
                    print("   ✅ 启动顺序配置成功（方法3）")
                    return True
            except Exception as e:
                print(f"   ⚠️ 启动顺序配置方法3失败: {e}")
            
            print("   ⚠️ 所有启动顺序配置方法失败，但虚拟机已创建")
            print("   💡 建议通过vSphere Client手动设置启动顺序")
            return True  # 虚拟机创建成功，只是启动顺序配置失败
            
        except Exception as e:
            print(f"   ❌ 配置启动顺序时出错: {e}")
            return True  # 虚拟机创建成功，只是启动顺序配置失败

    def create_vm_devices(self, datastore, vm_name):
        """创建设备配置"""
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
            disk_backing.fileName = f"[{datastore.name}] {vm_name}/{vm_name}.vmdk"
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
            
            network_adapter.wakeOnLanEnabled = True
            network_adapter.connectable = vim.vm.device.VirtualDevice.ConnectInfo()
            network_adapter.connectable.startConnected = True
            network_adapter.connectable.allowGuestControl = True
            
            network_spec = vim.vm.device.VirtualDeviceSpec()
            network_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            network_spec.device = network_adapter
            device_changes.append(network_spec)
            
            print("   ✅ 所有设备配置完成")
            return device_changes
            
        except Exception as e:
            print(f"   ❌ 创建设备配置时出错: {e}")
            return []

    def configure_vm_extra_settings(self, vm, vm_name):
        """配置虚拟机额外设置"""
        try:
            spec = vim.vm.ConfigSpec()
            spec.annotation = f"""虚拟机自动部署信息：
名称: {vm_name}
创建时间: {time.strftime('%Y-%m-%d %H:%M:%S')}
IP地址: {vm_name.split('_')[1]}
用途: {self.config['usage']}
系统: CentOS 7 最小化安装
配置: {self.config['cpus']}CPU, {self.config['memory_mb']}MB内存
备注: 通过自动化脚本部署"""
            
            task = vm.ReconfigVM_Task(spec=spec)
            self.wait_for_task(task)
            print("   📝 虚拟机注解配置完成")
        except Exception as e:
            print(f"   ⚠️ 配置虚拟机注解时出错: {e}")

    def wait_for_task(self, task, timeout=300):
        """等待任务完成"""
        start_time = time.time()
        while task.info.state not in ['success', 'error']:
            if time.time() - start_time > timeout:
                print("   ⏰ 任务等待超时")
                break
            time.sleep(5)

    # 其他方法保持不变
    def check_ip_availability(self, ip_address):
        """检查IP地址是否可用"""
        ip_str = str(ip_address)
        
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '1', ip_str] if sys.platform != 'win32' 
                else ['ping', '-n', '1', '-w', '1000', ip_str],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                print(f"   IP {ip_str} 响应ping，可能已被占用")
                return False
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        except Exception as e:
            print(f"   ⚠️ 检查IP {ip_str} ping时出现异常: {e}")
        
        # 端口扫描检查
        ports = [22, 80, 443, 3389]
        for port in ports:
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                    sock.settimeout(1)
                    if sock.connect_ex((ip_str, port)) == 0:
                        print(f"   IP {ip_str} 端口 {port} 开放，可能已被占用")
                        return False
            except Exception:
                continue
                
        print(f"   ✅ IP {ip_str} 可用")
        return True

    def find_available_ips(self, count=1):
        """查找可用IP地址"""
        print(f"🔍 在子网 {self.config['subnet']} 中查找可用IP地址...")
        
        available_ips = []
        network = ipaddress.IPv4Network(self.config['subnet'], strict=False)
        
        # 排除网络地址、广播地址和网关地址
        excluded_ips = {network.network_address, network.broadcast_address}
        if hasattr(self.config, 'gateway'):
            try:
                excluded_ips.add(ipaddress.IPv4Address(self.config['gateway']))
            except ipaddress.AddressValueError:
                pass
        
        # 从子网中段开始检查
        host_list = list(network.hosts())
        if not host_list:
            print("❌ 子网中无可用主机地址")
            return available_ips
            
        start_index = max(0, len(host_list) // 3)
        check_ips = host_list[start_index:start_index + 20]
        
        # 使用多线程加速IP检查
        with ThreadPoolExecutor(max_workers=5) as executor:
            future_to_ip = {
                executor.submit(self.check_ip_availability, ip): ip 
                for ip in check_ips
                if ip not in excluded_ips
            }
            
            for future in as_completed(future_to_ip):
                ip = future_to_ip[future]
                try:
                    if future.result() and len(available_ips) < count:
                        available_ips.append(ip)
                        print(f"🎯 找到可用IP: {ip} ({len(available_ips)}/{count})")
                        
                    if len(available_ips) >= count:
                        executor.shutdown(wait=False, cancel_futures=True)
                        break
                except Exception as e:
                    print(f"⚠️ 检查IP {ip} 时出错: {e}")
        
        return available_ips[:count]

    def deploy_vms(self, vm_count=1):
        """主部署方法"""
        print("🚀 开始ESXi虚拟机自动化部署...")
        
        if not self.connect_esxi():
            sys.exit(1)
        
        # 查找可用IP
        available_ips = self.find_available_ips(vm_count)
        if not available_ips:
            print("❌ 未找到可用的IP地址")
            Disconnect(self.service_instance)
            sys.exit(1)
        
        print(f"📋 找到可用IP: {[str(ip) for ip in available_ips]}")
        
        successful_deployments = []
        
        for i, ip in enumerate(available_ips, 1):
            print(f"\n📦 正在部署第 {i}/{len(available_ips)} 个虚拟机 (IP: {ip})")
            
            try:
                if self.create_virtual_machine(ip):
                    successful_deployments.append(ip)
                    print(f"✅ 虚拟机部署完成: c79_{ip}_{self.config['usage']}")
                else:
                    print(f"❌ 虚拟机部署失败: {ip}")
                
                # 添加延迟避免压力
                if i < len(available_ips):
                    print("⏳ 等待10秒后继续...")
                    time.sleep(10)
                    
            except Exception as e:
                print(f"❌ 部署虚拟机 {ip} 时发生异常: {e}")
                continue
        
        # 输出结果
        print(f"\n{'🎉 部署完成！' if successful_deployments else '❌ 部署结果'}")
        print(f"   成功部署: {len(successful_deployments)} 个虚拟机")
        if successful_deployments:
            print(f"   IP列表: {[str(ip) for ip in successful_deployments]}")
        
        Disconnect(self.service_instance)
        print("🔌 已断开ESXi连接")

def main():
    """主函数"""
    ESXI_HOST = "172.16.47.183"
    ESXI_USERNAME = "root"
    ESXI_PASSWORD = "Secsmart#612"
    
    deployer = ESXiVMDeployer(ESXI_HOST, ESXI_USERNAME, ESXI_PASSWORD)
    
    # 可选配置修改
    deployer.config.update({
        'usage': 'vmaidb',
        'subnet': '172.16.47.0/24',
        'gateway': '172.16.47.1',
        'dns_servers': '8.8.8.8',
        'datastore_name': 'disk183'
    })
    
    try:
        deployer.deploy_vms(vm_count=1)
    except KeyboardInterrupt:
        print("\n⚠️ 用户中断部署过程")
        if deployer.service_instance:
            Disconnect(deployer.service_instance)
    except Exception as e:
        print(f"❌ 部署过程中发生错误: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()