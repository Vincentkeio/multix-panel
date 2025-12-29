#!/bin/bash
# Multiy Pro V88.0 - 工业级全功能美化版

export M_ROOT="/opt/multiy_mvp"
SH_VER="V88.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }

# --- [ 1. 凭据中心看板 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}未检测到主控凭据${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    V6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 全方位凭据看板"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 管理入口 (WEB) ]${PLAIN}"
    echo -e " 🔹 IPv4 访问: ${SKYBLUE}http://$V4:$M_PORT${PLAIN}"
    echo -e " 🔹 IPv6 访问: ${SKYBLUE}http://[$V6]:$M_PORT${PLAIN}"
    echo -e " 🔹 管理用户: ${YELLOW}$M_USER${PLAIN}"
    echo -e " 🔹 管理密码: ${YELLOW}$M_PASS${PLAIN}"
    echo -e "\n${GREEN}[ 2. 被控通信凭据 (AGENT) ]${PLAIN}"
    echo -e " 🔹 主控域名: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 通信端口: ${SKYBLUE}9339${PLAIN} (WSS + Socket.io)"
    echo -e " 🔹 校验令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    echo -e "\n${GREEN}[ 3. 系统运行状态 ]${PLAIN}"
    ss -tuln | grep -q ":9339" && echo -e " 🔹 9339 隧道: ${GREEN}● 监听中${PLAIN}" || echo -e " 🔹 9339 隧道: ${RED}○ 未监听到${PLAIN}"
    ss -tuln | grep -q ":$M_PORT" && echo -e " 🔹 $M_PORT 面板: ${GREEN}● 监听中${PLAIN}" || echo -e " 🔹 $M_PORT 面板: ${RED}○ 未监听到${PLAIN}"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "按任意键返回主菜单..." && read -n 1 -s -r; main_menu
}

# --- [ 2. 主控安装逻辑 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 工业级主控 (V88.0)${PLAIN}"
    pkill -9 -f "app.py" 2>/dev/null
    
    # 环境依赖校准
    apt-get update && apt-get install -y python3 python3-pip openssl curl >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "python-socketio" "eventlet==0.33.3" "psutil" "cryptography==38.0.4" "pyOpenSSL==22.1.0" --break-system-packages --user >/dev/null 2>&1

    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板 Web 端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "管理用户名 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    TK_RAND=$(openssl rand -base64 12 | tr -d '/+=')
    read -p "通信 Token (回车用 $TK_RAND): " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}
    M_HOST="multix.spacelite.top"

    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'\nM_HOST='$M_HOST'" > "$M_ROOT/.env"
    
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    
    # 物理放行端口
    if command -v ufw >/dev/null; then ufw allow 9339/tcp; ufw allow "$M_PORT"/tcp; ufw reload; fi
    
    echo -e "${GREEN}✅ 主控已拉起，正在跳转凭据中心看板...${PLAIN}"
    sleep 2; credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import socketio, eventlet, os, json, ssl, time, psutil
from flask import Flask, render_template_string, session, redirect, request, jsonify
from threading import Thread

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
        AGENTS[sid] = {
            "alias": data.get('hostname', 'Node'),
            "stats": {"cpu":0,"mem":0},
            "last_seen": time.time(),
            "ip": request.remote_addr,
            "connected_at": time.strftime("%Y-%m-%d %H:%M:%S")
        }
        sio.emit('ready', {'msg': 'verified'}, room=sid)
        return True
    return False

@sio.on('heartbeat')
def handle_heartbeat(sid, data):
    if sid in AGENTS:
        AGENTS[sid]['stats'] = data
        AGENTS[sid]['last_seen'] = time.time()

@sio.on('disconnect')
def disconnect(sid):
    if sid in AGENTS: del AGENTS[sid]

@app.route('/api/state')
def api_state():
    return jsonify({"agents": AGENTS})

# --- [ 全功能美化前端 ] ---
HTML_INDEX = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Multiy Pro Dashboard</title>
<script src="https://cdn.tailwindcss.com"></script>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<style>
    body{background:#0a0f1d;color:#e2e8f0;font-family:'Inter',sans-serif}
    .glass{background:rgba(255,255,255,0.03);backdrop-filter:blur(12px);border:1px solid rgba(255,255,255,0.08);border-radius:24px}
    .status-pulse{animation:pulse 2s infinite}@keyframes pulse{0%{opacity:1}50%{opacity:0.4}100%{opacity:1}}
</style>
</head>
<body class="p-4 md:p-10" x-data="panel()" x-init="start()">
    <div class="max-w-7xl mx-auto">
        <header class="flex justify-between items-center mb-12">
            <div>
                <h1 class="text-4xl font-black italic tracking-tighter text-blue-500">MULTIY <span class="text-white">PRO</span></h1>
                <p class="text-slate-500 text-sm font-bold uppercase mt-1">Global Node Infrastructure</p>
            </div>
            <div class="flex gap-4">
                <div class="glass px-6 py-2 text-xs font-mono"><span class="text-slate-500">NODES:</span> <span class="text-blue-400" x-text="Object.keys(agents).length"></span></div>
                <a href="/logout" class="bg-red-500/10 border border-red-500/20 text-red-500 px-6 py-2 rounded-full text-xs font-bold hover:bg-red-500 hover:text-white transition">LOGOUT</a>
            </div>
        </header>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <template x-for="(node, sid) in agents" :key="sid">
                <div class="glass p-8 hover:border-blue-500/50 transition-all group">
                    <div class="flex justify-between items-start mb-6">
                        <div>
                            <h3 class="text-xl font-bold group-hover:text-blue-400 transition" x-text="node.alias"></h3>
                            <code class="text-[10px] text-slate-600 font-bold" x-text="node.ip"></code>
                        </div>
                        <div class="bg-green-500/20 p-1 rounded-full status-pulse"><div class="w-2 h-2 bg-green-500 rounded-full"></div></div>
                    </div>
                    
                    <div class="space-y-4">
                        <div>
                            <div class="flex justify-between text-[10px] font-bold uppercase mb-1"><span class="text-slate-500">CPU Usage</span><span x-text="node.stats.cpu+'%'"></span></div>
                            <div class="h-1.5 w-full bg-slate-800 rounded-full overflow-hidden"><div class="h-full bg-blue-500 transition-all duration-500" :style="'width:'+node.stats.cpu+'%'"></div></div>
                        </div>
                        <div>
                            <div class="flex justify-between text-[10px] font-bold uppercase mb-1"><span class="text-slate-500">Memory</span><span x-text="node.stats.mem+'%'"></span></div>
                            <div class="h-1.5 w-full bg-slate-800 rounded-full overflow-hidden"><div class="h-full bg-purple-500 transition-all duration-500" :style="'width:'+node.stats.mem+'%'"></div></div>
                        </div>
                    </div>
                    
                    <div class="mt-8 pt-6 border-t border-white/5 flex justify-between items-center text-[9px] font-bold text-slate-500 uppercase tracking-widest">
                        <span x-text="'SINCE: ' + node.connected_at"></span>
                        <span class="text-blue-400">ACTIVE</span>
                    </div>
                </div>
            </template>
        </div>
    </div>
    <script>
        function panel(){ return { agents:{}, start(){this.fetch();setInterval(()=>this.fetch(),3000)}, async fetch(){ try{const r=await fetch('/api/state');const d=await r.json();this.agents=d.agents}catch(e){} } } }
    </script>
</body></html>
"""

HTML_LOGIN = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-[#020617] h-screen flex items-center justify-center font-sans">
    <form method="post" class="bg-white/5 p-12 rounded-[2rem] border border-white/10 backdrop-blur-xl w-full max-w-md shadow-2xl">
        <div class="text-center mb-10">
            <h2 class="text-3xl font-black italic text-blue-500 uppercase tracking-tighter">Multiy <span class="text-white">Login</span></h2>
            <p class="text-slate-500 text-xs font-bold mt-2 uppercase tracking-widest">Central Command Center</p>
        </div>
        <input name="u" placeholder="Username" class="w-full bg-black/50 border border-white/10 p-4 rounded-2xl mb-4 text-white outline-none focus:border-blue-500 transition">
        <input name="p" type="password" placeholder="Password" class="w-full bg-black/50 border border-white/10 p-4 rounded-2xl mb-8 text-white outline-none focus:border-blue-500 transition">
        <button class="w-full bg-blue-600 hover:bg-blue-500 text-white font-black p-4 rounded-2xl transition shadow-lg shadow-blue-500/20">ACCESS SYSTEM</button>
    </form>
</body></html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    env = load_env(); app.secret_key = env.get('M_TOKEN')
    if request.method == 'POST':
        if request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
            session['logged'] = True; return redirect('/')
    return render_template_string(HTML_LOGIN)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_INDEX)

def run_wss():
    eventlet.wsgi.server(eventlet.wrap_ssl(eventlet.listen(('0.0.0.0', 9339)), 
                         certfile='cert.pem', keyfile='key.pem', server_side=True), app)

if __name__ == '__main__':
    Thread(target=run_wss, daemon=True).start()
    env = load_env()
    app.run(host='::', port=int(env.get('M_PORT', 7575)))
EOF
}

# --- [ 3. 被控安装逻辑 (SSL 豁免) ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 被控 (V88.0)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名或 IP: " M_HOST
    read -p "2. 主控 Token: " M_TOKEN
    
    pip3 install "python-socketio[client]" "psutil" --break-system-packages --user >/dev/null 2>&1

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import socketio, time, psutil, socket, ssl
# 核心：豁免自签名证书校验
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

# --- [ 4. 其它功能模块 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 智能链路诊断中心${PLAIN}"
    [ ! -f "$M_ROOT/agent/agent.py" ] && echo "未安装被控" && pause_back && return
    A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    echo -e "目标地址: ${SKYBLUE}$A_HOST:9339${PLAIN}"
    if curl -sk --max-time 3 "https://$A_HOST:9339" >/dev/null 2>&1 || [ $? -eq 52 ]; then
        echo -e "👉 隧道检测: ${GREEN}成功 (WSS 响应正常)${PLAIN}"
    else
        echo -e "👉 隧道检测: ${RED}失败 (端口不可达)${PLAIN}"
    fi
    pause_back
}

_deploy_service() {
    local NAME=$1; local EXEC=$2
    BODY="[Unit]\nDescription=${NAME}\nAfter=network.target\n[Service]\nExecStart=/usr/bin/python3 ${EXEC}\nRestart=always\nWorkingDirectory=$(dirname ${EXEC})\nEnvironment=PYTHONUNBUFFERED=1\n[Install]\nWantedBy=multi-user.target"
    echo -e "$BODY" > "/etc/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (全功能美化版)"
    echo " 2. 安装/更新 Multiy 被控 (自愈模式)"
    echo " 3. 智能链路诊断中心"
    echo " 4. 凭据与配置中心 (看板)"
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
