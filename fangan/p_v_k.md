好的，我们来详细解析 Prometheus -> VictoriaMetrics -> Kafka 这个数据管道的完整配置和数据传输过程。这个方案的核心是利用 VictoriaMetrics 作为强大的中间处理和缓冲层。

架构与数据流全景图

flowchart TD
subgraph "数据采集层"
    A[Prometheus<br/>抓取节点/metrics]
    B[其他数据源<br/>Node Exporter, 应用等]
end

subgraph "核心存储与处理层"
    C[VictoriaMetrics<br/>接收/存储/查询]
end

subgraph "数据导出层"
    D[vmagent<br/>远程读取/过滤/导出]
end

subgraph "数据分发与缓冲层"
    E[Kafka Adapter<br/>协议转换]
    F[(Kafka Message Queue)]
end

subgraph "数据消费层"
    G[业务系统 A<br/>实时告警]
    H[业务系统 B<br/>数据分析]
    I[业务系统 C<br/>监控面板]
end

A -- Prometheus Remote Write --> C
B -- Prometheus Remote Write --> C

C -- VictoriaMetrics Remote Read --> D
D -- HTTP Post --> E
E -- Kafka Producer Protocol --> F

F -- Kafka Consumer Protocol --> G
F -- Kafka Consumer Protocol --> H
F -- Kafka Consumer Protocol --> I


上图展示了数据的完整旅程，下面我们分步详解每个环节的配置和原理。

第一步：Prometheus 写入 VictoriaMetrics

配置 Prometheus

# prometheus.yml
global:
  scrape_interval: 15s
  external_labels:
    cluster: 'prod-cluster'
    __replica__: 'prometheus-01' # 高可用标识

# 抓取配置
scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node1:9100', 'node2:9100', 'node3:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115 # 如果有黑盒监控

# 核心配置：远程写入 VictoriaMetrics
remote_write:
  - url: http://victoria-metrics:8428/api/v1/write
    queue_config:
      max_samples_per_send: 10000  # 每次发送最大样本数
      capacity: 20000              # 队列容量
      max_shards: 100              # 并发分片数
    write_relabel_configs:
      - source_labels: [__name__]
        regex: '(node_.*|vmware_.*|container_.*)' # 只写入物理机/虚拟机指标
        action: keep


数据流说明

1.  数据采集：Prometheus 按 scrape_interval 从各 target 抓取指标。
2.  内存处理：数据在内存中排队、分批。
3.  远程写入：通过 HTTP Protobuf 协议将数据批量发送到 VictoriaMetrics 的 /api/v1/write 端点。
4.  可靠性：queue_config 确保在网络抖动或 VM 短暂不可用时，数据不会丢失，会在内存中重试。

第二步：配置 VictoriaMetrics

启动 VictoriaMetrics

# 单节点模式或集群模式下的 vmstorage 组件
./vmstorage \
  -retentionPeriod=2h \          # 在VM中只存2小时，因为我们要尽快导出到Kafka
  -storageDataPath=/data/vmstorage \
  -httpListenAddr=:8428 \
  -vminsertAddr=:8400 \
  -vmselectAddr=8401


关键参数解析：
•   -retentionPeriod=2h： 设置一个短保留期非常重要。我们的目标不是将数据长期保存在 VM 中，而是将其作为一个缓冲和实时查询层。数据会很快被导出到 Kafka，因此不需要长的保留时间，这可以节省 VM 的存储资源。

•   -vminsertAddr： 接收 Prometheus remote_write 数据的端口。

•   -vmselectAddr： 供 vmagent 查询读取数据的端口。

第三步：vmagent 从 VM 读取并写入 Kafka Adapter

这是整个流程的核心桥梁。vmagent 在这里扮演了一个“导出器”的角色。

启动与配置 vmagent

vmagent \
  -remoteRead.url=http://victoria-metrics:8428/api/v1/read \
  -remoteRead.streamParse=true \
  -remoteRead.lookback=6h \   # ★ 核心参数：告诉VM我要读取最近6小时的数据
  -remoteRead.forcedStartTime=$(date -d "6 hours ago" +%s) \
  -remoteRead.filter='{job=~"node-exporter|vmware-exporter"}' \ # 只导出特定job的数据
  -remoteWrite.url=http://kafka-adapter:8080/receive \
  -remoteWrite.queues=4 \
  -remoteWrite.maxBlockSize=10000 \
  -httpListenAddr=:8429 # 暴露自身指标


数据流说明

1.  初始化与查询：vmagent 启动后，立即向 VictoriaMetrics 的 /api/v1/read 端点发起查询。-remoteRead.lookback=6h 参数是关键，它定义了查询的时间范围是从现在开始往回6小时。
2.  流式拉取：-streamParse=true 使得 VM 以流式（Streaming）方式返回数据，而不是一次性返回所有数据。这对于处理大量数据至关重要，可以避免内存溢出。
3.  数据处理与转发：vmagent 接收到数据流后，会进行必要的过滤和分批处理，然后通过 HTTP POST 请求将数据发送到 Kafka Adapter 的 /receive 端点。
4.  持续运行：这个过程不是一次性的。vmagent 会持续运行，定期（或根据配置）从 VictoriaMetrics 拉取最新的数据并转发出去，从而实现近乎实时的数据导出。

第四步：Kafka Adapter 接收并写入 Kafka

部署 Kafka Adapter

docker run -d --name kafka-adapter \
  -p 8080:8080 \
  -e KAFKA_BROKERS=kafka-broker1:9092,kafka-broker2:9092 \
  -e KAFKA_TOPIC=infra-metrics \       # Kafka主题名
  -e SERVER_PORT=8080 \
  -e LOG_LEVEL=info \
  -e KAFKA_COMPRESSION=snappy \        # 使用Snappy压缩，节省带宽
  telefonica/prometheus-kafka-adapter


数据流说明

1.  协议转换：Kafka Adapter 接收来自 vmagent 的 HTTP 请求（内容是 Prometheus 格式的指标数据）。
2.  消息构造：它将接收到的数据转换为 Kafka 消息。默认通常是一个 JSON 对象，包含 metric（标签）、value（值）和 timestamp（时间戳）。
3.  生产到 Kafka：使用配置好的 Kafka 生产者将消息发送到指定的 infra-metrics Topic 中。KAFKA_COMPRESSION=snappy 可以显著减少网络传输的数据量。

第五步：配置 Kafka Topic（6小时保留）

这是满足您需求的关键步骤。
# 创建Topic
kafka-topics.sh --create \
  --bootstrap-server kafka-broker1:9092 \
  --replication-factor 2 \
  --partitions 10 \          # 根据吞吐量设置分区数
  --topic infra-metrics

# ★ 配置6小时数据保留策略
kafka-configs.sh --alter \
  --bootstrap-server kafka-broker1:9092 \
  --entity-type topics \
  --entity-name infra-metrics \
  --add-config retention.ms=21600000 # 6 * 60 * 60 * 1000 = 21600000毫秒


核心原理：Kafka Broker 会持续检查每个 Topic 中消息的留存时间。一旦消息的存活时间超过 retention.ms 设置的值（这里是6小时），Broker 就会自动删除这些旧消息，从而确保 Topic 只保留最新6小时的数据。这个过程是自动的，无需人工干预。

第六步：业务系统消费 Kafka 数据

业务系统作为 Kafka 消费者，从 infra-metrics Topic 中拉取数据。

Python 消费示例

from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    'infra-metrics',
    bootstrap_servers=['kafka-broker1:9092', 'kafka-broker2:9092'],
    group_id='my-business-service', # 消费组ID，用于偏移量管理
    auto_offset_reset='latest',     # 如果没有偏移量，从最新消息开始读
    value_deserializer=lambda m: json.loads(m.decode('utf-8'))
)

for message in consumer:
    metric_data = message.value
    # 示例: {'metric': {'__name__': 'node_cpu_seconds_total', 'mode':'idle'}, 'value': [1700000000, 0.8]}
    timestamp = metric_data['value'][0]
    value = metric_data['value'][1]
    labels = metric_data['metric']
    
    print(f"Received: {labels} = {value} @ {timestamp}")
    # 在这里进行您的业务逻辑处理，比如告警、分析、入库等


总结与关键点

阶段 组件 核心作用 协议 关键配置

采集 Prometheus 抓取原始指标 HTTP remote_write

存储/缓冲 VictoriaMetrics 短期存储，提供查询 HTTP Protobuf/JSON -retentionPeriod=2h

导出 vmagent ★ 核心桥梁，持续查询并转发 HTTP -remoteRead.lookback=6h

转换 Kafka Adapter 协议转换 (HTTP -> Kafka) HTTP -> Kafka KAFKA_TOPIC, KAFKA_BROKERS

存储 Kafka 消息队列，保证6小时保留 Kafka Protocol retention.ms=21600000

消费 业务系统 消费数据实现业务逻辑 Kafka Protocol group_id, auto_offset_reset

数据延迟： 这个管道的端到端延迟主要取决于 vmagent 的查询间隔和 Kafka 的处理速度。如果 vmagent 配置为频繁查询（例如每秒一次），延迟可以控制在几十秒到几分钟内，这对于大多数监控和业务场景是完全可接受的。

此方案的优势在于利用 VictoriaMetrics 的强大能力，实现了数据的可靠缓冲和灵活筛选，再通过 Kafka 实现与业务系统的解耦和数据生命周期管理。