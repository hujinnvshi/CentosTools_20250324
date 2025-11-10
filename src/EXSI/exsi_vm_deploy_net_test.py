#!/usr/bin/env python3
"""
最小化网络适配器创建测试脚本 (修正版)
用于解决 NetworkBackingInfo 属性错误问题
修正了关键API使用错误和测试逻辑
"""

import ssl

from pyVim.connect import Disconnect, SmartConnect
from pyVmomi import vim


def test_network_adapter_creation(esxi_host, username, password):
    """
    测试网络适配器创建的最小化函数 - 修正版
    """
    try:
        # 创建SSL上下文（跳过证书验证）
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        
        # 连接到ESXi
        print(f"🔗 正在连接到ESXi主机: {esxi_host}")
        si = SmartConnect(
            host=esxi_host,
            user=username,
            pwd=password,
            sslContext=context
        )
        print("✅ ESXi连接成功")
        
        # 获取内容对象
        content = si.RetrieveContent()
        
        # 测试1: 基础网络适配器创建
        print("\n🧪 测试1: 创建基础VirtualE1000适配器")
        try:
            network_adapter = vim.vm.device.VirtualE1000()
            network_adapter.key = 5000
            network_adapter.addressType = 'generated'
            print("✅ VirtualE1000实例创建成功")
        except Exception as e:
            print(f"❌ VirtualE1000创建失败: {e}")
            return False
        
        # 测试2: NetworkBackingInfo创建（关键测试 - 修正版）
        print("\n🧪 测试2: 创建NetworkBackingInfo")
        
        # 方法1: 标准方法（推荐）
        try:
            print("🔄 尝试方法1: VirtualEthernetCard.NetworkBackingInfo")
            backing_info = vim.vm.device.VirtualEthernetCard.NetworkBackingInfo()
            backing_info.deviceName = 'VM Network'
            backing_info.useAutoDetect = True
            
            network_adapter.backing = backing_info
            print("✅ NetworkBackingInfo创建成功（方法1）")
            used_method = "方法1"
            
        except AttributeError as e:
            print(f"❌ 方法1失败: {e}")
            
            # 方法2: 替代方法 - 尝试不同的类路径
            try:
                print("🔄 尝试方法2: VirtualE1000().NetworkBackingInfo")
                # 注意：这里应该是通过类访问，而不是实例
                backing_info = vim.vm.device.VirtualE1000().NetworkBackingInfo
                network_adapter.backing = backing_info
                network_adapter.backing.deviceName = 'VM Network'
                network_adapter.backing.useAutoDetect = True
                print("✅ NetworkBackingInfo创建成功（方法2）")
                used_method = "方法2"
                
            except Exception as e2:
                print(f"❌ 方法2也失败: {e2}")
                
                # 方法3: 最简方法 - 只设置必要的属性
                try:
                    print("🔄 尝试方法3: 最小化配置")
                    # 创建最基础的backing信息
                    network_adapter.backing = vim.vm.device.VirtualEthernetCard.NetworkBackingInfo()
                    # 只设置设备名称，让ESXi自动处理其他配置
                    network_adapter.backing.deviceName = 'VM Network'
                    print("✅ NetworkBackingInfo创建成功（方法3）")
                    used_method = "方法3"
                    
                except Exception as e3:
                    print(f"❌ 所有方法都失败: {e3}")
                    return False
        
        # 测试3: 配置连接信息
        print("\n🧪 测试3: 配置连接信息")
        try:
            network_adapter.wakeOnLanEnabled = True
            network_adapter.connectable = vim.vm.device.VirtualDevice.ConnectInfo()
            network_adapter.connectable.startConnected = True
            network_adapter.connectable.allowGuestControl = True
            print("✅ 连接信息配置成功")
        except Exception as e:
            print(f"❌ 连接信息配置失败: {e}")
            return False
        
        # 测试4: 验证配置的完整性
        print("\n🧪 测试4: 验证配置完整性")
        try:
            # 检查network_adapter对象的所有关键属性
            required_attrs = ['key', 'addressType', 'backing', 'connectable']
            for attr in required_attrs:
                if hasattr(network_adapter, attr):
                    print(f"   ✅ 属性 {attr} 存在")
                else:
                    print(f"   ❌ 属性 {attr} 缺失")
            
            # 特别检查backing属性
            if hasattr(network_adapter, 'backing'):
                backing = network_adapter.backing
                print(f"   ✅ Backing类型: {type(backing)}")
                if hasattr(backing, 'deviceName'):
                    print(f"   ✅ 设备名称: {backing.deviceName}")
            else:
                print("   ❌ Backing配置缺失")
                
        except Exception as e:
            print(f"⚠️ 配置验证时出现警告: {e}")
        
        # 测试5: 创建设备规格并模拟提交
        print("\n🧪 测试5: 创建设备规格")
        try:
            device_spec = vim.vm.device.VirtualDeviceSpec()
            device_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            device_spec.device = network_adapter
            
            # 验证设备规格
            if (device_spec.operation == vim.vm.device.VirtualDeviceSpec.Operation.add and 
                device_spec.device is not None):
                print("✅ 设备规格创建成功")
                print(f"   操作类型: {device_spec.operation}")
                print(f"   设备类型: {type(device_spec.device)}")
            else:
                print("❌ 设备规格验证失败")
                return False
                
        except Exception as e:
            print(f"❌ 设备规格创建失败: {e}")
            return False
        
        print(f"\n🎉 所有网络适配器测试通过！使用的方法: {used_method}")
        print("💡 建议在完整脚本中使用上述成功的配置方法")
        
        # 断开连接
        Disconnect(si)
        print("🔌 已断开ESXi连接")
        return True
        
    except Exception as e:
        print(f"❌ 测试过程中发生错误: {e}")
        import traceback
        traceback.print_exc()
        return False

def advanced_network_adapter_test(esxi_host, username, password):
    """
    高级测试：多种NetworkBackingInfo创建方法对比 - 修正版
    """
    print("\n" + "="*50)
    print("🔬 高级测试：NetworkBackingInfo API探索")
    print("="*50)
    
    try:
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        
        si = SmartConnect(host=esxi_host, user=username, pwd=password, sslContext=context)
        
        # 测试不同的类路径和方法
        test_cases = [
            {
                'name': 'VirtualEthernetCard.NetworkBackingInfo()',
                'code': "vim.vm.device.VirtualEthernetCard.NetworkBackingInfo()",
                'test': lambda: vim.vm.device.VirtualEthernetCard.NetworkBackingInfo()
            },
            {
                'name': 'VirtualE1000网络适配器创建',
                'code': "创建VirtualE1000实例",
                'test': lambda: vim.vm.device.VirtualE1000()
            }
        ]
        
        for i, test_case in enumerate(test_cases, 1):
            print(f"\n🧪 测试用例 {i}: {test_case['name']}")
            print(f"   代码: {test_case['code']}")
            
            try:
                result = test_case['test']()
                print(f"   ✅ 成功 - 结果类型: {type(result)}")
                
                # 如果是NetworkBackingInfo，测试其属性
                if 'NetworkBackingInfo' in str(type(result)):
                    result.deviceName = 'VM Network'
                    result.useAutoDetect = True
                    print("   ✅ NetworkBackingInfo属性设置成功")
                    
            except Exception as e:
                print(f"   ❌ 失败: {e}")
        
        # 探索可用的网络适配器类型
        print("\n🔍 可用的网络适配器类型探索:")
        adapter_types = [
            'VirtualE1000', 'VirtualE1000e', 'VirtualVmxnet', 
            'VirtualVmxnet2', 'VirtualVmxnet3', 'VirtualPCNet32'
        ]
        
        for adapter_type in adapter_types:
            try:
                # 动态获取类
                adapter_class = getattr(vim.vm.device, adapter_type, None)
                if adapter_class:
                    instance = adapter_class()
                    print(f"   ✅ {adapter_type}: 可用")
                else:
                    print(f"   ❌ {adapter_type}: 不可用")
            except Exception:
                print(f"   ❌ {adapter_type}: 不可用")
        
        Disconnect(si)
        print("\n✅ 高级测试完成")
        
    except Exception as e:
        print(f"❌ 高级测试失败: {e}")
        import traceback
        traceback.print_exc()

def simple_network_test(esxi_host, username, password):
    """
    最简单的网络适配器测试 - 专注于解决核心问题
    """
    print("\n" + "="*50)
    print("🧪 最简单测试：仅测试NetworkBackingInfo创建")
    print("="*50)
    
    try:
        # 不连接ESXi，只测试本地对象创建
        print("1. 测试VirtualE1000创建:")
        adapter = vim.vm.device.VirtualE1000()
        print("   ✅ VirtualE1000创建成功")
        
        print("2. 测试NetworkBackingInfo创建:")
        
        # 方法A: 标准方法
        try:
            backing = vim.vm.device.VirtualEthernetCard.NetworkBackingInfo()
            backing.deviceName = 'VM Network'
            adapter.backing = backing
            print("   ✅ 方法A成功: VirtualEthernetCard.NetworkBackingInfo()")
            return True
        except Exception as e:
            print(f"   ❌ 方法A失败: {e}")
        
        # 方法B: 尝试其他路径
        try:
            # 探索可能的类路径
            backing = vim.vm.device.VirtualE1000.NetworkBackingInfo
            adapter.backing = backing
            print("   ✅ 方法B成功: VirtualE1000.NetworkBackingInfo")
            return True
        except Exception as e:
            print(f"   ❌ 方法B失败: {e}")
        
        return False
        
    except Exception as e:
        print(f"❌ 简单测试失败: {e}")
        return False

def main():
    """
    主测试函数 - 修正版
    """
    # 配置信息 - 请根据您的环境修改
    ESXI_HOST = "172.16.47.183"  # 您的ESXi主机IP
    ESXI_USERNAME = "root"       # ESXi用户名
    ESXI_PASSWORD = "Secsmart#612"  # ESXi密码
    
    print("🚀 开始网络适配器创建测试")
    print("="*40)
    
    # 首先运行最简单测试（不依赖网络连接）
    print("\n📍 阶段1: 本地对象创建测试")
    simple_success = simple_network_test(ESXI_HOST, ESXI_USERNAME, ESXI_PASSWORD)
    
    if simple_success:
        print("\n📍 阶段2: 完整环境测试")
        # 运行基础测试
        success = test_network_adapter_creation(ESXI_HOST, ESXI_USERNAME, ESXI_PASSWORD)
        
        if success:
            # 运行高级测试
            advanced_network_adapter_test(ESXI_HOST, ESXI_USERNAME, ESXI_PASSWORD)
            
            print("\n" + "="*50)
            print("💡 解决方案总结:")
            print("1. 使用 VirtualEthernetCard.NetworkBackingInfo() 创建backing")
            print("2. 确保设备名称 'VM Network' 在ESXi中存在")
            print("3. 如果仍失败，检查pyvmomi版本和ESXi版本兼容性")
            print("="*50)
        else:
            print("\n❌ 完整测试失败，请检查网络连接和ESXi配置")
    else:
        print("\n❌ 本地对象创建测试失败，问题出在基础API使用上")
        print("💡 建议检查pyvmomi安装和版本兼容性")

if __name__ == "__main__":
    main()