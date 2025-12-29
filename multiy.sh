#!/bin/bash

# 修复版 MultiY 脚本
# 修复了 Python 代码被 Shell 错误执行的语法问题

# 定义颜色
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 安装目录
install_path="/usr/local/multix"
config_path="${install_path}/config.json"
service_path="/etc/systemd/system/multix.service"

# 安装必要的依赖
install_dependencies() {
    echo -e "${green}正在更新系统并安装依赖...${plain}"
    if [[ -f /etc/debian_version ]]; then
        apt-get update
        apt-get install -y wget curl git python3 python3-pip socat
    elif [[ -f /etc/redhat-release ]]; then
        yum update -y
        yum install -y wget curl git python3 python3-pip socat
    else
        echo -e "${red}不支持的操作系统${plain}"
        exit 1
    fi
    
    echo -e "${green}正在安装 Python 依赖...${plain}"
    pip3 install aiohttp
}

# 核心功能：生成 Python 后端文件
# 这里是之前报错的地方，已修复 cat 命令包裹
install_multix_files() {
    mkdir -p ${install_path}
    
    # 写入 Python 主程序
    cat > ${install_path}/main.py <<EOF
import asyncio
import json
import os
import sys
import logging
from aiohttp import web

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

CONFIG_FILE = '${config_path}'

def load_config():
    if not os.path.exists(CONFIG_FILE):
        return {}
    with open(CONFIG_FILE, 'r') as f:
        try:
            return json.load(f)
        except:
            return {}

async def handle(request):
    return web.Response(text="MultiX Panel is running")

async def ws_handler(ws):
    async for msg in ws:
        if msg.type == web.WSMsgType.TEXT:
            if msg.data == 'close':
                await ws.close()
            else:
                await ws.send_str(msg.data + '/answer')
        elif msg.type == web.WSMsgType.ERROR:
            print('ws connection closed with exception %s', ws.exception())
    return ws

async def init_app():
    app = web.Application()
    app.add_routes([web.get('/', handle)])
    return app

if __name__ == '__main__':
    try:
        if sys.platform == 'win32':
            loop = asyncio.ProactorEventLoop()
            asyncio.set_event_loop(loop)
        
        app = init_app()
        web.run_app(app, port=54321)
    except Exception as e:
        logger.error(f"Error: {e}")
EOF

    # 赋予执行权限
    chmod +x ${install_path}/main.py
}

# 配置 Systemd 服务
create_service() {
    echo -e "${green}正在创建系统服务...${plain}"
    cat > ${service_path} <<EOF
[Unit]
Description=MultiX Panel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${install_path}
ExecStart=/usr/bin/python3 ${install_path}/main.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable multix
    systemctl restart multix
}

# 菜单功能
show_menu() {
    echo -e "
  ${green}MultiX 面板管理脚本${plain}
--- https://github.com/Vincentkeio/multix-panel ---

  ${green}1.${plain} 安装面板
  ${green}2.${plain} 卸载面板
  ${green}3.${plain} 重启面板
  ${green}4.${plain} 停止面板
  ${green}5.${plain} 查看日志
  ${green}0.${plain} 退出脚本
 "
    echo && read -p "请输入选择 [0-5]: " num

    case "${num}" in
        0) exit 0
        ;;
        1) install_panel
        ;;
        2) uninstall_panel
        ;;
        3) restart_panel
        ;;
        4) stop_panel
        ;;
        5) show_log
        ;;
        *) echo -e "${red}请输入正确的数字 [0-5]${plain}"
        ;;
    esac
}

install_panel() {
    install_dependencies
    install_multix_files
    create_service
    echo -e "${green}面板安装成功！${plain}"
    echo -e "默认端口: 54321"
}

uninstall_panel() {
    systemctl stop multix
    systemctl disable multix
    rm -rf ${install_path}
    rm -f ${service_path}
    systemctl daemon-reload
    echo -e "${green}面板卸载成功！${plain}"
}

restart_panel() {
    systemctl restart multix
    echo -e "${green}面板已重启${plain}"
}

stop_panel() {
    systemctl stop multix
    echo -e "${green}面板已停止${plain}"
}

show_log() {
    journalctl -u multix -f
}

# 脚本入口
show_menu
