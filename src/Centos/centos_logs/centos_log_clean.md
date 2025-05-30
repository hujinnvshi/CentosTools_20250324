Centos 7 系统
递归扫描/var/log目录下所有文件
将半个小时之前的日志文件内容置为空
使用echo "" > 文件名 实现
tail -f /data/scripts/clean_logs/clean_logs.log
需要创建一个白名单，匹配白名单内正则的文件不进行清理。
创建一个黑名单，匹配黑名单内正则文件直接删除。
对于处理的文件，记录处理的日志。
创建一个一键执行的脚本给我。
并且设置自动执行每隔半个小时执行一次。


# CentOS 日志清理方案

## 1. 需求说明
### 1.1 基本需求
- 系统环境：CentOS 7/8
- 目标目录：/var/log 及其子目录
- 清理范围：所有日志文件
- 时间限制：清理30分钟前的日志
- 清理方式：将文件内容置空（echo "" >）

### 1.2 功能要求
1. 日志清理
   - 递归扫描目标目录
   - 识别日志文件
   - 检查文件修改时间
   - 安全清空文件内容

2. 自动化执行
   - 支持手动一键执行
   - 配置定时任务（每3分钟）
   - 记录执行日志

### 1.3 安全考虑
1. 文件权限
   - 检查文件访问权限
   - 保留原有权限设置

2. 系统影响
   - 避免清理系统关键日志
   - 防止影响正在写入的日志
   - 保护特殊文件（软链接等）

### 1.4 其他要求
1. 执行记录
   - 记录清理时间
   - 记录清理文件列表
   - 记录清理结果

2. 错误处理
   - 异常情况处理
   - 执行失败通知

## 2. 验收标准
1. 脚本功能完整
2. 定时任务正常
3. 不影响系统运行
4. 有完整执行日志

## 3. 注意事项
1. 建议先测试后使用
2. 重要文件提前备份
3. 定期检查执行日志
4. 监控系统资源占用