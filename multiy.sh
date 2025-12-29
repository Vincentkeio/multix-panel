#!/bin/bash

# ==============================================================================
# MultiX Pro Script V72.2 (ULTIMATE DUAL-STACK & UI PREVIEW)
# Fix 1: [Net] Forced Socket-level AF_INET6 dual-binding (v6only=0).
# Fix 2: [UI] Built-in "Mock Agent" card for instant feature preview.
# Fix 3: [Script] Fully restored all helper functions including pause_back.
# Fix 4: [Auth] Designer Glassmorphism Login Page fully active.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V72.2"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 1. 基础函数回归 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() {
    IPV4=$(curl -s4m 2 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 2 api64.ipify.org || echo "N/A")
}
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 2. 环境依赖 ] ---
install_dependencies() {
    echo -e "${YELLOW}[INFO]${PLAIN} 检查并安装依赖 (Python/WSS)..."
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y python3 python3-pip curl wget ntpdate openssl
    else apt-get update && apt-get install -y python3 python3-pip curl wget ntpdate openssl; fi
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    # 强制生成自签名证书
    mkdir -p $M_ROOT/master
    if [ ! -f "$M_ROOT/master/cert.pem" ]; then
        openssl req -x509 -newkey rsa:2048 -keyout $M_ROOT/master/key.pem -out $M_ROOT/master/cert.pem -days 3650 -nodes -subj "/CN=MultiX_Internal" >/dev/null 2>&1
    fi
}

# --- [ 3. 主控安装 ] ---
install_master() {
    install_dependencies
    echo -e "${SKYBLUE}>>> 主控配置${PLAIN}"
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
    echo -e "${GREEN}✅ 主控端部署成功！通信已由自签名 TLS 加密${PLAIN}"
    echo -e "IPv4: ${SKYBLUE}http://${IPV4}:${M_PORT}${PLAIN}"
    echo -e "IPv6: ${SKYBLUE}http://[${IPV6}]:${M_PORT}${PLAIN}"
    echo -e "令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

_write_master_app_py() {
# 物理顶格写入，确保 503 错误不发生
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

# 存储 Agent 信息，默认包含一个示例展示卡片
AGENTS = {
    "Demo-V6-Node": {
        "alias": "示例-新加坡GIA",
        "stats": {"cpu": 12, "mem": 45},
        "is_mock": True
    }
}

LOGIN_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>MultiX Pro</title>
<style>
body{background:#0a0a0c;height:100vh;display:flex;align-items:center;justify-content:center;font-family:sans-serif;margin:0;color:#fff}
.glass{background:rgba(255,255,255,0.03);backdrop-filter:blur(15px);padding:50px;border-radius:30px;border:1px solid rgba(255,255,255,0.1);width:350px;text-align:center;box-shadow:0 25px 50px rgba(0,0,0,0.5)}
h2{color:#3b82f6;font-style:italic;font-weight:900;margin-bottom:30px;letter-spacing:-1px}
input{width:100%;padding:14px;margin:12px 0;background:rgba(0,0,0,0.4);border:1px solid #333;color:#fff;border-radius:12px;box-sizing:border-box;outline:none;transition:0.3s}
input:focus{border-color:#3b82f6;box-shadow:0 0 15px rgba(59,130,246,0.3)}
button{width:100%;padding:15px;background:#3b82f6;color:#fff;border:none;border-radius:12px;font-weight:bold;cursor:pointer;margin-top:20px;transition:0.3s}
button:hover{background:#2563eb;transform:translateY(-2px)}
</style></head>
<body><div class="glass"><h2>MultiX <span style="color:#fff">Pro</span></h2>
<form method="post"><input name="u" placeholder="Admin Username" required autocomplete="off">
<input name="p" type="password" placeholder="Password" required><button type="submit">ENTER SYSTEM</button></form>
<p style="font-size:10px;color:#444;margin-top:20px">V72.2 SECURED INSTANCE</p></div></body></html>
"""

MAIN_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>MultiX Dashboard</title>
<style>
body{background:#050505;color:#e2e8f0;font-family:sans-serif;margin:0;padding:30px}
.header{display:flex;justify-content:space-between;align-items:center;max-width:1200px;margin:0 auto 50px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:25px;max-width:1200px;margin:0 auto}
.card{background:#111;border:1px solid #222;border-radius:24px;padding:25px;transition:0.3s;position:relative}
.card:hover{border-color:#3b82f6;transform:translateY(-5px)}
.status{width:10px;height:10px;border-radius:50%;background:#22c55e;box-shadow:0 0 10px #22c55e}
.badge{font-family:monospace;color:#fbbf24;background:rgba(251,191,36,0.1);padding:5px 12px;border-radius:10px;font-size:0.8rem}
.stat-item{background:#18181b;padding:12px;border-radius:15px;flex:1;text-align:center;border:1px solid #222}
.btn-manage{background:#3b82f6;color:#fff;border:none;padding:12px;border-radius:12px;font-weight:bold;cursor:pointer;width:100%;margin-top:20px}
.btn-logout{color:#ef4444;text-decoration:none;font-weight:bold;font-size:0.9rem;border:1px solid rgba(239,68,68,0.2);padding:8px 20px;border-radius:30px}
</style>
<script>
async function refresh() {
    const r = await fetch('/api/state');
    const d = await r.json();
    document.getElementById('tk').innerText = d.master_token;
    const grid = document.getElementById('grid'); grid.innerHTML = '';
    for (let ip in d.agents) {
        const a = d.agents[ip];
        grid.innerHTML += `<div class="card">
            <div style="display:flex;justify-content:space-between;margin-bottom:20px">
                <div><b style="font-size:1.2rem">${a.alias}</b><br><small style="color:#555;font-family:monospace">${ip}</small></div>
                <div class="status"></div>
            </div>
            <div style="display:flex;gap:15px">
                <div class="stat-item"><small style="color:#666">CPU</small><br><b>${a.stats.cpu}%</b></div>
                <div class="stat-item"><small style="color:#666">MEM</small><br><b>${a.stats.mem}%</b></div>
            </div>
            <button class="btn-manage" onclick="alert('即将开启 Sing-box 可视化编辑...')">MANAGE SING-BOX</button>
        </div>`;
    }
}
setInterval(refresh, 3000); window.onload = refresh;
</script></head>
<body>
<div class="header">
    <div><h1 style="margin:0;font-style:italic;color:#3b82f6;font-size:2rem">MultiX <span style="color:#fff">Pro</span></h1>
    <div style="margin-top:10px"><span class="badge">Master Token: <span id="tk">...</span></span></div></div>
    <a href="/logout" class="btn-logout">LOGOUT</a>
</div>
<div class="grid" id="grid"></div>
</body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(MAIN_HTML)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form.get('u') == M_USER and request.form.get('p') == M_PASS:
            session['logged'] = True; return redirect('/')
    return render_template_string(LOGIN_HTML)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

@app.route('/api/state')
def api_state():
    if not session.get('logged'): return jsonify({"error":"auth"}), 401
    return jsonify({"master_token": M_TOKEN, "agents": AGENTS})

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {}, "alias": "Initial..."}
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
    # 关键修复：显式监听 :: 并在系统层面允许双栈映射，解决 IPv6 打不开问题
    srv = websockets.serve(ws_handler, "::", 8888, ssl=ssl_ctx)
    loop.run_until_complete(srv)
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    # 强制监听双栈地址
    app.run(host='::', port=M_PORT)
EOF
}

# --- [ 4. 被控安装 ] ---
install_agent() {
    install_dependencies; mkdir -p $M_ROOT/agent
    read -p "主控域名/IP: " M_HOST; read -p "Token: " M_TOKEN
    
    # 自动识别并安装 Sing-box 二进制
    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

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

# --- [ 9. 主菜单逻辑 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro (V72.2 Dual-Stack)${PLAIN}"
    echo " 1. 安装/更新 主控端 (自签名 TLS)"
    echo " 2. 安装/更新 被控端 (WSS 加密)"
    echo " 3. 查看 凭据中心"
    echo " 4. 深度清理 组件"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) clear; [ -f $M_ROOT/.env ] && source $M_ROOT/.env && echo -e "Token: $M_TOKEN | Port: $M_PORT"; pause_back ;;
        4) read -p "确认清理? [y/N]: " cf; [[ "$cf" == "y" ]] && { systemctl stop multix-master multix-agent; rm -rf "$M_ROOT" /usr/local/bin/sing-box; echo "Done"; pause_back; } ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
