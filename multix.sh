#!/bin/bash

# ==================================================
# MultiX 监控系统一键管理脚本
# ==================================================
# 配置区域
SERVER_PORT=7575                  # 强制使用 7575 端口
APP_DIR="/opt/multix_monitor"     # 程序安装目录
SERVICE_NAME_MASTER="multix-master"
SERVICE_NAME_AGENT="multix-agent"
# ==================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 root 用户运行此脚本！${PLAIN}"
   exit 1
fi

# ==================================================
# 基础函数
# ==================================================

# 检查系统并安装依赖
check_sys_depend() {
    echo -e "${YELLOW}正在检查并安装系统依赖...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get update -y
        apt-get install -y wget curl python3 python3-pip git ufw
    elif [ -f /etc/redhat-release ]; then
        yum install -y wget curl python3 python3-pip git firewalld
    fi
    echo -e "${GREEN}依赖安装完成。${PLAIN}"
}

# 配置防火墙
open_firewall_port() {
    echo -e "${YELLOW}正在开放防火墙端口: ${SERVER_PORT}...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        ufw allow ${SERVER_PORT}/tcp
        ufw reload
    elif [ -f /etc/redhat-release ]; then
        firewall-cmd --zone=public --add-port=${SERVER_PORT}/tcp --permanent
        firewall-cmd --reload
    fi
}

# 停止服务
stop_service() {
    systemctl stop ${SERVICE_NAME_MASTER} 2>/dev/null
    systemctl stop ${SERVICE_NAME_AGENT} 2>/dev/null
}

# ==================================================
# 安装逻辑
# ==================================================

# 1. 安装主控端 (Master)
install_master() {
    check_sys_depend
    stop_service
    
    echo -e "${GREEN}>>> 正在安装 [主控面板] 到 ${APP_DIR} ...${PLAIN}"
    mkdir -p ${APP_DIR}
    
    # ----------------------------------------------------
    # [关键] 写入主控端代码
    # 这里使用 cat EOF 写入演示代码，实际使用时可替换为 git clone
    # ----------------------------------------------------
    cat > ${APP_DIR}/server.py <<EOF
import sys
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "MultiX Master Panel is Running on Port ${SERVER_PORT}"

if __name__ == '__main__':
    # 监听所有IP，端口 ${SERVER_PORT}
    print("Starting Master on port ${SERVER_PORT}...")
    app.run(host='0.0.0.0', port=${SERVER_PORT})
EOF

    # 安装 Python 依赖
    pip3 install flask

    # 创建系统服务
    cat > /etc/systemd/system/${SERVICE_NAME_MASTER}.service <<EOF
[Unit]
Description=MultiX Master Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/server.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 启动
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME_MASTER}
    systemctl start ${SERVICE_NAME_MASTER}
    
    open_firewall_port
    
    # 标记安装类型
    echo "master" > ${APP_DIR}/.role

    echo -e "------------------------------------------------"
    echo -e "${GREEN}主控端安装成功！${PLAIN}"
    echo -e "访问地址: http://$(curl -s ifconfig.me):${SERVER_PORT}"
    echo -e "------------------------------------------------"
}

# 2. 安装被控端 (Agent)
install_agent() {
    check_sys_depend
    stop_service

    echo -e "${YELLOW}请输入主控端 IP 地址:${PLAIN}"
    read -p "(默认: 127.0.0.1): " MASTER_IP
    [[ -z "${MASTER_IP}" ]] && MASTER_IP="127.0.0.1"

    echo -e "${GREEN}>>> 正在安装 [被控端 Agent] 到 ${APP_DIR} ...${PLAIN}"
    mkdir -p ${APP_DIR}

    # ----------------------------------------------------
    # [关键] 写入被控端代码
    # ----------------------------------------------------
    cat > ${APP_DIR}/agent.py <<EOF
import time
import sys

def main():
    print("MultiX Agent Started...")
    print("Connecting to Master at ${MASTER_IP}:${SERVER_PORT}")
    while True:
        # 这里写你的上报逻辑
        time.sleep(10)

if __name__ == '__main__':
    main()
EOF
    
    # 创建配置文件
    echo "MASTER_IP=${MASTER_IP}" > ${APP_DIR}/config.env
    echo "MASTER_PORT=${SERVER_PORT}" >> ${APP_DIR}/config.env

    # 创建系统服务
    cat > /etc/systemd/system/${SERVICE_NAME_AGENT}.service <<EOF
[Unit]
Description=MultiX Agent Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/agent.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 启动
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME_AGENT}
    systemctl start ${SERVICE_NAME_AGENT}

    # 标记安装类型
    echo "agent" > ${APP_DIR}/.role

    echo -e "${GREEN}被控端安装成功！正在后台运行。${PLAIN}"
}

# 3. 卸载
uninstall_all() {
    echo -e "${YELLOW}正在停止并移除服务...${PLAIN}"
    systemctl stop ${SERVICE_NAME_MASTER} 2>/dev/null
    systemctl disable ${SERVICE_NAME_MASTER} 2>/dev/null
    rm -f /etc/systemd/system/${SERVICE_NAME_MASTER}.service
    
    systemctl stop ${SERVICE_NAME_AGENT} 2>/dev/null
    systemctl disable ${SERVICE_NAME_AGENT} 2>/dev/null
    rm -f /etc/systemd/system/${SERVICE_NAME_AGENT}.service
    
    systemctl daemon-reload
    
    echo -e "${YELLOW}正在删除文件...${PLAIN}"
    rm -rf ${APP_DIR}
    
    echo -e "${GREEN}卸载完成。${PLAIN}"
}

# ==================================================
# 菜单界面
# ==================================================
show_menu() {
    clear
    echo -e "============================================"
    echo -e "    ${GREEN}MultiX 监控系统一键脚本${PLAIN} ${YELLOW}[Port: ${SERVER_PORT}]${PLAIN}"
    echo -e "============================================"
    
    # 状态检测
    if [ -f "${APP_DIR}/.role" ]; then
        ROLE=$(cat ${APP_DIR}/.role)
        if [ "$ROLE" == "master" ]; then
            STATUS=$(systemctl is-active ${SERVICE_NAME_MASTER})
            echo -e "当前状态: ${GREEN}已安装主控端 (Master)${PLAIN} | 运行状态: ${YELLOW}${STATUS}${PLAIN}"
        elif [ "$ROLE" == "agent" ]; then
            STATUS=$(systemctl is-active ${SERVICE_NAME_AGENT})
            echo -e "当前状态: ${GREEN}已安装被控端 (Agent)${PLAIN} | 运行状态: ${YELLOW}${STATUS}${PLAIN}"
        fi
    else
        echo -e "当前状态: ${RED}未安装${PLAIN}"
    fi
    
    echo -e "============================================"
    echo -e "1. 安装/重装 主控面板 (Master)"
    echo -e "2. 安装/重装 被控端 (Agent)"
    echo -e "--------------------------------------------"
    echo -e "3. 启动服务"
    echo -e "4. 停止服务"
    echo -e "5. 重启服务"
    echo -e "6. 查看运行日志"
    echo -e "--------------------------------------------"
    echo -e "9. 卸载程序"
    echo -e "0. 退出"
    echo -e "============================================"
    read -p "请输入选项 [0-9]: " OPT
    
    case $OPT in
        1) install_master ;;
        2) install_agent ;;
        3) 
           systemctl start ${SERVICE_NAME_MASTER} 2>/dev/null
           systemctl start ${SERVICE_NAME_AGENT} 2>/dev/null
           echo -e "${GREEN}服务已尝试启动${PLAIN}"
           ;;
        4) stop_service; echo -e "${GREEN}服务已停止${PLAIN}" ;;
        5) 
           stop_service
           systemctl start ${SERVICE_NAME_MASTER} 2>/dev/null
           systemctl start ${SERVICE_NAME_AGENT} 2>/dev/null
           echo -e "${GREEN}服务已重启${PLAIN}" 
           ;;
        6) 
            if [ -f "${APP_DIR}/.role" ] && [ "$(cat ${APP_DIR}/.role)" == "master" ]; then
                journalctl -u ${SERVICE_NAME_MASTER} -f
            else
                journalctl -u ${SERVICE_NAME_AGENT} -f
            fi
            ;;
        9) uninstall_all ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}" ;;
    esac
}

# 运行菜单
show_menu
