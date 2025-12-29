#!/bin/bash

# ==============================================================================
# MultiX Pro Script V72.7 (STABILITY & UI FIX)
# Fix 1: [Sys] Fixed path error in check_sys (/etc/issue).
# Fix 2: [UI] Isolated Jinja2 tags to prevent frontend Alpine.js conflicts.
# Fix 3: [UI] Full localized CSS + Design-ready mock card logic.
# Fix 4: [Net] Forced Dual-Stack Socket implementation for Web & WS.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V72.7"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础函数 ] ---
install_shortcut() { rm -f /usr/bin/multix; cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix; }
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() { 
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 主控安装 ] ---
install_master() {
    echo -e "${SKYBLUE}>>> 部署 MultiX 主控 (V72.7)${PLAIN}"
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y python3 python3-pip curl wget ntpdate openssl
    else apt-get update && apt-get install -y python3 python3-pip curl wget ntpdate openssl; fi
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p $M_ROOT/master
    openssl req -x509 -newkey rsa:2048 -keyout $M_ROOT/master/key.pem -out $M_ROOT/master/cert.pem -days 3650 -nodes -subj "/CN=MultiX" >/dev/null 2>&1

    read -p "面板访问端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信监听端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    M_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env

    _write_master_app_py
    systemctl daemon-reload; systemctl enable multix-master; systemctl restart multix-master
    get_public_ips
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    echo -e "IPv4 面板: http://${IPV4}:${M_PORT}"
    echo -e "IPv6 面板: http://[${IPV6}]:${M_PORT}"
    echo -e "通信端口: ${YELLOW}${WS_PORT}${PLAIN}"
    pause_back
}

_write_master_app_py() {
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
M_PORT = int(CONF.get('M_PORT', 7575))
WS_PORT = int(CONF.get('WS_PORT', 9339))
M_USER, M_PASS, M_TOKEN = CONF.get('M_USER', 'admin'), CONF.get('M_PASS', 'admin'), CONF.get('M_TOKEN', 'error')

app = Flask(__name__); app.secret_key = M_TOKEN

# 核心隔离：将 Flask 占位符改为 [[ ]]，把 {{ }} 留给前端脚本
app.jinja_env.variable_start_string = '[['
app.jinja_env.variable_end_string = ']]'

AGENTS = {"Mock-Node-01": {"alias": "示例卡片 (新加坡)", "stats": {"cpu":12,"mem":34}}} 

UI_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>MultiX Pro</title>
<style>
:root{--blue:#3b82f6;--bg:#020617;--glass:rgba(15,23,42,0.85)}
body{background:var(--bg);color:#f8fafc;font-family:ui-sans-serif,system-ui;margin:0;padding:30px}
.glass{background:var(--glass);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.08);border-radius:24px}
.header{display:flex;justify-content:space-between;align-items:center;max-width:1100px;margin:0 auto 50px}
.card{padding:25px;border-left:4px solid var(--blue);transition:0.4s;position:relative}
.card:hover{transform:translateY(-4px);background:rgba(30,41,59,0.5);border-left-color:#fff}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:25px;max-width:1100px;margin:0 auto}
.tk-tag{background:rgba(59,130,246,0.15);color:var(--blue);padding:6px 14px;border-radius:30px;font-size:12px;font-family:monospace;font-weight:600}
.dot{height:10px;width:10px;border-radius:50%;background:#22c55e;box-shadow:0 0 10px #22c55e}
.btn-m{width:100%;background:var(--blue);color:#fff;border:none;padding:12px;border-radius:12px;font-weight:800;cursor:pointer;margin-top:20px;letter-spacing:1px}
[x-cloak]{display:none !important}
</style>
<script src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
</head>
<body x-data="panel()" x-init="start()">
<div class="header">
    <div><h1 style="margin:0;color:var(--blue);font-style:italic;font-weight:900;font-size:2rem">MultiX <span style="color:#fff">Pro</span></h1>
    <div style="margin-top:12px"><span class="tk-tag">Master Token: <span id="tk-val">[[ master_token ]]</span></span></div></div>
    <div style="display:flex;gap:12px">
        <button @click="fetchData()" class="glass" style="color:#fff;padding:8px 20px;border-radius:30px;cursor:pointer;font-size:12px;font-weight:bold">REFRESH</button>
        <a href="/logout" style="color:#ef4444;text-decoration:none;border:1px solid rgba(239,68,68,0.2);padding:8px 20px;border-radius:30px;font-size:12px;font-weight:bold">LOGOUT</a>
    </div>
</div>

<div class="grid">
    <template x-for="(a, ip) in agents" :key="ip">
        <div class="glass card">
            <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:15px">
                <div><b style="font-size:1.2rem;color:#fff" x-text="a.alias"></b><br><span style="font-size:11px;color:#64748b;font-family:monospace" x-text="ip"></span></div>
                <div class="dot"></div>
            </div>
            <div style="display:flex;gap:10px;margin-bottom:10px">
                <div style="background:#0f172a;padding:8px 15px;border-radius:12px;flex:1;text-align:center"><small style="color:#64748b;display:block;font-size:9px;font-weight:900">CPU</small><b x-text="a.stats.cpu+'%'"></b></div>
                <div style="background:#0f172a;padding:8px 15px;border-radius:12px;flex:1;text-align:center"><small style="color:#64748b;display:block;font-size:9px;font-weight:900">MEM</small><b x-text="a.stats.mem+'%'"></b></div>
            </div>
            <button class="btn-m" @click="alert('Loading Visual Builder...')">MANAGE NODE</button>
        </div>
    </template>
</div>

<script>
function panel(){
    return {
        agents: {},
        start(){ this.fetchData(); setInterval(()=>this.fetchData(), 5000); },
        async fetchData(){
            const r=await fetch('/api/state'); const d=await r.json();
            this.agents = d.agents;
        }
    }
}
</script>
</body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    # 传递 master_token 到模板
    return render_template_string(UI_HTML, master_token=M_TOKEN)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method=='POST':
        if request.form.get('u')==M_USER and request.form.get('p')==M_PASS:
            session['logged']=True; return redirect('/')
    return """<body style="background:#020617;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif">
        <form method="post" style="background:#0f172a;padding:45px;border-radius:30px;width:320px;border:1px solid #1e293b;box-shadow:0 25px 50px -12px rgba(0,0,0,0.5)">
            <h2 style="color:#3b82f6;font-style:italic;margin-bottom:30px;font-weight:900">MultiX <span style="color:#fff">Login</span></h2>
            <input name="u" placeholder="User" style="width:100%;padding:14px;margin:10px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:12px;box-sizing:border-box">
            <input name="p" type="password" placeholder="Pass" style="width:100%;padding:14px;margin:10px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:12px;box-sizing:border-box">
            <button style="width:100%;padding:14px;background:#3b82f6;color:#fff;border:none;border-radius:12px;margin-top:15px;font-weight:900;cursor:pointer">ENTER PANEL</button>
        </form></body>"""

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

@app.route('/api/state')
def api_state():
    if not session.get('logged'): return jsonify({}), 401
    return jsonify({"master_token": M_TOKEN, "agents": AGENTS})

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=10)
        auth = json.loads(auth_raw)
        if auth.get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "alias": "Remote Node"}
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
    v4 = websockets.serve(ws_handler, "0.0.0.0", WS_PORT, ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", WS_PORT, ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF
}

# --- [ 菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 主控端 (Jinja2 隔离版)"
    echo " 2. 安装/更新 被控端"
    echo " 3. 通信诊断中心"
    echo " 4. 实时日志"
    echo " 5. 深度清理"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) diag_menu ;;
        4) journalctl -f -u multix-master ;;
        5) read -p "确认清理? [y/N]: " cf; [[ "$cf" == "y" ]] && { systemctl stop multix-master; rm -rf "$M_ROOT"; echo "Done"; } ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
