#!/bin/bash

# ==============================================================================
# MultiX Pro Script V72.4 (FULL RESTORED & DUAL-STACK WSS)
# Fix 1: [Net] Explicit dual-stack listening for 8888 WSS port.
# Fix 2: [UI] Tailwind CSS localized logic with Token display in Header.
# Fix 3: [Security] Self-signed TLS for configuration encryption.
# Fix 4: [Feature] Visual parameter builders for Sing-box config.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V72.4"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 1. 基础环境 ] ---
install_shortcut() { rm -f /usr/bin/multix; cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix; }
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() { IPV4=$(curl -s4m 2 api.ipify.org || echo "N/A"); IPV6=$(curl -s6m 2 api64.ipify.org || echo "N/A"); }
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 2. 主控安装 ] ---
install_master() {
    echo -e "${SKYBLUE}>>> 正在安装 MultiX 主控 (WSS 原生版)...${PLAIN}"
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y python3 python3-pip curl wget ntpdate openssl
    else apt-get update && apt-get install -y python3 python3-pip curl wget ntpdate openssl; fi
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1

    mkdir -p $M_ROOT/master
    # 自动生成 TLS 证书
    openssl req -x509 -newkey rsa:2048 -keyout $M_ROOT/master/key.pem -out $M_ROOT/master/cert.pem -days 3650 -nodes -subj "/CN=MultiX" >/dev/null 2>&1

    read -p "面板端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    M_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env

    _write_master_app_py

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
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    echo -e "IPv4: http://${IPV4}:${M_PORT}"
    echo -e "IPv6: http://[${IPV6}]:${M_PORT}"
    echo -e "Token: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

_write_master_app_py() {
# 物理顶格写入 app.py
cat > $M_ROOT/master/app.py <<'EOF'
import json, asyncio, psutil, os, socket, websockets, ssl, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
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
AGENTS = {"Demo-Node": {"alias": "示例-新加坡", "stats": {"cpu": 15, "mem": 30}}} 

# 玻璃拟态 UI 模板
HTML_T = """
<!DOCTYPE html>
<html lang="en" class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro V72.4</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <style> .glass { background: rgba(15, 23, 42, 0.8); backdrop-filter: blur(12px); border: 1px solid rgba(255,255,255,0.1); } </style>
</head>
<body class="bg-slate-950 text-slate-200" x-data="app()" x-init="init()">
    <div x-show="!isLogged" class="fixed inset-0 flex items-center justify-center bg-black">
        <div class="glass p-10 rounded-3xl w-full max-w-sm shadow-2xl">
            <h1 class="text-3xl font-black text-blue-500 mb-8 italic text-center">MultiX <span class="text-white">Pro</span></h1>
            <form action="/login" method="post" class="space-y-6">
                <input name="u" placeholder="Admin" class="w-full bg-slate-900 border-slate-800 rounded-xl px-4 py-3 outline-none focus:ring-2 ring-blue-500">
                <input name="p" type="password" placeholder="Pass" class="w-full bg-slate-900 border-slate-800 rounded-xl px-4 py-3 outline-none focus:ring-2 ring-blue-500">
                <button type="submit" class="w-full bg-blue-600 font-bold py-4 rounded-xl shadow-lg shadow-blue-500/20">ACCESS SYSTEM</button>
            </form>
        </div>
    </div>

    <div x-show="isLogged" class="container mx-auto p-8" x-cloak>
        <div class="flex justify-between items-center mb-12">
            <div>
                <h2 class="text-2xl font-black italic">MultiX <span class="text-blue-500">Pro</span></h2>
                <div class="mt-2 flex gap-4">
                    <span class="text-[10px] bg-slate-900 px-3 py-1 rounded-full border border-slate-800 text-yellow-500 font-mono">TK: [[ masterToken ]]</span>
                    <span class="text-[10px] bg-blue-900/20 px-3 py-1 rounded-full border border-blue-800/30 text-blue-400">WSS SECURITY ACTIVE</span>
                </div>
            </div>
            <a href="/logout" class="text-xs font-bold text-red-500 border border-red-500/20 px-4 py-2 rounded-full hover:bg-red-500 hover:text-white transition-all">LOGOUT</a>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <template x-for="(agent, ip) in agents" :key="ip">
                <div class="glass p-6 rounded-2xl group border-l-4 border-blue-500 hover:scale-[1.02] transition-all">
                    <div class="flex justify-between mb-4">
                        <h3 class="font-bold text-white text-lg" x-text="agent.alias"></h3>
                        <div class="h-2 w-2 rounded-full bg-green-500 shadow-[0_0_10px_#22c55e]"></div>
                    </div>
                    <div class="text-[10px] font-mono text-slate-500 mb-6" x-text="ip"></div>
                    <div class="flex gap-4 mb-6">
                        <div class="flex-1 bg-slate-900/50 p-2 rounded-lg border border-slate-800 text-center">
                            <p class="text-[9px] text-slate-500 font-bold uppercase">CPU</p>
                            <p class="text-sm font-mono text-blue-400" x-text="agent.stats.cpu + '%'"></p>
                        </div>
                        <div class="flex-1 bg-slate-900/50 p-2 rounded-lg border border-slate-800 text-center">
                            <p class="text-[9px] text-slate-500 font-bold uppercase">MEM</p>
                            <p class="text-sm font-mono text-blue-400" x-text="agent.stats.mem + '%'"></p>
                        </div>
                    </div>
                    <button @click="openManager(ip)" class="w-full bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold py-3 rounded-xl transition-all">MANAGE SING-BOX</button>
                </div>
            </template>
        </div>
    </div>

    <div x-show="showModal" class="fixed inset-0 bg-black/90 backdrop-blur-sm flex items-center justify-center p-4 z-50" x-cloak>
        <div class="glass w-full max-w-2xl rounded-3xl overflow-hidden shadow-2xl">
            <div class="p-6 border-b border-slate-800 flex justify-between items-center">
                <h3 class="font-bold">Edit Nodes on <span class="text-blue-500" x-text="activeIp"></span></h3>
                <button @click="showModal = false" class="text-slate-500 hover:text-white text-2xl">&times;</button>
            </div>
            <div class="p-8 space-y-6">
                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label class="text-[10px] uppercase font-bold text-slate-500 mb-2 block">Protocol</label>
                        <select class="w-full bg-slate-900 border-slate-800 rounded-xl p-3 outline-none focus:ring-2 ring-blue-500">
                            <option>VLESS + Reality</option><option>Hysteria 2</option><option>VMess</option>
                        </select>
                    </div>
                    <div>
                        <label class="text-[10px] uppercase font-bold text-slate-500 mb-2 block">Listen Port</label>
                        <input class="w-full bg-slate-900 border-slate-800 rounded-xl p-3 outline-none" value="443">
                    </div>
                </div>
                <div>
                    <label class="text-[10px] uppercase font-bold text-slate-500 mb-2 block">UUID / Secret</label>
                    <div class="flex gap-2">
                        <input x-model="tempVal" class="flex-1 bg-slate-900 border-slate-800 rounded-xl p-3 outline-none font-mono text-sm">
                        <button @click="genUuid()" class="bg-slate-800 hover:bg-slate-700 px-6 rounded-xl text-xs font-bold">GEN</button>
                    </div>
                </div>
                <div class="bg-blue-900/10 border border-blue-500/20 p-4 rounded-xl">
                    <p class="text-[10px] text-blue-400 font-bold uppercase mb-1">Reality Sni</p>
                    <input class="w-full bg-transparent outline-none text-sm" value="www.microsoft.com">
                </div>
                <button class="w-full bg-blue-600 hover:bg-blue-500 py-4 rounded-2xl font-bold shadow-lg shadow-blue-500/30 transition-all">SYNC TO REMOTE AGENT</button>
            </div>
        </div>
    </div>

    <script>
        function app() {
            return {
                isLogged: false, agents: {}, masterToken: '', showModal: false, activeIp: '', tempVal: '',
                init() {
                    this.checkAuth();
                    setInterval(() => this.fetchData(), 3000);
                },
                checkAuth() {
                    fetch('/api/state').then(r => r.ok ? this.isLogged = true : this.isLogged = false);
                },
                fetchData() {
                    if(!this.isLogged) return;
                    fetch('/api/state').then(r => r.json()).then(d => {
                        this.agents = d.agents;
                        this.masterToken = d.master_token;
                    });
                },
                openManager(ip) { this.activeIp = ip; this.showModal = true; },
                genUuid() {
                    fetch('/api/tool', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({type:'uuid'})})
                    .then(r=>r.json()).then(d=>this.tempVal=d.val);
                }
            }
        }
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_T.replace('[[', '{{').replace(']]', '}}'), masterToken=M_TOKEN)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form.get('u') == M_USER and request.form.get('p') == M_PASS:
            session['logged'] = True; return redirect('/')
    return render_template_string(HTML_T.replace('[[', '{{').replace(']]', '}}'), masterToken=M_TOKEN)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

@app.route('/api/state')
def api_state():
    if not session.get('logged'): return jsonify({}), 401
    return jsonify({"master_token": M_TOKEN, "agents": AGENTS})

@app.route('/api/tool', methods=['POST'])
def api_tool():
    t = request.json.get('type')
    if t == 'uuid':
        val = subprocess.check_output(['cat', '/proc/sys/kernel/random/uuid']).decode().strip()
        return jsonify({"val": val})
    return jsonify({"val": ""})

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=10)
        auth = json.loads(auth_raw)
        if auth.get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "alias": "Loading..."}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data')
                    AGENTS[ip]['alias'] = d.get('data', {}).get('hostname', 'Node')
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    # 显式物理双监听
    v4 = websockets.serve(ws_handler, "0.0.0.0", 8888, ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", 8888, ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=M_PORT)
EOF
}

# --- [ 3. 被控安装 ] ---
install_agent() {
    mkdir -p $M_ROOT/agent
    echo -e "${SKYBLUE}>>> 被控配置 (WSS 原生)${PLAIN}"
    read -p "主控域名/IP: " M_HOST; read -p "主控 Token: " M_TOKEN
    
    # 安装 Sing-box
    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    # 生成 Agent 脚本
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, psutil, websockets, socket, platform, ssl, sys
MASTER = "$M_HOST"
TOKEN = "$M_TOKEN"
async def run():
    print(f"[Agent] Connecting to wss://{MASTER}:8888...", flush=True)
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE
    uri = f"wss://{MASTER}:8888"
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=15) as ws:
                print("[Agent] Linked. Auth...", flush=True)
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {
                        "cpu": int(psutil.cpu_percent()), 
                        "mem": int(psutil.virtual_memory().percent), 
                        "hostname": socket.gethostname()
                    }
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    await asyncio.sleep(5)
        except Exception as e:
            print(f"[Agent] Error: {e}. Retry in 5s...", flush=True)
            await asyncio.sleep(5)
if __name__ == "__main__":
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
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multix-agent; systemctl restart multix-agent
    echo -e "${GREEN}✅ 被控已上线。${PLAIN}"
    pause_back
}

# --- [ 4. 菜单逻辑 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro ${SH_VER} (WSS Native)${PLAIN}"
    echo " 1. 安装/更新 主控端 (玻璃拟态 UI)"
    echo " 2. 安装/更新 被控端 (Sing-box)"
    echo " 3. 实时日志查看 (主控)"
    echo " 4. 实时日志查看 (被控)"
    echo " 5. 凭据管理中心"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) journalctl -u multix-master -f ;; 4) journalctl -u multix-agent -f ;;
        5) clear; [ -f $M_ROOT/.env ] && source $M_ROOT/.env && echo -e "Token: $M_TOKEN | Port: $M_PORT"; pause_back ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
