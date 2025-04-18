#!/bin/bash

ES_USER="es_admin"
ACTION=$1
VERSION=$2

usage() {
    echo "Usage: $0 {start|stop|restart|status} {7.10.2|7.6.2}"
    exit 1
}

control_es() {
    local action=$1
    local version=$2
    local es_home="/data/es-${version}"
    
    case ${action} in
        start)
            su - ${ES_USER} -c "ES_HOME=${es_home} ${es_home}/bin/elasticsearch -d"
            ;;
        stop)
            pkill -f "es-${version}"
            ;;
        restart)
            control_es stop ${version}
            sleep 5
            control_es start ${version}
            ;;
        status)
            curl -u "es_admin:Secsmart#612" "http://localhost:9200/_cluster/health?pretty"
            ;;
        *)
            usage
            ;;
    esac
}

[ $# -ne 2 ] && usage
control_es "$ACTION" "$VERSION"