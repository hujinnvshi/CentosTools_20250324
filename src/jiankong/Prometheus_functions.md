Prometheus 常用函数分类汇总

一、聚合函数（Aggregation Operators）

函数 作用 示例

sum() 对维度值求和 sum(container_cpu_usage_seconds_total)

avg() 计算平均值 avg(node_memory_MemFree_bytes)

min() 取最小值 min(container_memory_usage_bytes)

max() 取最大值 max(http_requests_total)

count() 统计序列数量 count(up == 1)

group() 将所有值设为1 group(instance)

stddev() 计算标准差 stddev(node_cpu_seconds_total)

topk() 取前N个最大值 topk(5, http_requests_total)

bottomk() 取前N个最小值 bottomk(5, node_memory_MemFree_bytes)
二、数学函数（Math Functions）
函数 作用 示例

abs() 取绝对值 abs(temperature)

ceil() 向上取整 ceil(node_filesystem_free_bytes)

floor() 向下取整 floor(container_memory_usage_bytes)

round() 四舍五入 round(http_request_duration_seconds, 0.01)

sqrt() 平方根 sqrt(vector(9))

ln() 自然对数 ln(process_cpu_seconds_total)

exp() 指数函数 exp(vector(2))

clamp_max() 限制最大值 clamp_max(rate(http_requests_total[5m]), 100)

clamp_min() 限制最小值 clamp_min(node_memory_MemFree_bytes, 1024)
三、时间函数（Time Functions）
函数 作用 示例

time() 返回当前时间戳 time()

timestamp() 返回样本时间戳 timestamp(http_requests_total)

minute() 提取分钟数 minute(timestamp(node_boot_time))

hour() 提取小时数 hour(timestamp(process_start_time_seconds))

day_of_month() 提取月中日期 day_of_month(timestamp(up))

month() 提取月份 month(timestamp(process_cpu_seconds_total))

year() 提取年份 year(timestamp(node_time_seconds))
四、标签操作函数（Label Functions）
函数 作用 示例

label_replace() 替换标签值 label_replace(up, "new_label", "$1", "instance", "(.*):.*")

label_join() 连接多个标签值 label_join(up, "new_label", "-", "job", "instance")
五、逻辑函数（Logical Functions）
函数 作用 示例

and() 逻辑与 and(up == 1, node_memory_MemFree_bytes > 1024)

or() 逻辑或 or(up == 0, http_requests_total < 10)

unless() 逻辑排除 unless(up, node_cpu_seconds_total{mode="idle"} < 0.1)
六、特殊函数（Special Functions）
函数 作用 示例

absent() 检测指标是否缺失 absent(up{instance="localhost:9090"})

histogram_quantile() 计算分位数 histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

predict_linear() 线性预测 predict_linear(node_filesystem_free_bytes[6h], 3600*24)

deriv() 计算导数 deriv(node_cpu_seconds_total[5m])

resets() 计算计数器重置次数 resets(node_network_receive_bytes_total[1h])
七、最重要的函数：rate() 和 increase()
函数 作用 示例 重要说明

rate() 计算每秒平均增长率 rate(http_requests_total[5m]) 仅用于计数器，自动处理重置

increase() 计算时间窗口内总增长量 increase(node_network_receive_bytes_total[1h]) 仅用于计数器，自动处理重置

rate() 使用要点：

1. 只用于计数器类型指标（单调递增）
2. 必须指定时间窗口（如 [5m], [1h]）
3. 自动处理计数器重置
4. 结果是每秒速率

错误用法示例：

# 错误：对非计数器使用 rate
rate(node_memory_MemFree_bytes[5m])

# 错误：忘记时间窗口
rate(http_requests_total)


八、函数组合使用示例

1. 计算95%分位响应时间

histogram_quantile(0.95, 
  rate(http_request_duration_seconds_bucket[5m])
)


2. 检测服务是否宕机

absent(up{job="api-server"})


3. 预测磁盘空间耗尽时间

predict_linear(node_filesystem_free_bytes[1h], 3600*24) < 0


4. 统计前5个最繁忙的服务

topk(5, 
  sum by (job) (
    rate(http_requests_total[5m])
  )
)


总结建议

1. 计数器指标：优先使用 rate() 或 increase()
2. 测量值指标：使用 avg_over_time(), max_over_time() 等
3. 处理分位数：使用 histogram_quantile()
4. 检测异常：使用 absent() 和 predict_linear()
5. 数据聚合：使用 sum(), avg(), max() 等聚合函数