
# -*- coding: utf-8 -*-
import hashlib
import os
from datetime import datetime

import pandas as pd


def get_file_info(filepath):
    """获取文件的详细信息：大小、修改时间、MD5哈希"""
    try:
        stat = os.stat(filepath)
        return {
            'size': stat.st_size,
            'size_readable': format_size(stat.st_size),
            'modified_time': datetime.fromtimestamp(stat.st_mtime),
            'hash': get_file_md5(filepath) if os.path.isfile(filepath) else 'N/A'
        }
    except Exception as e:
        return {'error': str(e)}

def get_file_md5(filename):
    """计算文件的MD5哈希值[1,4,7](@ref)"""
    if not os.path.isfile(filename):
        return None
    try:
        myhash = hashlib.md5()
        with open(filename, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b""):
                myhash.update(chunk)
        return myhash.hexdigest()
    except Exception as e:
        return f"Error: {str(e)}"

def scan_directory(directory_path):
    """扫描目录，返回所有文件的相对路径和详细信息[1,7](@ref)"""
    file_info = {}
    if not os.path.exists(directory_path):
        return file_info
    
    for root, dirs, files in os.walk(directory_path):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                # 获取文件相对路径作为键
                rel_path = os.path.relpath(file_path, directory_path)
                file_info[rel_path] = get_file_info(file_path)
                file_info[rel_path]['full_path'] = file_path
            except Exception as e:
                print(f"无法读取文件 {file_path}: {str(e)}")
    
    return file_info

def format_size(size_bytes):
    """将字节大小转换为易读的格式"""
    if size_bytes == 0:
        return "0 B"
    units = ['B', 'KB', 'MB', 'GB']
    import math
    unit_index = min(int(math.log(size_bytes, 1024)), len(units)-1) if size_bytes > 0 else 0
    size = size_bytes / (1024 ** unit_index)
    return f"{size:.2f} {units[unit_index]}"

def compare_directories(original_dir, copied_dir):
    """比较两个目录，返回详细的差异报告"""
    print("正在扫描原始目录...")
    original_files = scan_directory(original_dir)
    print("正在扫描拷贝目录...")
    copied_files = scan_directory(copied_dir)
    
    # 收集所有文件路径
    all_files = set(original_files.keys()) | set(copied_files.keys())
    
    comparison_results = []
    
    for file_path in sorted(all_files):
        original_info = original_files.get(file_path)
        copied_info = copied_files.get(file_path)
        
        result = {'file_path': file_path}
        
        if original_info and copied_info:
            # 文件在两个目录中都存在
            result['status'] = '存在'
            result['size_match'] = original_info.get('size', 0) == copied_info.get('size', 0)
            result['time_match'] = True  # 假设时间匹配，实际可根据需要比较
            
            # 记录具体信息
            result['original_size'] = original_info.get('size', 0)
            result['copied_size'] = copied_info.get('size', 0)
            result['original_mtime'] = original_info.get('modified_time')
            result['copied_mtime'] = copied_info.get('modified_time')
            result['original_full_path'] = original_info.get('full_path', '')
            result['copied_full_path'] = copied_info.get('full_path', '')
            
            # 比较内容哈希
            if 'hash' in original_info and 'hash' in copied_info:
                result['content_match'] = original_info['hash'] == copied_info['hash']
            else:
                result['content_match'] = 'N/A'
                
        elif original_info and not copied_info:
            # 文件只在原始目录中存在
            result['status'] = '缺失'
            result['original_size'] = original_info.get('size', 0)
            result['original_mtime'] = original_info.get('modified_time')
            result['original_full_path'] = original_info.get('full_path', '')
        elif not original_info and copied_info:
            # 文件只在拷贝目录中存在
            result['status'] = '多余'
            result['copied_size'] = copied_info.get('size', 0)
            result['copied_mtime'] = copied_info.get('modified_time')
            result['copied_full_path'] = copied_info.get('full_path', '')
        else:
            continue
        
        comparison_results.append(result)
    
    return comparison_results, len(original_files), len(copied_files)

def generate_detailed_report(comparison_results, original_dir, copied_dir):
    """生成详细的差异报告"""
    # 分类不同类型的文件
    missing_files = [r for r in comparison_results if r['status'] == '缺失']
    extra_files = [r for r in comparison_results if r['status'] == '多余']
    existing_files = [r for r in comparison_results if r['status'] == '存在']
    
    # 内容不匹配的文件
    content_mismatch = [r for r in existing_files if not r.get('content_match', True)]
    
    print("\n" + "="*100)
    print("文件夹详细差异报告")
    print("="*100)
    print(f"原始目录: {original_dir}")
    print(f"拷贝目录: {copied_dir}")
    print(f"报告生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("-"*100)
    
    # 缺失文件详情
    if missing_files:
        print(f"\n❌ 缺失文件 ({len(missing_files)} 个):")
        print("-" * 80)
        for i, file_info in enumerate(missing_files, 1):
            print(f"{i:2d}. {file_info['file_path']}")
            print(f"    大小: {format_size(file_info['original_size'])}")
            print(f"    修改时间: {file_info['original_mtime']}")
            print(f"    完整路径: {file_info['original_full_path']}")
    
    # 多余文件详情
    if extra_files:
        print(f"\n⚠️  多余文件 ({len(extra_files)} 个):")
        print("-" * 80)
        for i, file_info in enumerate(extra_files, 1):
            print(f"{i:2d}. {file_info['file_path']}")
            print(f"    大小: {format_size(file_info['copied_size'])}")
            print(f"    修改时间: {file_info['copied_mtime']}")
            print(f"    完整路径: {file_info['copied_full_path']}")
    
    # 内容不匹配文件详情
    if content_mismatch:
        print(f"\n📝 内容不匹配文件 ({len(content_mismatch)} 个):")
        print("-" * 80)
        for i, file_info in enumerate(content_mismatch, 1):
            print(f"{i:2d}. {file_info['file_path']}")
            original_size = format_size(file_info.get('original_size', 0))
            copied_size = format_size(file_info.get('copied_size', 0))
            print(f"    原始大小: {original_size} | 拷贝大小: {copied_size}")
            print(f"    原始路径: {file_info.get('original_full_path', '')}")
            print(f"    拷贝路径: {file_info.get('copied_full_path', '')}")
    
    # 生成Excel报告
    excel_filename = generate_excel_report(comparison_results, original_dir, copied_dir)
    
    return {
        'missing_files': missing_files,
        'extra_files': extra_files,
        'content_mismatch': content_mismatch,
        'excel_report': excel_filename
    }

def generate_excel_report(comparison_results, original_dir, copied_dir):
    """生成Excel格式的详细报告"""
    excel_data = []
    
    for result in comparison_results:
        row = {
            '文件相对路径': result['file_path'],
            '状态': result['status']
        }
        
        if result['status'] == '存在':
            row.update({
                '原始大小': result.get('original_size', 0),
                '拷贝大小': result.get('copied_size', 0),
                '大小匹配': '是' if result.get('size_match') else '否',
                '内容匹配': '是' if result.get('content_match') else '否',
                '原始修改时间': result.get('original_mtime'),
                '拷贝修改时间': result.get('copied_mtime'),
                '原始完整路径': result.get('original_full_path', ''),
                '拷贝完整路径': result.get('copied_full_path', '')
            })
        elif result['status'] == '缺失':
            row.update({
                '文件大小': result.get('original_size', 0),
                '修改时间': result.get('original_mtime'),
                '完整路径': result.get('original_full_path', '')
            })
        elif result['status'] == '多余':
            row.update({
                '文件大小': result.get('copied_size', 0),
                '修改时间': result.get('copied_mtime'),
                '完整路径': result.get('copied_full_path', '')
            })
        
        excel_data.append(row)
    
    # 创建DataFrame并保存为Excel
    df = pd.DataFrame(excel_data)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    excel_filename = f"folder_comparison_report_{timestamp}.xlsx"
    
    df.to_excel(excel_filename, index=False, engine='openpyxl')
    print(f"\n💾 详细Excel报告已保存为: {excel_filename}")
    
    return excel_filename

def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description='比较两个文件夹的差异并生成详细报告')
    parser.add_argument('original_dir', help='/data/mysql_5.7.39_v2_bak')
    parser.add_argument('copied_dir', help='/data/mysql_5.7.39_v2')
    
    args = parser.parse_args()
    
    # 检查目录是否存在
    if not os.path.exists(args.original_dir):
        print(f"错误: 原始目录不存在: {args.original_dir}")
        return
    
    if not os.path.exists(args.copied_dir):
        print(f"错误: 拷贝目录不存在: {args.copied_dir}")
        return
    
    try:
        # 比较目录
        results, original_count, copied_count = compare_directories(args.original_dir, args.copied_dir)
        
        # 生成详细报告
        report = generate_detailed_report(results, args.original_dir, args.copied_dir)
        
        # 输出总结
        print(f"\n📊 对比总结:")
        print(f"   原始目录文件数: {original_count}")
        print(f"   拷贝目录文件数: {copied_count}")
        print(f"   ❌ 缺失文件: {len(report['missing_files'])} 个")
        print(f"   ⚠️  多余文件: {len(report['extra_files'])} 个")
        print(f"   📝 内容不匹配: {len(report['content_mismatch'])} 个")
        print(f"   💾 详细报告: {report['excel_report']}")
        
    except Exception as e:
        print(f"比较过程中发生错误: {str(e)}")

if __name__ == "__main__":
    main()