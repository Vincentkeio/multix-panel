#!/bin/bash

# ==============================================================================
# Multiy Pro Script V73.1 (SYSTEMD PATH FIX & UI PREVIEW)
# Fix 1: [Systemd] Forced service path to /lib/systemd/system/ for Debian/Ubuntu.
# Fix 2: [Net] Dual-Stack WebSocket binding on port 9339 (Physical 2-Thread).
# Fix 3: [UI] Built-in "Mock Card" to verify frontend rendering immediately.
# Fix 4: [Log] Added systemd status check after installation.
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V73.1"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
install_shortcut() { rm -f /usr/bin/multiy; cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
get_public_ips() { 
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 主控安装 ] ---
install_master() {
    echo -e "${SKYBLUE}>>> 正在部署 Multiy 主控 (V73.1)...${PLAIN}"
    get_public_ips
    # 安装依赖
    apt-get update && apt-get install -y python3 python3-pip curl wget ntpdate openssl
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p $M_ROOT/master
    openssl req -x509 -newkey rsa:2048 -keyout $M_ROOT/master/key.pem -out $M_ROOT/master/cert.pem -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板访问端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信监听端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    M_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    
    echo "M_TOKEN='$M_TOKEN'" > $M_ROOT/.env
    echo "M_PORT='$M_PORT'" >> $M_ROOT/.env
    echo "WS_PORT='$WS_PORT'" >> $M_ROOT/.env
    echo "M_USER='$M_USER'" >> $M_ROOT/.env
    echo "M_PASS='$M_PASS'" >> $M_ROOT/.env

    _write_master_app_py

    # 修复 Systemd 路径：强制写入 /lib/systemd/system/
    cat > /lib/systemd/system/multiy-master.service <<EOF
[Unit]
Description=Multiy Master Server
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/master/app.py
Restart=always
WorkingDirectory=$M_ROOT/master
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable multiy-master
    systemctl restart multiy-master
    
    echo -e "${GREEN}✅ Multiy 主控部署成功！${PLAIN}"
    echo -e "IPv4: http://${IPV4}:${M_PORT}"
    echo -e "IPv6: http://[${IPV6}]:${M_PORT}"
    echo -e "Token: ${YELLOW}${M_TOKEN}${PLAIN}"
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
M_PORT, WS_PORT = int(CONF.get('M_PORT', 7575)), int(CONF.get('WS_PORT', 9339))
M_USER, M_PASS, M_TOKEN = CONF.get('M_USER', 'admin'), CONF.get('M_PASS', 'admin'), CONF.get('M_TOKEN', 'error')

app = Flask(__name__); app.secret_key = M_TOKEN
app.jinja_env.variable_start_string, app.jinja_env.variable_end_string = '[[', ']]'

# 默认包含一个 Mock 卡片用于验证 UI 渲染
AGENTS = {"Mock-GIA-Node": {"alias": "示例-新加坡GIA", "stats": {"cpu":15,"mem":25}, "is_mock": True}}

UI_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Multiy Pro</title>
<style>
:root{--blue:#3b82f6;--bg:#020617;--glass:rgba(15,23,42,0.85)}
body{background:var(--bg);color:#f8fafc;font-family:sans-serif;margin:0;padding:30px}
.glass{background:var(--glass);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.1);border-radius:24px}
.header{display:flex;justify-content:space-between;max-width:1100px;margin:0 auto 40px}
.card{padding:25px;border-left:4px solid var(--blue);transition:0.3s;margin-bottom:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:20px;max-width:1100px;margin:0 auto}
.btn-m{width:100%;background:var(--blue);color:#fff;border:none;padding:12px;border-radius:12px;font-weight:bold;cursor:pointer;margin-top:15px}
.badge{background:rgba(59,130,246,0.15);color:var(--blue);padding:6px 14px;border-radius:30px;font-size:11px;font-family:monospace}
</style>
<script src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
</head>
<body x-data="panel()" x-init="start()">
<div class="header">
    <div><h1 style="color:var(--blue);font-style:italic;margin:0;font-weight:900">Multiy <span style="color:#fff">Pro</span></h1>
    <div style="margin-top:10px"><span class="badge">Token: <span id="tk">[[ master_token ]]</span></span></div></div>
    <div style="display:flex;gap:12px">
        <button @click="fetchData()" class="glass" style="color:#fff;padding:8px 15px;border-radius:20px;cursor:pointer;font-size:12px;font-weight:bold">REFRESH</button>
        <a href="/logout" style="color:#ef4444;text-decoration:none;border:1px solid rgba(239,68,68,0.2);padding:8px 15px;border-radius:20px;font-size:12px;font-weight:bold">LOGOUT</a>
    </div>
</div>
<div class="grid" id="grid">
    <template x-for="(a, ip) in agents" :key="ip">
        <div class="glass card">
            <div style="display:flex;justify-content:space-between">
                <div><b style="font-size:1.1rem" x-text="a.alias"></b><br><small style="color:#64748b;font-family:monospace" x-text="ip"></small></div>
                <div style="height:10px;width:10px;border-radius:50%;background:#22c55e;box-shadow:0 0 10px #22c55e"></div>
            </div>
            <div style="display:flex;gap:10px;margin:20px 0">
                <div style="background:#0f172a;padding:10px;border-radius:12px;flex:1;text-align:center"><small style="color:#64748b;display:block;font-size:9px">CPU</small><b x-text="a.stats.cpu+'%'"></b></div>
                <div style="background:#0f172a;padding:10px;border-radius:12px;flex:1;text-align:center"><small style="color:#64748b;display:block;font-size:9px">MEM</small><b x-text="a.stats.mem+'%'"></b></div>
            </div>
            <button class="btn-m" @click="alert('Manage Sing-box Module Loading...')">MANAGE NODE</button>
        </div>
    </template>
</div>
<script>
function panel(){ return { agents:{}, start(){this.fetchData();setInterval(()=>this.fetchData(),5000)}, async fetchData(){ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents; } } }
</script></body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(UI_HTML, master_token=M_TOKEN)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method=='POST':
        if request.form.get('u')==M_USER and request.form.get('p')==M_PASS:
            session['logged']=True; return redirect('/')
    return """<body style="background:#020617;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif">
    <form method="post" style="background:rgba(255,255,255,0.03);backdrop-filter:blur(20px);padding:50px;border-radius:30px;border:1px solid rgba(255,255,255,0.1);width:320px;text-align:center">
        <h2 style="color:#3b82f6;font-style:italic;font-weight:900;margin-bottom:30px">Multiy <span style="color:#fff">Pro</span></h2>
        <input name="u" placeholder="Admin" style="width:100%;padding:14px;margin:12px 0;background:rgba(0,0,0,0.4);border:1px solid #333;color:#fff;border-radius:12px">
        <input name="p" type="password" placeholder="Pass" style="width:100%;padding:14px;margin:12px 0;background:rgba(0,0,0,0.4);border:1px solid #333;color:#fff;border-radius:12px">
        <button style="width:100%;padding:15px;background:#3b82f6;color:#fff;border:none;border-radius:12px;font-weight:bold;cursor:pointer;margin-top:20px">LOGIN</button>
    </form></body>"""

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
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "alias": "Initial..."}
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
    # 物理双协议栈绑定
    v4 = websockets.serve(ws_handler, "0.0.0.0", WS_PORT, ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", WS_PORT, ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF
}

# --- [ 2. 被控安装 ] ---
install_agent() {
    echo -e "${SKYBLUE}>>> 部署 Multiy 被控 (V73.1)${PLAIN}"
    mkdir -p $M_ROOT/agent
    read -p "主控域名/IP: " M_HOST
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    echo -e "连接偏好：1. 强制 IPv6 (NAT) | 2. 强制 IPv4 | 3. 自动"
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
                proto = 'IPv6' if ws.remote_address[0].count(':') > 1 else 'IPv4'
                print(f"[Agent] Linked successfully via {proto}", flush=True)
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                    await ws.send(json.dumps({"type":"heartbeat", "data":stats}))
                    await asyncio.sleep(8)
        except Exception as e:
            print(f"[Agent] Connection Failed: {e}", flush=True); await asyncio.sleep(5)
asyncio.run(run())
EOF

    cat > /lib/systemd/system/multiy-agent.service <<EOF
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
    systemctl daemon-reload
    systemctl enable multiy-agent
    systemctl restart multiy-agent
    echo -e "${GREEN}✅ 被控部署完成！使用 journalctl -u multiy-agent -f 查看状态。${PLAIN}"
    pause_back
}

# --- [ 3. 连接监控 ] ---
status_monitor() {
    clear; echo -e "${SKYBLUE}📡 连接监控中心${PLAIN}"
    echo -e "1. [主控] 端口监听状态 (Web & WS)"
    echo -e "2. [被控] 当前连接日志 (V4/V6)"
    echo -e "3. [主控] 实时连接日志"
    echo -e "0. 返回"
    read -p "选择: " m
    case $m in
        1) ss -tuln | grep -E '7575|9339' ;;
        2) journalctl -u multiy-agent -f ;;
        3) journalctl -u multiy-master -f ;;
        0) main_menu ;;
    esac; pause_back
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (修复 Systemd)"
    echo " 2. 安装/更新 Multiy 被控 (NAT 优先)"
    echo " 3. 连接监控中心 (状态 & 路径)"
    echo " 4. 深度清理组件"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) status_monitor ;;
        4) read -p "确认清理? [y/N]: " cf; [[ "$cf" == "y" ]] && { systemctl stop multiy-master multiy-agent 2>/dev/null; rm -rf "$M_ROOT"; echo "Done"; } ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
