#!/bin/bash

# ==============================================================================
# Multiy Pro Script V72.9 (FULL FIX & CONNECTIVITY MONITOR)
# Fix 1: [Bug] Restored missing 'install_agent' function.
# Fix 2: [UI] Full Glassmorphism Login & Dashboard with Refresh button.
# Fix 3: [Net] Enhanced Dual-Stack monitoring for both Master and Agent.
# Fix 4: [Protocol] Forced IPv6 option for NAT VPS during Agent setup.
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V72.9"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础函数 ] ---
install_shortcut() { rm -f /usr/bin/multiy; cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} 必须 Root 运行！" && exit 1; }
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
    echo -e "${SKYBLUE}>>> 部署 Multiy 主控 (V72.9)${PLAIN}"
    check_sys; get_public_ips
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y python3 python3-pip curl wget ntpdate openssl
    else apt-get update && apt-get install -y python3 python3-pip curl wget ntpdate openssl; fi
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p $M_ROOT/master
    openssl req -x509 -newkey rsa:2048 -keyout $M_ROOT/master/key.pem -out $M_ROOT/master/cert.pem -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板访问端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信监听端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    M_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env

    _write_master_app_py
    systemctl daemon-reload; systemctl enable multiy-master; systemctl restart multiy-master
    echo -e "${GREEN}✅ Multiy 主控端部署成功！${PLAIN}"
    echo -e "IPv4 面板: http://${IPV4}:${M_PORT}"
    echo -e "IPv6 面板: http://[${IPV6}]:${M_PORT}"
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
        with open('/opt/multiy_mvp/.env') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    except: pass
    return c

CONF = load_conf()
M_PORT = int(CONF.get('M_PORT', 7575))
WS_PORT = int(CONF.get('WS_PORT', 9339))
M_USER, M_PASS, M_TOKEN = CONF.get('M_USER', 'admin'), CONF.get('M_PASS', 'admin'), CONF.get('M_TOKEN', 'error')

app = Flask(__name__); app.secret_key = M_TOKEN
app.jinja_env.variable_start_string = '[['
app.jinja_env.variable_end_string = ']]'

AGENTS = {} 

LOGIN_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Login</title>
<style>
body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#020617;font-family:sans-serif;color:#fff}
.box{background:rgba(255,255,255,0.05);backdrop-filter:blur(15px);padding:40px;border-radius:24px;border:1px solid rgba(255,255,255,0.1);width:320px;text-align:center}
h2{color:#3b82f6;font-style:italic;margin-bottom:30px}
input{width:100%;padding:12px;margin:10px 0;background:rgba(0,0,0,0.3);border:1px solid #333;color:#fff;border-radius:10px;box-sizing:border-box}
button{width:100%;padding:12px;background:#3b82f6;color:#fff;border:none;border-radius:10px;font-weight:bold;cursor:pointer;margin-top:10px}
</style></head>
<body><div class="box"><h2>Multiy Pro</h2><form method="post"><input name="u" placeholder="User"><input name="p" type="password" placeholder="Pass"><button type="submit">LOGIN</button></form></div></body></html>
"""

INDEX_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Panel</title>
<style>
body{background:#020617;color:#e2e8f0;font-family:sans-serif;padding:30px}
.header{display:flex;justify-content:space-between;max-width:1100px;margin:0 auto 40px}
.glass{background:rgba(15,23,42,0.8);backdrop-filter:blur(15px);border:1px solid rgba(255,255,255,0.1);border-radius:20px;padding:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:20px;max-width:1100px;margin:0 auto}
.card{border-left:4px solid #3b82f6}
.btn{background:#3b82f6;color:#fff;border:none;padding:10px;border-radius:10px;cursor:pointer;width:100%;margin-top:15px}
.refresh-btn{background:#1e293b;color:#fff;border:1px solid #334155;padding:8px 15px;border-radius:20px;cursor:pointer;font-size:12px}
</style>
<script src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
</head>
<body x-data="panel()" x-init="start()">
<div class="header">
    <div><h2 style="color:#3b82f6">Multiy Pro</h2><small>Token: [[ master_token ]]</small></div>
    <div><button @click="fetchData()" class="refresh-btn">REFRESH</button> <a href="/logout" style="color:#ef4444;text-decoration:none">LOGOUT</a></div>
</div>
<div class="grid">
    <template x-for="(a, ip) in agents" :key="ip">
        <div class="glass card">
            <div style="display:flex;justify-content:space-between"><b>[[ a.alias ]]</b><span style="color:#22c55e">●</span></div>
            <div style="font-size:11px;color:#64748b;margin:10px 0">[[ ip ]]</div>
            <div style="display:flex;gap:10px;font-size:11px"><span>CPU: [[ a.stats.cpu ]]%</span><span>MEM: [[ a.stats.mem ]]%</span></div>
            <button class="btn" @click="alert('Building...')">MANAGE</button>
        </div>
    </template>
</div>
<script>
function panel(){ return { agents: {}, start(){ this.fetchData(); setInterval(()=>this.fetchData(), 5000); }, async fetchData(){ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents; } } }
</script></body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML, master_token=M_TOKEN)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method=='POST':
        if request.form.get('u')==M_USER and request.form.get('p')==M_PASS:
            session['logged']=True; return redirect('/')
    return render_template_string(LOGIN_HTML)

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
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    v4 = websockets.serve(ws_handler, "0.0.0.0", WS_PORT, ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", WS_PORT, ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF
}

# --- [ 2. 被控安装 (修复遗漏函数) ] ---
install_agent() {
    echo -e "${SKYBLUE}>>> 部署 Multiy 被控 (V72.9)${PLAIN}"
    mkdir -p $M_ROOT/agent
    read -p "主控域名/IP: " M_HOST
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    echo -e "连接偏好：1. 强制 IPv6 (适合NAT) | 2. 强制 IPv4 | 3. 自动"
    read -p "选择 [1-3]: " NET_PREF

    # 安装 Sing-box
    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, psutil, websockets, socket, platform, ssl, sys
MASTER = "$M_HOST"; TOKEN = "$M_TOKEN"; PORT = "$WS_PORT"; PREF = "$NET_PREF"
async def run():
    ssl_ctx = ssl.create_default_context(); ssl_ctx.check_hostname = False; ssl_ctx.verify_mode = ssl.CERT_NONE
    family = socket.AF_UNSPEC
    if PREF == "1": family = socket.AF_INET6
    elif PREF == "2": family = socket.AF_INET
    uri = f"wss://{MASTER}:{PORT}"
    print(f"[Agent] Linking to {uri}...", flush=True)
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=15, family=family) as ws:
                mode = 'IPv6' if ws.remote_address[0].count(':') > 1 else 'IPv4'
                print(f"[Agent] Linked via {mode}", flush=True)
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                    await ws.send(json.dumps({"type":"heartbeat", "data":stats}))
                    await asyncio.sleep(8)
        except Exception as e:
            print(f"[Agent] Error: {e}", flush=True); await asyncio.sleep(5)
asyncio.run(run())
EOF

    cat > /etc/systemd/system/multiy-agent.service <<EOF
[Unit]
Description=Multiy Agent
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/agent/agent.py
Restart=always
WorkingDirectory=$M_ROOT/agent
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multiy-agent; systemctl restart multiy-agent
    echo -e "${GREEN}✅ 被控部署完成！使用 journalctl -u multiy-agent -f 查看状态。${PLAIN}"
    pause_back
}

# --- [ 3. 连通性测试菜单 ] ---
diag_menu() {
    clear; echo -e "${SKYBLUE}📡 通信诊断中心${PLAIN}"
    echo "1. 查看主控监听接口 (ss -tuln)"
    echo "2. 被控端连接实时追踪 (日志)"
    echo "0. 返回"
    read -p "选择: " d
    case $d in
        1) ss -tuln | grep -E '7575|9339' ;;
        2) journalctl -u multiy-agent -f ;;
        0) main_menu ;;
    esac; pause_back
}

# --- [ 9. 主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (Jinja2 隔离版)"
    echo " 2. 安装/更新 Multiy 被控 (NAT 优先)"
    echo " 3. 通信诊断中心"
    echo " 4. 实时日志查看"
    echo " 5. 深度清理组件"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) diag_menu ;;
        4) journalctl -f -u multiy-master -u multiy-agent ;;
        5) read -p "确认清理? [y/N]: " cf; [[ "$cf" == "y" ]] && { systemctl stop multiy-master multiy-agent; rm -rf "$M_ROOT"; echo "Done"; } ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
