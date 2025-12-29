#!/bin/bash
# Multiy Pro V115.0 - 终极全功能旗舰版 (交互增强/功能无删减)

export M_ROOT="/opt/multiy_mvp"
SH_VER="V115.0-FINAL"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 凭据中心看板 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "未分配")
    V6=$(curl -s6m 3 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰凭据看板"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 管理入口 (WEB) ]${PLAIN}"
    echo -e " 🔹 IPv4: http://$V4:$M_PORT"
    [ "$V6" != "未分配" ] && echo -e " 🔹 IPv6: http://[$V6]:$M_PORT"
    echo -e " 🔹 管理员: ${YELLOW}$M_USER${PLAIN} / 密码: ${YELLOW}$M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. 被控接入 (WSS) ]${PLAIN}"
    echo -e " 🔹 通信域名: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 接入端口: ${SKYBLUE}9339${PLAIN}"
    echo -e " 🔹 校验令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 物理监听状态 ]${PLAIN}"
    check_v4v6() { ss -tuln | grep -q ":$1 " && echo -e "${GREEN}● OK${PLAIN}" || echo -e "${RED}○ OFF${PLAIN}"; }
    echo -e " 🔹 Web 端口 ($M_PORT): $(check_v4v6 $M_PORT)"
    echo -e " 🔹 WSS 端口 (9339): $(check_v4v6 9339)"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 2. 主控安装 (交互增强版) ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (V115.0)${PLAIN}"
    pkill -9 -f "app.py" 2>/dev/null
    
    # 环境校准
    apt-get update && apt-get install -y python3 python3-pip openssl curl lsof net-tools >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "python-socketio" "eventlet==0.33.3" "psutil" --break-system-packages --user >/dev/null 2>&1

    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    echo -e "\n${YELLOW}--- 交互式设置 (按回车可使用默认值) ---${PLAIN}"
    read -p "1. 面板 Web 端口 [默认 7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "2. 管理员账号 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "3. 管理员密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    
    TK_RAND=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    echo -e "4. 通信 Token (Agent 接入凭据)"
    read -p "   请输入 Token [回车使用: $TK_RAND]: " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}
    M_HOST="multix.spacelite.top"

    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF
    
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 部署完成。${PLAIN}"; sleep 2; credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import socketio, eventlet, os, json, ssl, time, socket, subprocess
from flask import Flask, render_template_string, session, redirect, request, jsonify
from threading import Thread

def load_env():
    c = {}
    path = '/opt/multiy_mvp/.env'
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            for l in f:
                if '=' in l: k, v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

sio = socketio.Server(cors_allowed_origins='*', async_mode='eventlet', ping_timeout=45)
app = Flask(__name__)
app.wsgi_app = socketio.WSGIApp(sio, app.wsgi_app)
AGENTS = {}

@sio.on('auth')
def authenticate(sid, data):
    env = load_env()
    if data.get('token') == env.get('M_TOKEN'):
        AGENTS[sid] = {"alias": data.get('hostname', 'Node'), "stats": {"cpu":0,"mem":0}, "last_seen": time.time(), "ip": request.remote_addr, "connected_at": time.strftime("%H:%M:%S")}
        sio.emit('ready', {'msg': 'verified'}, room=sid)
        sio.emit('update_ui', AGENTS)
        return True
    return False

@sio.on('heartbeat')
def handle_heartbeat(sid, data):
    if sid in AGENTS:
        AGENTS[sid]['stats'] = data; AGENTS[sid]['last_seen'] = time.time()
        sio.emit('update_ui', AGENTS)

@sio.on('disconnect')
def disconnect(sid):
    if sid in AGENTS: del AGENTS[sid]; sio.emit('update_ui', AGENTS)

@app.route('/api/state')
def api_state(): return jsonify({"agents": AGENTS})

@app.route('/api/info')
def api_info():
    env = load_env()
    ip4 = subprocess.getoutput("curl -s4m 2 api.ipify.org || echo 'N/A'")
    ip6 = subprocess.getoutput("curl -s6m 2 api64.ipify.org || echo 'N/A'")
    return jsonify({"token": env.get('M_TOKEN'), "ip4": ip4, "ip6": ip6, "m_port": env.get('M_PORT')})

# --- [ UI 旗舰增强版 ] ---
INDEX_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Multiy Pro Dashboard</title>
<script src="https://cdn.tailwindcss.com"></script>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
<style>
    body{background:#020617;color:#fff;font-family:ui-sans-serif,system-ui;overflow-x:hidden}
    .glass{background:rgba(255,255,255,0.01);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.08);border-radius:2rem}
    .top-badge{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.05);padding:8px 16px;border-radius:12px;font-size:10px;font-weight:900}
</style></head>
<body class="p-6 md:p-12" x-data="panel()" x-init="init()">
    <div class="max-w-7xl mx-auto">
        <div class="flex flex-wrap gap-4 mb-10">
            <div class="top-badge uppercase">Token: <span class="text-blue-400" x-text="sys.token"></span></div>
            <div class="top-badge uppercase">V4: <span class="text-blue-400" x-text="sys.ip4 + ':' + sys.m_port"></span></div>
            <div class="top-badge uppercase">V6: <span class="text-blue-400" x-text="'['+sys.ip6+']:' + sys.m_port"></span></div>
        </div>
        <header class="flex justify-between items-end mb-16">
            <h1 class="text-6xl font-black italic tracking-tighter text-blue-600">MULTIY <span class="text-white">PRO</span></h1>
            <div class="bg-green-500/10 text-green-500 px-4 py-1 rounded-full text-[10px] font-black border border-green-500/20">WSS TUNNEL ACTIVE</div>
        </header>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div class="glass p-10 border-blue-500/20 bg-blue-500/5">
                <h2 class="text-2xl font-black text-blue-400 uppercase tracking-tighter">Demo Node</h2>
                <div class="mt-6 text-slate-500 text-[10px] uppercase font-black tracking-widest">Permanent Simulation</div>
            </div>
            <template x-for="(node, sid) in agents" :key="sid">
                <div class="glass p-10 hover:border-blue-500/50 transition-all">
                    <div class="flex justify-between mb-8">
                        <div><h2 class="text-2xl font-black" x-text="node.alias"></h2><code class="text-blue-400 text-xs" x-text="node.ip"></code></div>
                    </div>
                    <div class="space-y-4">
                        <div class="flex justify-between text-[10px] font-black uppercase"><span class="text-slate-500">CPU</span><span x-text="node.stats.cpu+'%'"></span></div>
                        <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-blue-500 transition-all" :style="'width:'+node.stats.cpu+'%'"></div></div>
                    </div>
                </div>
            </template>
        </div>
    </div>
    <script>
        function panel(){ return { agents:{}, sys:{}, init(){
            this.socket = io({ transports: ['websocket'] });
            this.socket.on('update_ui', (data) => { this.agents = data; });
            this.fetch();
        }, async fetch(){
            try{ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents;
                 const i=await fetch('/api/info'); const si=await i.json(); this.sys=si; }catch(e){}
        }}}
    </script>
</body></html>
"""

# --- [ 登录页极简美化 ] ---
HTML_LOGIN = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script></head>
<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif">
<form method="post" style="background:rgba(255,255,255,0.02);backdrop-filter:blur(30px);padding:60px;border-radius:40px;border:1px solid rgba(255,255,255,0.1);width:360px;text-align:center;box-shadow:0 0 50px rgba(59,130,246,0.15)">
    <h2 style="color:#3b82f6;font-size:2.5rem;font-weight:900;margin-bottom:40px;font-style:italic;letter-spacing:-2px;text-transform:uppercase">Multiy <span style="color:#fff">Pro</span></h2>
    <input name="u" placeholder="Username" style="width:100%;padding:18px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:18px;outline:none">
    <input name="p" type="password" placeholder="Password" style="width:100%;padding:18px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:18px;outline:none">
    <button style="width:100%;padding:18px;background:#3b82f6;color:#fff;border:none;border-radius:18px;font-weight:900;cursor:pointer;margin-top:25px;text-transform:uppercase;box-shadow:0 10px 20px rgba(59,130,246,0.3)">Access Terminal</button>
</form></body></html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    env = load_env(); app.secret_key = env.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return render_template_string(HTML_LOGIN)

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

def run_wss():
    try:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        sock.bind(('::', 9339))
        sock.listen(128)
        eventlet.wsgi.server(eventlet.wrap_ssl(sock, certfile='cert.pem', keyfile='key.pem', server_side=True), app)
    except:
        eventlet.wsgi.server(eventlet.wrap_ssl(eventlet.listen(('0.0.0.0', 9339)), certfile='cert.pem', keyfile='key.pem', server_side=True), app)

if __name__ == '__main__':
    Thread(target=run_wss, daemon=True).start()
    env = load_env()
    app.run(host='::', port=int(env.get('M_PORT', 7575)))
EOF
}

# --- [ 3. 被控安装逻辑 (修复) ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 安装 Multiy 被控 (V115.0)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名/IP: " M_HOST
    read -p "2. 通信令牌 (Token): " M_TOKEN
    
    # 环境依赖强制安装
    pip3 install "python-socketio[client]" "psutil" --break-system-packages --user >/dev/null 2>&1

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import socketio, time, psutil, socket, ssl
sio = socketio.Client(ssl_verify=False)
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"
@sio.event
def connect(): sio.emit('auth', {'token': TOKEN, 'hostname': socket.gethostname()})
def send_heartbeat():
    while True:
        if sio.connected:
            stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
            sio.emit('heartbeat', stats)
        time.sleep(8)
if __name__ == "__main__":
    while True:
        try: sio.connect(f"https://{MASTER}:9339"); send_heartbeat()
        except: time.sleep(5)
EOF
    sed -i "s/REPLACE_HOST/$M_HOST/; s/REPLACE_TOKEN/$M_TOKEN/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端已启动。${PLAIN}"; pause_back
}

# --- [ 4. 增强诊断中心 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 智能链路诊断中心 (修复版)${PLAIN}"
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_TOKEN=$(grep "TOKEN =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e "${GREEN}[ 诊断参数 ]${PLAIN}"
        echo -e " 🔹 目标地址: ${SKYBLUE}$A_HOST:9339${PLAIN}"
        echo -e " 🔹 使用凭据: ${YELLOW}$A_TOKEN${PLAIN}"
        
        echo -e "\n${GREEN}[ 连通性测试 ]${PLAIN}"
        if curl -sk --max-time 5 "https://$A_HOST:9339" >/dev/null 2>&1 || [ $? -eq 52 ]; then
            echo -e " 👉 隧道状态: ${GREEN}成功 (WSS 响应正常)${PLAIN}"
        else
            echo -e " 👉 隧道状态: ${RED}失败 (请检查主控防火墙与 9339 端口)${PLAIN}"
        fi
    else
        echo -e "${RED}[错误]${PLAIN} 未发现被控端安装记录。"
    fi
    pause_back
}

_deploy_service() {
    local NAME=$1; local EXEC=$2
    cat > "/etc/systemd/system/${NAME}.service" << EOF
[Unit]
Description=${NAME}
After=network.target
[Service]
ExecStart=/usr/bin/python3 ${EXEC}
Restart=always
WorkingDirectory=$(dirname ${EXEC})
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/物理修复主控 (双栈强制自愈版)"
    echo " 2. 安装/更新被控 (自动双栈适配)"
    echo " 3. 智能链路诊断中心 (凭据核验版)"
    echo " 4. 凭据与配置看板 (精准存活状态)"
    echo " 5. 深度清理中心 (彻底物理抹除)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;; 4) credential_center ;; 5) 
        systemctl stop multiy-master multiy-agent 2>/dev/null; pkill -9 -f "app.py"
        rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "清理完成"; exit ;; 0) exit ;; esac
}

check_root; install_shortcut; main_menu
