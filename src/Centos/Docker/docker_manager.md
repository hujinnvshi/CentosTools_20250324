我需要在 CentOS Linux release 7.9.2009 (Core) 
管理当前的全部Docker实例
先展示目前全部的Docker实例,只展示 CONTAINER ID，IMAGE，CREATED ，STATUS  这些信息
将信息保存到文件：docker_instance_yyyymmddhh24miss.md 文件中,位置在/var/www/html/docker 目录下
帮我生成清理Exited状态的实例的bash脚本,也保存在/var/www/html/docker 目录下
/var/www/html/docker 如何不存在需要自行创建
请提供满足上述需求的一键执行 Python 脚本。 

我想要在 CentOS Linux release 7.9.2009 (Core) 操作系统环境下，对当前所有的 Docker 实例进行管理操作。具体需求如下：
首先，需要展示系统当下全部的 Docker 实例信息，仅提取并展示 CONTAINER ID、IMAGE、CREATED 以及 STATUS 这几个关键信息列，以清晰呈现各个实例的基本状态。
接着，将这些提取出的 Docker 实例信息保存至一个名为 “docker_instance_yyyymmddhh24miss.md” 的文件中，该文件需存储在 “/var/www/html/docker” 目录下。若此目录不存在，则脚本应具备自动创建该目录的功能。
还需要生成一个用于清理处于 Exited 状态的 Docker 实例的 bash 脚本，同样将其保存在 “/var/www/html/docker” 目录下。
还需要生成一个用于关闭处于 运行 状态的 Docker 实例的 bash 脚本，同样将其保存在 “/var/www/html/docker” 目录下。
还需要生成一个用于启动处于 关闭 状态的 Docker 实例的 bash 脚本，同样将其保存在 “/var/www/html/docker” 目录下。
请编写一个能够一键执行，满足上述所有需求的 Python 脚本。


在 CentOS Linux release 7.9.2009 (Core) 操作系统的应用场景下，我期望实现对当前所有 Docker 实例的全面且便捷的管理操作。详细的功能诉求如下：
其一，精准聚焦关键信息展示环节，系统需快速且准确地呈现出当下全部 Docker 实例的核心数据，仅筛选并输出Name CONTAINER ID、IMAGE、CREATED 以及 STATUS 这四项极具代表性的信息列，以便使用者能够一目了然地洞察各个实例的基础运行状态，为后续决策提供有力的数据支撑。
其二，重视数据的留存与整理，将提取到的上述 Docker 实例信息，妥善保存至一个按照特定格式命名的文件 ——“docker_instance_yyyymmddhh24miss.md” 之中，该文件的存储路径指定为 “/var/www/html/docker” 目录。值得注意的是，倘若此目录在系统中尚未存在，那么执行脚本时应自动触发创建该目录的机制，确保文件存储环节的顺畅无阻。
其三，着眼于实例状态的优化调整，分别生成三个具备针对性功能的 bash 脚本：
第一个 bash 脚本旨在高效清理那些处于 Exited 状态的 Docker 实例，及时回收系统资源，避免资源浪费；
第二个 bash 脚本专注于关闭当前处于运行状态的 Docker 实例，满足特定场景下对系统负载或资源调配的临时性管控需求；
第三个 bash 专用脚本致力于启动那些处于关闭状态的 Docker 实例，以便快速恢复相关服务或应用的运行，保障业务的连续性。
以上这三个 bash 脚本同样都要保存在 “/var/www/html/docker” 目录下，以便于统一管理与后续调用。
最后，尤为关键的是，期望您能编写一个高度集成、一键即可顺利执行的 Python2.7 脚本，使其能够完美满足上述所有精细化的需求，为 Docker 实例管理工作带来极大的便利与高效,注意在代码中尽量不要出现中文，避免乱码问题