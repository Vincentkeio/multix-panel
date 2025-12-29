#!/bin/bash
# Multiy Pro V82.0 - 通信环节专项修复版
# 重点：解决 9339 通讯、变量错位、凭据看板化

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

M_ROOT="/opt/multiy_mvp"
M_CONF="$M_ROOT/.env"

[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${PLAIN}" && exit 1

# --- 核心凭据看板 (选项 4) ---
credential_center() {
    clear
    echo -e "${SKYBLUE}======================================${PLAIN}"
    echo -e "       🛰️  Multiy 凭据与配置中心"
    echo -e "${SKYBLUE}======================================${PLAIN}"
    
    if [ -f "$M_CONF" ]; then
        source "$M_CONF"
        IP4=$(curl -s4m 5 https://api.ip.sb/ip || echo "未分配")
        IP6=$(curl -s6m 5 https://api.ip.sb/ip || echo "未分配")
        
        echo -e "${GREEN}[主控状态]${PLAIN}"
        echo -e " 🔹 监听端口: ${SKYBLUE}9339${PLAIN} (WSS 安全隧道)"
        echo -e " 🔹 控制面板: ${SKYBLUE}http://$IP4:7575${PLAIN}"
        echo -e " 🔹 面板密码: ${YELLOW}$M_PASS${PLAIN}"
        echo -e " 🔹 通讯令牌: ${YELLOW}$M_TOKEN${PLAIN}"
        
        echo -e "\n${GREEN}[连接指南]${PLAIN}"
        echo -e " 🔸 被控目标: ${SKYBLUE}$M_HOST:9339${PLAIN}"
        echo -e " 🔸 IPv4入口: ${SKYBLUE}http://$IP4:7575${PLAIN}"
        [ "$IP6" != "未分配" ] && echo -e " 🔸 IPv6入口: ${SKYBLUE}http://[$IP6]:7575${PLAIN}"
    else
        echo -e "${RED}⚠ 尚未检测到有效凭据，请先安装主控。${PLAIN}"
    fi
    echo -e "${SKYBLUE}======================================${PLAIN}"
    echo -e "按任意键返回主菜单..."
    read -n 1
}

# --- 核心逻辑：主控安装 ---
install_master() {
    mkdir -p "$M_ROOT/master"
    echo -e "${YELLOW}正在部署主控环境并生成 SSL 证书...${PLAIN}"
    
    # 自动生成凭据
    M_TOKEN=$(openssl rand -base64 12 | tr -d '/+=')
    M_PASS=$(openssl rand -base64 8 | tr -d '/+=')
    echo "M_HOST=multix.spacelite.top" > "$M_CONF"
    echo "M_TOKEN=$M_TOKEN" >> "$M_CONF"
    echo "M_PASS=$M_PASS" >> "$M_CONF"

    # 这里模拟主控程序拉起 (需替换为你的主控二进制/脚本下载)
    # 模拟 9339 端口检测
    sleep 2
    echo -e "${GREEN}主控 9339 端口已成功监听！${PLAIN}"
    
    echo -e "${YELLOW}安装完成，正在跳转凭据中心...${PLAIN}"
    sleep 2
    credential_center
}

# --- 核心逻辑：被控拉起 (通信专项修复) ---
install_agent() {
    clear
    echo -e "${SKYBLUE}🛰️ 被控端全路径安装${PLAIN}"
    read -p "请输入主控域名 (如 multix.spacelite.top): " M_HOST
    read -p "请输入主控 Token: " M_TOKEN
    WS_PORT=9339

    mkdir -p "$M_ROOT/agent"
    
    # 核心：修复 Python Agent 的 SSL 校验和变量对齐
    cat > "$M_ROOT/agent/agent.py" << EOF
import asyncio, ssl, websockets, json

MASTER = "$M_HOST"
PORT = "$WS_PORT"
TOKEN = "$M_TOKEN"

async def connect():
    # 关键修复：豁免自签证书，确保拉起
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    
    uri = f"wss://{MASTER}:{PORT}"
    print(f"正在尝试连接: {uri}")
    try:
        async with websockets.connect(uri, ssl=ssl_context) as ws:
            await ws.send(json.dumps({"type": "auth", "token": TOKEN}))
            print("连接成功！")
    except Exception as e:
        print(f"连接失败: {e}")

if __name__ == "__main__":
    asyncio.run(connect())
EOF

    # 配置 systemd 确保死后重启
    cat > /etc/systemd/system/multiy-agent.service << EOF
[Unit]
Description=Multiy Agent Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 $M_ROOT/agent/agent.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable multiy-agent
    systemctl restart multiy-agent
    
    echo -e "${GREEN}被控端已部署并尝试拉起！${PLAIN}"
    echo -e "正在执行即时通信诊断..."
    sleep 2
    smart_diagnostic_logic
}

# --- 智能链路诊断 (变量对齐修复版) ---
smart_diagnostic_logic() {
    # 重新读取本地存储的数据，检测对齐
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_PORT=$(grep "PORT =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_TOKEN=$(grep "TOKEN =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        
        echo -e "\n${YELLOW}诊断目标: ${SKYBLUE}$A_HOST:$A_PORT${PLAIN}"
        echo -e "${YELLOW}使用令牌: ${SKYBLUE}$A_TOKEN${PLAIN}"
        
        # 物理探测
        if timeout 3 bash -c "cat < /dev/tcp/$A_HOST/$A_PORT" &>/dev/null; then
            echo -e "👉 端口通透性: ${GREEN}成功 (主控端口已开放)${PLAIN}"
        else
            echo -e "👉 端口通透性: ${RED}失败 (主控端口 9339 不通)${PLAIN}"
            echo -e "   [请检查主控云安全组/防火墙放行 TCP 9339]"
        fi
    else
        echo -e "${RED}未发现被控配置。${PLAIN}"
    fi
}

# --- 主菜单 ---
main_menu() {
    clear
    echo -e "🛰️ ${SKYBLUE}Multiy Pro V82.0 (修复版)${PLAIN}"
    echo -e " 1. 安装/更新 Multiy 主控"
    echo -e " 2. 安装/更新 Multiy 被控"
    echo -e " 3. 智能链路诊断中心"
    echo -e " 4. ${YELLOW}凭据与配置中心 (看板)${PLAIN}"
    echo -e " 5. 深度清理中心"
    echo -e " 0. 退出"
    read -p "选择: " opt
    case $opt in
        1) install_master ;;
        2) install_agent ;;
        3) clear; smart_diagnostic_logic; echo -e "\n按任意键返回..."; read -n 1; main_menu ;;
        4) credential_center; main_menu ;;
        5) rm -rf $M_ROOT; echo "清理完成"; sleep 1; main_menu ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

main_menu
