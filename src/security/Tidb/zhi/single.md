准备环境

开始部署 TiDB 集群前，准备一台部署主机，确保其软件满足需求：

推荐安装 CentOS 7.3 及以上版本
运行环境可以支持互联网访问，用于下载 TiDB 及相关软件安装包
最小规模的 TiDB 集群拓扑包含以下实例：

实例	个数	IP	配置
TiKV	3	10.0.1.1	使用递增的端口号以避免冲突
TiDB	1	10.0.1.1	使用默认端口和其他配置
PD	1	10.0.1.1	使用默认端口和其他配置
TiFlash	1	10.0.1.1	使用默认端口和其他配置
Monitor	1	10.0.1.1	使用默认端口和其他配置
注意
该表中拓扑实例的 IP 为示例 IP。在实际部署时，请替换为实际的 IP。
部署主机软件和环境要求如下：

部署需要使用部署主机的 root 用户及密码
部署主机关闭防火墙或者开放 TiDB 集群的节点间所需端口
目前 TiUP Cluster 支持在 x86_64（AMD64）和 ARM 架构上部署 TiDB 集群
在 AMD64 架构下，建议使用 CentOS 7.3 及以上版本 Linux 操作系统
在 ARM 架构下，建议使用 CentOS 7.6 (1810) 版本 Linux 操作系统
实施部署

注意
你可以使用 Linux 系统的任一普通用户或 root 用户登录主机，以下步骤以 root 用户为例。
下载并安装 TiUP：

curl --proto '=https' --tlsv1.2 -sSf https://tiup-mirrors.pingcap.com/install.sh | sh
声明全局环境变量：

注意
TiUP 安装完成后会提示对应 Shell profile 文件的绝对路径。在执行以下 source 命令前，需要将 ${your_shell_profile} 修改为 Shell profile 文件的实际位置。
source ${your_shell_profile}
安装 TiUP 的 cluster 组件：

tiup cluster
如果机器已经安装 TiUP cluster，需要更新软件版本：

tiup update --self && tiup update cluster
由于模拟多机部署，需要通过 root 用户调大 sshd 服务的连接数限制：

修改 /etc/ssh/sshd_config 将 MaxSessions 调至 20。

重启 sshd 服务：

service sshd restart
创建并启动集群：

按下面的配置模板，创建并编辑拓扑配置文件，命名为 topo.yaml。其中：

user: "tidb"：表示通过 tidb 系统用户（部署会自动创建）来做集群的内部管理，默认使用 22 端口通过 ssh 登录目标机器
replication.enable-placement-rules：设置这个 PD 参数来确保 TiFlash 正常运行
host：设置为本部署主机的 IP
配置模板如下：

# # Global variables are applied to all deployments and used as the default value of
# # the deployments if a specific deployment value is missing.
global:
 user: "tidb"
 ssh_port: 22
 deploy_dir: "/tidb-deploy"
 data_dir: "/tidb-data"

# # Monitored variables are applied to all the machines.
monitored:
 node_exporter_port: 9100
 blackbox_exporter_port: 9115

server_configs:
 tidb:
   instance.tidb_slow_log_threshold: 300
 tikv:
   readpool.storage.use-unified-pool: false
   readpool.coprocessor.use-unified-pool: true
 pd:
   replication.enable-placement-rules: true
   replication.location-labels: ["host"]
 tiflash:
   logger.level: "info"

pd_servers:
 - host: 10.0.1.1

tidb_servers:
 - host: 10.0.1.1

tikv_servers:
 - host: 10.0.1.1
   port: 20160
   status_port: 20180
   config:
     server.labels: { host: "logic-host-1" }

 - host: 10.0.1.1
   port: 20161
   status_port: 20181
   config:
     server.labels: { host: "logic-host-2" }

 - host: 10.0.1.1
   port: 20162
   status_port: 20182
   config:
     server.labels: { host: "logic-host-3" }

tiflash_servers:
 - host: 10.0.1.1

monitoring_servers:
 - host: 10.0.1.1

grafana_servers:
 - host: 10.0.1.1
执行集群部署命令：

tiup cluster deploy <cluster-name> <version> ./topo.yaml --user root -p
参数 <cluster-name> 表示设置集群名称

参数 <version> 表示设置集群版本，例如 v8.5.1。可以通过 tiup list tidb 命令来查看当前支持部署的 TiDB 版本

参数 --user 表示初始化环境的用户

参数 -p 表示在连接目标机器时使用密码登录

注意
如果主机通过密钥进行 SSH 认证，请使用 -i 参数指定密钥文件路径，-i 与 -p 不可同时使用。
按照引导，输入”y”及 root 密码，来完成部署：

Do you want to continue? [y/N]:  y
Input SSH password:
启动集群：

tiup cluster start <cluster-name>
访问集群端点：

安装 MySQL 客户端。如果已安装，则跳过这一步骤。

yum -y install mysql
使用 MySQL 客户端访问 TiDB 数据库，密码为空：

mysql -h 10.0.1.1 -P 4000 -u root
访问 Grafana 监控页面：http://{grafana-ip}:3000，默认用户名和密码均为 admin。

访问集群 TiDB Dashboard 监控页面：http://{pd-ip}:2379/dashboard，默认用户名为 root，密码为空。

（可选）查看集群列表和拓扑结构：

执行以下命令确认当前已经部署的集群列表：

tiup cluster list
执行以下命令查看集群的拓扑结构和状态：

tiup cluster display <cluster-name>
要了解更多 tiup cluster 命令，请参阅 TiUP 集群命令。