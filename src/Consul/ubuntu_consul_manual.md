sudo -u consul_1.14.10 /data/consul/base_1.14.10/consul agent -config-dir=/etc/consul.d/conf_1.14.10

su - consul -c "nohup /usr/bin/consul agent -server -ui -node=server-01 -client=0.0.0.0 -bootstrap-expect=3 -config-dir=/etc/consul.d/ -data-dir=/home/consul/data -bind=172.16.47.208 &"