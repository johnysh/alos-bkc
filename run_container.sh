#!/usr/bin/env bash
# set -euo pipefail

DEFAULT_IMAGE_NAME="alos_build:latest"
DEFAULT_CONTAINER_NAME="alos_yourname"
DEFAULT_HOST_PORT="6000"

prompt_with_default() {
    local prompt="$1"
    local default_value="$2"
    local input

    read -e -r -p "${prompt} [${default_value}]: " input
    if [[ -z "${input}" ]]; then
        echo "${default_value}"
    else
        echo "${input}"
    fi
}

create_container() {
    echo "=== 创建容器 ==="

    local image_name
    local container_name
    local host_port
    local source_dir
    local kernel_dir
    local grub_dir
    local git_user_name
    local git_user_email

    image_name="$(prompt_with_default "请输入镜像名" "${DEFAULT_IMAGE_NAME}")"
    container_name="$(prompt_with_default "请输入容器名称" "${DEFAULT_CONTAINER_NAME}")"
    host_port="$(prompt_with_default "请输入宿主机映射端口(映射到容器22)" "${DEFAULT_HOST_PORT}")"
    source_dir="$(prompt_with_default "请输入宿主机ALOS源代码目录(留空不映射)" "")"
    kernel_dir="$(prompt_with_default "请输入宿主机Kernel源代码目录(留空不映射)" "")"
    grub_dir="$(prompt_with_default "请输入宿主机alos-grub目录(留空不映射)" "")"

    if docker ps -a --format '{{.Names}}' | grep -Fxq "${container_name}"; then
        echo "错误: 容器 ${container_name} 已存在，请更换名称或先删除旧容器。"
        return 1
    fi

    if ! docker image inspect "${image_name}" >/dev/null 2>&1; then
        echo "错误: 镜像 ${image_name} 不存在，请先构建镜像。"
        return 1
    fi

    if lsof -i :"${host_port}" >/dev/null 2>&1; then
        echo "错误: 端口 ${host_port} 已被占用，请选择其他端口。"
        return 1
    fi

    echo "正在创建容器 ${container_name} ..."
    cmd="docker run --privileged -d --name \"${container_name}\" -p \"${host_port}:22\""
    if [[ -n "${source_dir}" ]] && [[ -d "${source_dir}" ]]; then
        cmd+=" -v \"${source_dir}:/root/alos\""
    fi
    if [[ -n "${kernel_dir}" ]] && [[ -d "${kernel_dir}" ]]; then
        cmd+=" -v \"${kernel_dir}:/root/kernel\""
    fi
    if [[ -n "${grub_dir}" ]] && [[ -d "${grub_dir}" ]]; then
        cmd+=" -v \"${grub_dir}:/root/grub\""
    fi
    cmd+=" \"${image_name}\""
    eval "${cmd}" >/dev/null

    read -e -r -p "请输入 git user.name: " git_user_name
    read -e -r -p "请输入 git user.email: " git_user_email

    if [[ -n "${git_user_name}" ]]; then
        docker exec "${container_name}" git config --global user.name "${git_user_name}"
    fi
    if [[ -n "${git_user_email}" ]]; then
        docker exec "${container_name}" git config --global user.email "${git_user_email}"
    fi

    echo "容器创建完成: ${container_name}"
    echo "端口映射: ${host_port} -> 22"
    [[ -n "${source_dir}" ]] && echo "ALOS 挂载 : ${source_dir} -> /root/alos"
    [[ -n "${kernel_dir}" ]] && echo "Kernel 挂载: ${kernel_dir} -> /root/kernel"
    [[ -n "${grub_dir}" ]]   && echo "GRUB 挂载  : ${grub_dir} -> /root/grub"
}

start_container() {
    echo "=== 启动容器 ==="
    local container_name

    container_name="$(prompt_with_default "请输入容器名称" "${DEFAULT_CONTAINER_NAME}")"

    if ! docker ps -a --format '{{.Names}}' | grep -Fxq "${container_name}"; then
        echo "错误: 容器 ${container_name} 不存在。"
        return 1
    fi

    if docker ps --format '{{.Names}}' | grep -Fxq "${container_name}"; then
        echo "容器 ${container_name} 已在运行。"
        return 0
    fi

    docker start "${container_name}" >/dev/null
    echo "容器 ${container_name} 已启动。"
}

enter_container() {
    echo "=== 进入容器 ==="
    local container_name

    container_name="$(prompt_with_default "请输入容器名称" "${DEFAULT_CONTAINER_NAME}")"

    if ! docker ps --format '{{.Names}}' | grep -Fxq "${container_name}"; then
        echo "错误: 容器 ${container_name} 未运行，请先启动。"
        return 1
    fi

    echo "正在进入容器 ${container_name} ..."
    docker exec -it "${container_name}" /bin/bash
}

show_menu() {
    echo
    echo "请选择功能:"
    echo "1) 创建容器并初始化配置"
    echo "2) 启动指定容器"
    echo "3) 进入正在运行的容器"
    echo "4) 退出"
}

main() {
    while true; do
        show_menu
        read -e -r -p "输入选项 [1-4]: " choice

        case "${choice}" in
            1)
                create_container
                ;;
            2)
                start_container
                ;;
            3)
                enter_container
                ;;
            4)
                echo "退出。"
                break
                ;;
            *)
                echo "无效选项，请输入 1-4。"
                ;;
        esac
    done
}

main
