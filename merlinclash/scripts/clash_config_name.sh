#!/bin/sh

require_config_name(){
    case "${1%.yaml}" in
        *[![:space:]]*) return 0 ;;
    esac
    echo "请先添加配置名称，再下载配置。" >&2
    return 1
}
