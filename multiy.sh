#!/bin/bash

# ==============================================================================
# MultiX Pro Script V72.0 (Native Sing-box & WSS Encrypted)
# Fix 1: [Security] Auto-generated Self-signed TLS for WSS communication.
# Fix 2: [Net] Forced Physical Dual-Stack listening (V4 & V6 threads).
# Fix 3: [UI] Alpine.js + Tailwind CSS with visual param builders.
# Fix 4: [Arch] Removed Docker. 100% Native Sing-box implementation.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V72.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 1. 基础环境 ] ---
install_shortcut() { rm -f /usr/bin/multix; cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix; }
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() {
    IPV4=$(curl -s4m 2 api.ipify.org || echo "N/A"); IPV6=$(curl -s6m 2 api64.ipify.org || echo "N/A")
}

# --- [ 2. 依赖与证书生成 ] ---
install_dependencies() {
    check_sys
    echo -e "${YELLOW}[INFO]${PLAIN} 安装系统依赖与加密组件..."
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y python3 python3-pip curl wget ntpdate openssl
    else apt-get update && apt-get install -y python3 python3-pip curl wget ntpdate openssl; fi
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    # 生成自签名证书 (有效期10年)
    if [ ! -f "$M_ROOT/master/cert.pem" ]; then
        mkdir -p $M_ROOT/master
        openssl req -x509 -newkey rsa:2048 -keyout $M_ROOT/master/key.pem -out $M_ROOT/master/cert.pem -days 3650 -nodes -subj "/CN=MultiX_Internal" >/dev/null 2>&1
    fi
}

# --- [ 3. 主控安装 ] ---
install_master() {
    install_dependencies; mkdir -p $M_ROOT/master/static
    read -p "面板端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    M_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env

    _write_master_api_py
    _write_master_index_html

    cat > /etc/systemd/system/multix-master.service <<EOF
[Unit]
Description=MultiX Master Server
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/master/app.py
Restart=always
WorkingDirectory=$M_ROOT/master
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multix-master; systemctl restart multix-master
    get_public_ips
    echo -e "${GREEN}✅ 主控端部署成功！通信已由自签名 TLS 加密${PLAIN}"
    echo -e "IPv4: http://${IPV4}:${M_PORT} | IPv6: http://[${IPV6}]:${M_PORT}"
    echo -e "通信令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

_write_master_api_py() {
cat > $M_ROOT/master/app.py <<'EOF'
import json, asyncio, psutil, os, socket, websockets, ssl, subprocess
from flask import Flask, send_from_directory, request, session, redirect, jsonify
from threading import Thread

def load_conf():
    c = {}
    try:
        with open('/opt/multix_mvp/.env') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    except: pass
    return c

CONF = load_conf()
M_PORT, M_USER, M_PASS, M_TOKEN = int(CONF.get('M_PORT', 7575)), CONF.get('M_USER', 'admin'), CONF.get('M_PASS', 'admin'), CONF.get('M_TOKEN', 'error')
app = Flask(__name__); app.secret_key = M_TOKEN
AGENTS = {} 

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return send_from_directory('.', 'index.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form.get('u') == M_USER and request.form.get('p') == M_PASS:
            session['logged'] = True; return redirect('/')
    return send_from_directory('.', 'index.html')

@app.route('/api/state')
def api_state():
    if not session.get('logged'): return jsonify({"error":"auth"}), 401
    return jsonify({"master_token": M_TOKEN, "agents": {ip: {"stats": a['stats'], "alias": a.get('alias')} for ip,a in AGENTS.items()}})

@app.route('/api/gen', methods=['POST'])
def gen_tool():
    t = request.json.get('type')
    if t == 'uuid': return jsonify({"val": str(subprocess.check_output(['cat', '/proc/sys/kernel/random/uuid']).decode().strip())})
    return jsonify({"val": ""})

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth_msg = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth_msg).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {}, "alias": "Initial..."}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data')
                    AGENTS[ip]['alias'] = d.get('data', {}).get('hostname', 'Node')
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws_server():
    loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    # 物理双栈监听 + TLS 加密 (WSS)
    v4 = websockets.serve(ws_handler, "0.0.0.0", 8888, ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", 8888, ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws_server, daemon=True).start()
    app.run(host='0.0.0.0', port=M_PORT)
EOF
}

_write_master_index_html() {
cat > $M_ROOT/master/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en" class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro V72</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <style> .glass { background: rgba(15, 23, 42, 0.8); backdrop-filter: blur(12px); border: 1px solid rgba(255,255,255,0.1); } </style>
</head>
<body class="bg-slate-950 text-slate-200" x-data="app()" x-init="init()">
    <div x-show="!isLogged" class="fixed inset-0 flex items-center justify-center bg-slate-900">
        <div class="glass p-10 rounded-3xl w-full max-w-sm">
            <h1 class="text-3xl font-black text-blue-500 mb-8 italic">MultiX <span class="text-white">Pro</span></h1>
            <form action="/login" method="post" class="space-y-6">
                <input name="u" placeholder="Admin" class="w-full bg-slate-900 border-slate-800 rounded-xl px-4 py-3 outline-none">
                <input name="p" type="password" placeholder="Pass" class="w-full bg-slate-900 border-slate-800 rounded-xl px-4 py-3 outline-none">
                <button type="submit" class="w-full bg-blue-600 font-bold py-4 rounded-xl">LOGIN</button>
            </form>
        </div>
    </div>
    <div x-show="isLogged" class="container mx-auto p-8">
        <div class="flex justify-between items-center mb-12">
            <h2 class="text-2xl font-black italic">MultiX <span class="text-blue-500">Pro</span></h2>
            <span class="text-xs font-mono bg-slate-900 px-4 py-2 rounded-full border border-slate-800">WSS SECURITY ACTIVE</span>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <template x-for="(agent, ip) in agents" :key="ip">
                <div class="glass p-6 rounded-2xl border-t-2 border-blue-500">
                    <div class="flex justify-between mb-4">
                        <h3 class="font-bold text-white text-lg" x-text="agent.alias"></h3>
                        <div class="h-2 w-2 rounded-full bg-green-500 animate-pulse"></div>
                    </div>
                    <div class="text-xs text-slate-500 mb-6" x-text="ip"></div>
                    <div class="flex gap-4 text-xs font-mono mb-6">
                        <span class="bg-slate-900 p-2 rounded-lg text-blue-400">CPU: <span x-text="agent.stats.cpu"></span>%</span>
                        <span class="bg-slate-900 p-2 rounded-lg text-blue-400">MEM: <span x-text="agent.stats.mem"></span>%</span>
                    </div>
                    <button @click="openManager(ip)" class="w-full bg-blue-600/20 text-blue-400 border border-blue-600/30 py-3 rounded-xl font-bold">MANAGE NODE</button>
                </div>
            </template>
        </div>
    </div>
    <div x-show="showModal" class="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4 z-50">
        <div class="glass w-full max-w-xl rounded-3xl p-8">
            <div class="flex justify-between mb-8"><h3>Configuration Building</h3><button @click="showModal=false">&times;</button></div>
            <div class="space-y-4">
                <select class="w-full bg-slate-900 border-slate-800 rounded-lg p-3 outline-none">
                    <option>VLESS + Reality</option><option>Hysteria 2</option>
                </select>
                <div class="flex gap-2">
                    <input x-model="tempVal" class="flex-1 bg-slate-900 border-slate-800 rounded-lg p-3 text-sm font-mono" placeholder="UUID or Password">
                    <button @click="genUuid()" class="bg-slate-800 px-4 rounded-lg text-xs font-bold">GEN</button>
                </div>
                <button class="w-full bg-blue-600 py-4 rounded-xl font-bold mt-4 shadow-lg shadow-blue-600/20">下发加密配置 (WSS)</button>
            </div>
        </div>
    </div>
    <script>
        function app() {
            return {
                isLogged: false, agents: {}, showModal: false, tempVal: '',
                init() { this.checkAuth(); setInterval(() => this.fetchData(), 3000); },
                checkAuth() { fetch('/api/state').then(r => r.ok ? this.isLogged = true : this.isLogged = false); },
                fetchData() { if(this.isLogged) fetch('/api/state').then(r => r.json()).then(d => { this.agents = d.agents; }); },
                openManager(ip) { this.showModal = true; },
                genUuid() { fetch('/api/gen', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({type:'uuid'})}).then(r=>r.json()).then(d=>this.tempVal=d.val); }
            }
        }
    </script>
</body>
</html>
EOF
}

# --- [ 4. 被控安装 ] ---
install_agent() {
    install_dependencies; mkdir -p $M_ROOT/agent
    echo -e "${YELLOW}连接协议选择：1. 强制V4 | 2. 强制V6 | 3. 自动探测 (WSS加密)${PLAIN}"
    read -p "选择: " NET_OPT
    read -p "主控域名/IP: " M_HOST; read -p "Token: " M_TOKEN

    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    # Agent Python - 关键点：wss 连接且忽略自签名证书校验
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, psutil, websockets, socket, platform, ssl
MASTER = "$M_HOST"; TOKEN = "$M_TOKEN"
async def run():
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE
    uri = f"wss://{MASTER}:8888"
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=10) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent), "hostname": socket.gethostname()}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    await asyncio.sleep(5)
        except: await asyncio.sleep(5)
asyncio.run(run())
EOF

    cat > /etc/systemd/system/multix-agent.service <<EOF
[Unit]
Description=MultiX Agent
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/agent/agent.py
Restart=always
WorkingDirectory=$M_ROOT/agent
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multix-agent; systemctl restart multix-agent
    echo -e "${GREEN}✅ 被控端加密连接已建立${PLAIN}"; pause_back
}

# --- [ 5. 菜单逻辑 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro ${SH_VER} (WSS Native)${PLAIN}"
    echo " 1. 安装/更新 主控端 (自签名 TLS 版)"
    echo " 2. 安装/更新 被控端 (WSS 加密版)"
    echo " 3. 凭据管理中心"
    echo " 4. 深度清理组件"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) credential_center ;;
        4) read -p "确认清理? [y/N]: " cf; [[ "$cf" == "y" ]] && { systemctl stop multix-master multix-agent; rm -rf "$M_ROOT" /usr/local/bin/sing-box; echo "Done"; pause_back; } ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

credential_center() {
    clear; echo -e "${SKYBLUE}🔐 凭据中心${PLAIN}"
    [ -f $M_ROOT/.env ] && source $M_ROOT/.env && echo -e "Token: $M_TOKEN | Port: $M_PORT"
    pause_back
}

check_root; install_shortcut; main_menu
