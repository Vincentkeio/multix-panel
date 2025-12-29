#!/bin/bash
# Multiy Pro V85.5 - 工业级 Socket.io 重构版 (高兼容/防死锁)

export M_ROOT="/opt/multiy_mvp"
SH_VER="V85.5"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 凭据与配置中心 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    V6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 全方位凭据看板"
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
    ss -tuln | grep -q ":9339" && echo -e " 🔹 9339 隧道: ${GREEN}● 正在监听 (Socket.io模式)${PLAIN}" || echo -e " 🔹 9339 隧道: ${RED}○ 未监听到 (请手动检查报错)${PLAIN}"
    ss -tuln | grep -q ":$M_PORT" && echo -e " 🔹 $M_PORT 面板: ${GREEN}● 正在监听 (Flask)${PLAIN}" || echo -e " 🔹 $M_PORT 面板: ${RED}○ 未监听到${PLAIN}"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 2. 主控安装 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 工业级主控 (V85.5)${PLAIN}"
    
    echo -e "${YELLOW}正在强力修复 Python 依赖环境...${PLAIN}"
    pkill -9 -f "app.py" 2>/dev/null
    apt-get update && apt-get install -y python3 python3-pip openssl curl >/dev/null 2>&1
    # 强制安装最新兼容版本
    pip3 install --upgrade pip --break-system-packages >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "python-socketio" "eventlet==0.33.3" "psutil" --break-system-packages --user >/dev/null 2>&1

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
    
    # 防火墙本地放行
    if command -v ufw >/dev/null; then ufw allow 9339/tcp; ufw allow "$M_PORT"/tcp; ufw reload; fi
    
    echo -e "${GREEN}✅ 主控动作已执行完毕，请进入看板检查监听状态。${PLAIN}"
    pause_back
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import socketio, eventlet, os, json, ssl, time, psutil
from flask import Flask, render_template_string, session, redirect, request, jsonify
from threading import Thread

# 强力加载环境变量
def load_env():
    c = {}
    path = '/opt/multiy_mvp/.env'
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

conf = load_env()
sio = socketio.Server(cors_allowed_origins='*', async_mode='eventlet')
app = Flask(__name__)
app.wsgi_app = socketio.WSGIApp(sio, app.wsgi_app)
AGENTS = {}

@sio.on('auth')
def authenticate(sid, data):
    env = load_env()
    if data.get('token') == env.get('M_TOKEN'):
        AGENTS[sid] = {"alias": data.get('hostname', 'Node'), "stats": {"cpu":0,"mem":0}, "last_seen": time.time(), "ip": request.remote_addr}
        sio.emit('ready', {'msg': 'verified'}, room=sid)
        return True
    return False

@sio.on('heartbeat')
def handle_heartbeat(sid, data):
    if sid in AGENTS:
        AGENTS[sid]['stats'] = data; AGENTS[sid]['last_seen'] = time.time()

@app.route('/api/state')
def api_state():
    return jsonify({"master_token": load_env().get('M_TOKEN'), "agents": AGENTS})

@app.route('/login', methods=['GET', 'POST'])
def login():
    env = load_env()
    app.secret_key = env.get('M_TOKEN')
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return "<body><form method='post'><input name='u' placeholder='Admin'><br><input name='p' type='password' placeholder='Pass'><br><button>LOGIN</button></form></body>"

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return "<h1>Multiy Pro V85.5 Panel Running</h1>"

def run_server():
    env = load_env()
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain('/opt/multiy_mvp/master/cert.pem', '/opt/multiy_mvp/master/key.pem')
    # 强制监听
    eventlet.wsgi.server(eventlet.wrap_ssl(eventlet.listen(('0.0.0.0', 9339)), 
                         certfile='/opt/multiy_mvp/master/cert.pem', 
                         keyfile='/opt/multiy_mvp/master/key.pem', 
                         server_side=True), app)

if __name__ == '__main__':
    run_server()
EOF
}

# --- [ 3. 服务引擎 ] ---
_deploy_service() {
    local NAME=$1; local EXEC=$2
    BODY="[Unit]\nDescription=${NAME}\nAfter=network.target\n[Service]\nExecStart=/usr/bin/python3 ${EXEC}\nRestart=always\nWorkingDirectory=$(dirname ${EXEC})\nEnvironment=PYTHONUNBUFFERED=1\n[Install]\nWantedBy=multi-user.target"
    echo -e "$BODY" > "/etc/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

# --- [ 4. 被控安装 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 安装 Multiy 被控 (SSL 豁免模式)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名或 IP: " M_HOST
    read -p "2. 主控 Token: " M_TOKEN
    
    pip3 install "python-socketio[client]" "psutil" --break-system-packages --user >/dev/null 2>&1

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import socketio, time, psutil, socket, ssl
sio = socketio.Client(ssl_verify=False)
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"

@sio.event
def connect():
    sio.emit('auth', {'token': TOKEN, 'hostname': socket.gethostname()})

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
        except Exception: time.sleep(5)
EOF
    sed -i "s/REPLACE_HOST/$M_HOST/; s/REPLACE_TOKEN/$M_TOKEN/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控已启动。${PLAIN}"; pause_back
}

# --- [ 5. 诊断与清理 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 智能链路诊断中心${PLAIN}"
    [ ! -f "$M_ROOT/agent/agent.py" ] && echo "未安装被控" && pause_back && return
    A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    echo -e "目标地址: ${SKYBLUE}$A_HOST:9339${PLAIN}"
    if curl -sk --max-time 3 "https://$A_HOST:9339" >/dev/null 2>&1 || [ $? -eq 52 ]; then
        echo -e "👉 隧道检测: ${GREEN}成功 (9339 响应 WSS)${PLAIN}"
    else
        echo -e "👉 隧道检测: ${RED}失败 (端口不可达)${PLAIN}"
    fi
    pause_back
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (强制 9339 启动版)"
    echo " 2. 安装/更新 Multiy 被控"
    echo " 3. 智能链路诊断中心"
    echo " 4. 凭据与配置中心 (实时看板)"
    echo " 5. 深度清理中心"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;;
        4) credential_center ;; 5) 
            systemctl stop multiy-master multiy-agent 2>/dev/null; rm -rf "$M_ROOT" /etc/systemd/system/multiy-* /usr/bin/multiy
            echo "环境已重置。"; exit 0 ;;
        *) exit 0 ;;
    esac
}

check_root; install_shortcut; main_menu
