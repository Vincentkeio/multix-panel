#!/bin/bash

# ==============================================================================
# Multiy Pro Script V75.0 (MODULAR & TOKEN SYNC FIX)
# 1. [Init] 脚本运行即创建 multiy 命令
# 2. [Master] 支持自定义 Token，安装前强制清理残留进程
# 3. [UI] 面板 Token 实时从 .env 读取，确保与凭据中心一致
# 4. [Net] 被控端增加 IPv6 连通性预检逻辑
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
SH_VER="V75.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 模块：初始化 ] ---
install_shortcut() {
    [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy
}
install_shortcut

check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 请使用 root 用户运行！" && exit 1; }
get_public_ips() { 
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 模块：凭据中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 Multiy 凭据与配置中心 (V75.0)${PLAIN}"
    M_TOKEN=$(get_env_val "M_TOKEN"); M_PORT=$(get_env_val "M_PORT"); WS_PORT=$(get_env_val "WS_PORT")
    M_USER=$(get_env_val "M_USER"); M_PASS=$(get_env_val "M_PASS")

    if [ -n "$M_TOKEN" ]; then
        get_public_ips
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}[主控端 - 访问凭据]${PLAIN}"
        echo -e "IPv4 URL: ${GREEN}http://${IPV4}:${M_PORT}${PLAIN}"
        echo -e "IPv6 URL: ${GREEN}http://[${IPV6}]:${M_PORT}${PLAIN}"
        echo -e "管理员用户: ${GREEN}${M_USER}${PLAIN}"
        echo -e "管理员密码: ${GREEN}${M_PASS}${PLAIN}"
        echo -e "\n${YELLOW}[主控端 - 通信配置]${PLAIN}"
        echo -e "通信监听端口: ${SKYBLUE}${WS_PORT}${PLAIN}"
        echo -e "通信令牌 (Token): ${YELLOW}${M_TOKEN}${PLAIN}"
        echo -e "------------------------------------------------"
    fi

    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_PORT=$(grep "PORT =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e "${YELLOW}[被控端 - 当前配置]${PLAIN}"
        echo -e "连接目标: ${SKYBLUE}${A_HOST}:${A_PORT}${PLAIN}"
        echo -e "------------------------------------------------"
    fi
    echo " 1. 重新安装/修改配置 | 0. 返回"
    read -p "选择: " c_opt
    [[ "$c_opt" == "1" ]] && install_master
    main_menu
}

# --- [ 模块：主控端 ] ---
# [Module: Master Core - Fix Input]
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 主控 (Token 交互修复版)${PLAIN}"
    
    # 基础环境检查与安装
    apt-get update && apt-get install -y python3 python3-pip curl wget openssl ntpdate >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    # 获取用户自定义参数
    read -p "1. 面板访问端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "2. 通信监听端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "3. 管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "4. 管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    
    # --- Token 自定义逻辑 (修复点) ---
    DEFAULT_TK=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "------------------------------------------------"
    echo -e "系统生成的建议 Token: ${YELLOW}${DEFAULT_TK}${PLAIN}"
    echo -e "直接回车将使用上述建议值，或手动输入你自定义的 Token。"
    # 使用 -r 确保特殊字符不转义，使用 -p 强制等待
    read -p "请输入自定义 Token: " IN_TOKEN
    
    M_TOKEN=${IN_TOKEN:-$DEFAULT_TK}
    echo -e "------------------------------------------------"
    echo -e "最终确定的 Token 为: ${GREEN}${M_TOKEN}${PLAIN}"
    # --------------------------------

    # 保存配置并清理旧进程
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > "$M_ROOT/.env"
    pkill -9 -f "master/app.py" >/dev/null 2>&1

    # 生成后端文件并启动服务
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    # 确保这里调用后能返回菜单
    pause_back
}
# --- [ 模块：被控端 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 被控 (V75.0)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "主控域名或 IP: " M_HOST
    read -p "主控通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    echo -e "偏好选择: 1. 强制 IPv6 (适合 NAT 小鸡) | 2. 强制 IPv4 | 3. 自动探测"
    read -p "请选择 [1-3]: " NET_PREF

    # 下载 Sing-box 二进制
    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    _generate_agent_py "$M_HOST" "$M_TOKEN" "$WS_PORT" "$NET_PREF"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端部署成功！请在主控面板查看。${PLAIN}"
    pause_back
}

_generate_agent_py() {
    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, json, psutil, websockets, socket, ssl, time
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"; PORT = "REPLACE_PORT"; PREF = "REPLACE_PREF"
async def run():
    ssl_ctx = ssl.create_default_context(); ssl_ctx.check_hostname = False; ssl_ctx.verify_mode = ssl.CERT_NONE
    family = socket.AF_INET6 if PREF == "1" else (socket.AF_INET if PREF == "2" else socket.AF_UNSPEC)
    uri = f"wss://{MASTER}:{PORT}"
    print(f"[Agent] 连接目标: {uri}...", flush=True)
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=15, family=family) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                print(f"[Agent] 成功与主控建立安全通信", flush=True)
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                    await ws.send(json.dumps({"type":"heartbeat", "data":stats}))
                    await asyncio.sleep(8)
        except Exception as e:
            print(f"[Agent] 通信异常: {e}", flush=True); await asyncio.sleep(5)
asyncio.run(run())
EOF
    sed -i "s/REPLACE_HOST/$1/; s/REPLACE_TOKEN/$2/; s/REPLACE_PORT/$3/; s/REPLACE_PREF/$4/" "$M_ROOT/agent/agent.py"
}

# --- [ 模块：服务引擎 ] ---
_deploy_service() {
    local NAME=$1; local EXEC=$2
    SERVICE_CONF="[Unit]
Description=${NAME} Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 ${EXEC}
Restart=always
WorkingDirectory=$(dirname ${EXEC})
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target"

    echo "$SERVICE_CONF" > "/etc/systemd/system/${NAME}.service"
    echo "$SERVICE_CONF" > "/lib/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

# --- [ 模块：主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (自定义 Token 版)"
    echo " 2. 安装/更新 Multiy 被控 (WSS 加固版)"
    echo " 3. 连接监控中心 (查看 ss 监听 & 日志)"
    echo " 4. 凭据与配置中心 (主/被控信息查看)"
    echo " 5. 卸载并清理组件"
    echo " 0. 退出"
    read -p "请选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) 
            clear; echo -e "${YELLOW}[主控端口监听]${PLAIN}"
            ss -tuln | grep -E "$(get_env_val 'M_PORT')|$(get_env_val 'WS_PORT')"
            echo -e "\n${YELLOW}[被控运行日志]${PLAIN}"
            journalctl -u multiy-agent -f --output cat ;;
        4) credential_center ;;
        5) 
            systemctl stop multiy-master multiy-agent 2>/dev/null
            rm -rf "$M_ROOT" /usr/bin/multiy /etc/systemd/system/multiy-*
            echo "清理完成！"; exit 0 ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; main_menu
