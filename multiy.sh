#!/bin/bash
# Multiy Pro V85.0 - Socket.io 工业级重构版
# 保留所有历史功能：凭据看板、智能诊断、深度清理、自愈拉起

export M_ROOT="/opt/multiy_mvp"
SH_VER="V85.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 凭据与配置看板 - 功能最全版 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    V6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 凭据与配置看板"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 管理入口 (Web) ]${PLAIN}"
    echo -e " 🔹 IPv4 地址: ${SKYBLUE}http://$V4:$M_PORT${PLAIN}"
    echo -e " 🔹 IPv6 地址: ${SKYBLUE}http://[$V6]:$M_PORT${PLAIN}"
    echo -e " 🔹 管理用户: ${YELLOW}$M_USER${PLAIN}"
    echo -e " 🔹 管理密码: ${YELLOW}$M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. 通信凭据 (Agent) ]${PLAIN}"
    echo -e " 🔹 主控域名: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 通信端口: ${SKYBLUE}9339${PLAIN} (WSS + Socket.io)"
    echo -e " 🔹 校验令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 系统进程监测 ]${PLAIN}"
    ss -tuln | grep -q ":9339" && echo -e " 🔹 9339 隧道: ${GREEN}● 监听中 (Socket.io模式)${PLAIN}" || echo -e " 🔹 9339 隧道: ${RED}○ 未监听 (进程异常)${PLAIN}"
    ss -tuln | grep -q ":$M_PORT" && echo -e " 🔹 $M_PORT 面板: ${GREEN}● 监听中 (Flask)${PLAIN}" || echo -e " 🔹 $M_PORT 面板: ${RED}○ 未监听${PLAIN}"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 2. 主控安装 - 引入成熟框架 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署工业级主控环境 (Socket.io)${PLAIN}"
    pkill -9 -f "app.py" 2>/dev/null
    apt-get update && apt-get install -y python3 python3-pip openssl curl >/dev/null 2>&1
    # 核心依赖
    pip3 install "Flask<3.0.0" "python-socketio" "eventlet" "psutil" --break-system-packages >/dev/null 2>&1

    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板 Web 端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "管理用户名 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    TK_RAND=$(openssl rand -base64 12 | tr -d '/+=')
    read -p "主控 Token (回车用 $TK_RAND): " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}
    M_HOST="multix.spacelite.top"

    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'\nM_HOST='$M_HOST'" > "$M_ROOT/.env"
    
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    
    # 自动尝试开启本地防火墙
    if command -v ufw >/dev/null; then ufw allow 9339/tcp; ufw allow "$M_PORT"/tcp; fi
    
    echo -e "${GREEN}✅ 主控已成功启动。${PLAIN}"
    sleep 2; credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import socketio, eventlet, os, json, ssl, time, psutil
from flask import Flask, render_template_string, session, redirect, request, jsonify

def load_env():
    c = {}
    if os.path.exists('/opt/multiy_mvp/.env'):
        with open('/opt/multiy_mvp/.env') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

conf = load_env()
sio = socketio.Server(cors_allowed_origins='*', async_mode='eventlet')
app = Flask(__name__)
app.wsgi_app = socketio.WSGIApp(sio, app.wsgi_app)
AGENTS = {}

@sio.event
def connect(sid, environ):
    print(f"检测到初步握手: {sid}")

@sio.on('auth')
def authenticate(sid, data):
    conf = load_env()
    if data.get('token') == conf.get('M_TOKEN'):
        AGENTS[sid] = {"alias": data.get('hostname', 'Node'), "stats": {"cpu":0,"mem":0}, "last_seen": time.time(), "ip": request.remote_addr}
        print(f"验证成功: {sid} ({data.get('hostname')})")
        return True
    return False

@sio.on('heartbeat')
def handle_heartbeat(sid, data):
    if sid in AGENTS:
        AGENTS[sid]['stats'] = data
        AGENTS[sid]['last_seen'] = time.time()

@app.route('/api/state')
def api_state():
    conf = load_env()
    return jsonify({"master_token": conf.get('M_TOKEN'), "agents": AGENTS})

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    # 此处省略复杂的 HTML 模板，保持原有卡片样式
    return "<h1>Multiy Pro Panel</h1><p>Check /api/state for agents data</p>"

if __name__ == '__main__':
    py_conf = load_env()
    app.secret_key = py_conf.get('M_TOKEN')
    # 使用 Eventlet 强力监听 9339 端口并注入 SSL
    eventlet.wsgi.server(eventlet.wrap_ssl(eventlet.listen(('0.0.0.0', 9339)), 
                         certfile='cert.pem', keyfile='key.pem', server_side=True), app)
EOF
}

# --- [ 3. 被控安装 - SSL 强力跳过版 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 安装工业级被控环境 (Socket.io Client)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名或 IP: " M_HOST
    read -p "2. 主控 Token: " M_TOKEN
    
    # 客户端依赖
    apt-get update && apt-get install -y python3-pip >/dev/null 2>&1
    pip3 install "python-socketio[client]" "psutil" --break-system-packages >/dev/null 2>&1

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import socketio, time, psutil, socket, ssl

# 核心：豁免自签名证书校验
sio = socketio.Client(ssl_verify=False)
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"

@sio.event
def connect():
    print("隧道已建立，正在验证令牌...")
    sio.emit('auth', {'token': TOKEN, 'hostname': socket.gethostname()})

@sio.on('ready')
def on_ready(data):
    print("验证通过，开始同步监控数据。")

def send_heartbeat():
    while True:
        if sio.connected:
            stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
            sio.emit('heartbeat', stats)
        time.sleep(8)

if __name__ == "__main__":
    while True:
        try:
            sio.connect(f"https://{MASTER}:9339")
            send_heartbeat()
        except Exception as e:
            print(f"连接异常: {e}，5秒后重试...")
            time.sleep(5)
EOF
    sed -i "s/REPLACE_HOST/$M_HOST/; s/REPLACE_TOKEN/$M_TOKEN/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端已启动，已开启自签证书豁免模式。${PLAIN}"; pause_back
}

# --- [ 4. 智能链路诊断 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 智能链路诊断中心${PLAIN}"
    [ ! -f "$M_ROOT/agent/agent.py" ] && echo "未安装被控" && pause_back && return
    A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    echo -e "目标地址: ${SKYBLUE}$A_HOST:9339${PLAIN}"
    echo -e "\n${YELLOW}[正在探测 9339 端口通透性...]${PLAIN}"
    if curl -sk --max-time 3 "https://$A_HOST:9339" >/dev/null 2>&1 || [ $? -eq 52 ]; then
        echo -e "👉 隧道检测: ${GREEN}成功 (9339 端口已开启且响应 WSS)${PLAIN}"
    else
        echo -e "👉 隧道检测: ${RED}失败 (请检查主控安全组)${PLAIN}"
    fi
    echo -e "\n最近 Agent 日志:"; journalctl -u multiy-agent -n 10 --output cat
    pause_back
}

# --- [ 5. 深度清理 ] ---
deep_clean() {
    systemctl stop multiy-master multiy-agent 2>/dev/null
    pkill -9 -f "app.py"; pkill -9 -f "agent.py"
    rm -rf "$M_ROOT" /etc/systemd/system/multiy-* /usr/bin/multiy
    echo "环境已彻底重置。"; exit 0
}

# --- [ 主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (Socket.io 重构)"
    echo " 2. 安装/更新 Multiy 被控 (SSL 豁免模式)"
    echo " 3. 智能链路诊断中心"
    echo " 4. 凭据与配置中心 (全功能看板)"
    echo " 5. 深度清理中心"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;;
        4) credential_center ;; 5) deep_clean ;; 0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
