- 步骤2：规划镜像数据存储路径
    ```bash
    mkdir -p /home/dockerImages/rede_dataOfContainer/oracle19cee
    cd /home/dockerImages/rede_dataOfContainer
    chmod 777 oracle19cee
    ```

- 步骤3：实例化镜像参数修改
    ```bash
    docker run -it \
    --name="c_Oracle19c" \
    --privileged \
    --restart=always \
    -p 15312:1521  \
    -p 15313:5500  \
    -v /home/dockerImages/rede_dataOfContainer/oracle19cee:/opt/oracle/oradata \
    -e ORACLE_ALLOW_REMOTE=true \
    -d heartu41/oracle19c
    ```

    参照上面的步骤，我将oracle19c部署在/data/oracle19c路径中，帮我调整下脚本