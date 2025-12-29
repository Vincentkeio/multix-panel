#!/bin/bash

# ==============================================================================
# MultiX Pro Script V72.6 (CUSTOM PORT & DUAL-STACK STABLE)
# Fix 1: [Config] Added Custom Communication Port (Default 9339).
# Fix 2: [Net] Explicit IPv6 dual-stack binding for both Web and WS.
# Fix 3: [UI] Full local CSS injection for glassmorphism UI.
# Fix 4: [Debug] Enhanced multi-node tracking and connection status.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V72.6"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础函数 ] ---
install_shortcut() { rm -f /usr/bin/multix; cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix; }
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() { IPV4=$(curl -s4m 2 api.ipify.org || echo "N/A"); IPV6=$(curl -s6m 2 api64.ipify.org || echo "N/A"); }
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 主控安装 ] ---
install_master() {
    echo -e "${SKYBLUE}>>> 部署 MultiX 主控 (V72.6)${PLAIN}"
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
    echo -e "通信端口: ${YELLOW}${WS_PORT}${PLAIN} (请确保安全组已放行)"
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
AGENTS = {"Local-Preview": {"alias": "测试卡片", "stats": {"cpu":0,"mem":0}}} 

UI_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>MultiX Pro</title>
<style>
:root{--blue:#3b82f6;--bg:#020617;--glass:rgba(15,23,42,0.85)}
body{background:var(--bg);color:#e2e8f0;font-family:sans-serif;margin:0;padding:25px}
.glass{background:var(--glass);backdrop-filter:blur(16px);border:1px solid rgba(255,255,255,0.1);padding:25px;border-radius:24px}
.header{display:flex;justify-content:space-between;max-width:1200px;margin:0 auto 40px}
.card{border-left:4px solid var(--blue);transition:0.3s;margin-bottom:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:20px;max-width:1200px;margin:0 auto}
.tk-tag{background:rgba(59,130,246,0.1);color:var(--blue);padding:4px 12px;border-radius:20px;font-size:11px}
</style>
<script>
async function refresh(){
    const r=await fetch('/api/state'); const d=await r.json();
    document.getElementById('tk').innerText=d.master_token;
    const g=document.getElementById('grid'); g.innerHTML='';
    for(let ip in d.agents){
        const a=d.agents[ip];
        g.innerHTML+=`<div class="glass card">
            <div style="display:flex;justify-content:space-between;margin-bottom:15px"><b>${a.alias}</b><div style="height:8px;width:8px;border-radius:50%;background:#22c55e;box-shadow:0 0 8px #22c55e"></div></div>
            <div style="font-size:11px;color:#64748b;margin-bottom:15px">${ip}</div>
            <div style="display:flex;gap:10px"><span style="background:#0f172a;padding:5px 10px;border-radius:8px;font-size:11px">CPU: ${a.stats.cpu}%</span></div>
            <button style="width:100%;background:var(--blue);color:#fff;border:none;padding:10px;border-radius:10px;margin-top:20px;font-weight:bold;cursor:pointer">MANAGE</button>
        </div>`;
    }
}
setInterval(refresh, 5000); window.onload=refresh;
</script></head>
<body>
<div class="header">
    <div><h1 style="margin:0;color:var(--blue);font-style:italic">MultiX <span style="color:#fff">Pro</span></h1><span class="tk-tag">Token: <span id="tk">...</span></span></div>
    <a href="/logout" style="color:#ef4444;text-decoration:none;border:1px solid rgba(239,68,68,0.2);padding:8px 15px;border-radius:20px;font-size:13px">LOGOUT</a>
</div>
<div class="grid" id="grid"></div>
</body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(UI_HTML)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method=='POST':
        if request.form.get('u')==M_USER and request.form.get('p')==M_PASS:
            session['logged']=True; return redirect('/')
    return """<body style="background:#020617;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif"><form method="post" style="background:#0f172a;padding:40px;border-radius:24px;width:300px"><h2>Login</h2><input name="u" placeholder="User" style="width:100%;padding:10px;margin:10px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:8px"><input name="p" type="password" placeholder="Pass" style="width:100%;padding:10px;margin:10px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:8px"><button style="width:100%;padding:10px;background:#3b82f6;color:#fff;border:none;border-radius:8px;margin-top:10px">LOGIN</button></form></body>"""

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
    # 使用自定义 WS_PORT 监听
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
    mkdir -p $M_ROOT/agent
    echo -e "${SKYBLUE}>>> 被控连接配置${PLAIN}"
    read -p "主控域名/IP: " M_HOST
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    echo -e "优先连接协议：1. 强制 IPv6 | 2. 强制 IPv4 | 3. 自动"
    read -p "选择 [1-3]: " NET_PREF

    # 安装 Sing-box
    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    # 生成 Agent 脚本
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, psutil, websockets, socket, platform, ssl, sys
MASTER = "$M_HOST"; TOKEN = "$M_TOKEN"; PORT = "$WS_PORT"; PREF = "$NET_PREF"
async def run():
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False; ssl_ctx.verify_mode = ssl.CERT_NONE
    family = socket.AF_UNSPEC
    if PREF == "1": family = socket.AF_INET6
    elif PREF == "2": family = socket.AF_INET
    uri = f"wss://{MASTER}:{PORT}"
    print(f"[Agent] Linking to {uri}...", flush=True)
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=15, family=family) as ws:
                print("[Agent] Linked!", flush=True)
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                    await ws.send(json.dumps({"type":"heartbeat", "data":stats}))
                    await asyncio.sleep(8)
        except Exception as e:
            print(f"[Agent] Retry Error: {e}", flush=True); await asyncio.sleep(5)
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
    echo -e "${GREEN}✅ 被控已启动。${PLAIN}"; pause_back
}

# --- [ 3. 诊断与维护 ] ---
diag_menu() {
    clear; echo -e "${SKYBLUE}📡 诊断中心${PLAIN}"
    echo "1. 查看监听端口 (Web & WS)"
    echo "2. 强制同步内核双栈参数"
    echo "0. 返回"
    read -p "选择: " d
    case $d in
        1) ss -tuln | grep -E '7575|9339' ;;
        2) sysctl -w net.ipv4.ip_forward=1; sysctl -w net.ipv6.bindv6only=0; sysctl -p; echo "已同步" ;;
        0) main_menu ;;
    esac; pause_back
}

# --- [ 4. 菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 主控端 (自定义端口版)"
    echo " 2. 安装/更新 被控端"
    echo " 3. 诊断中心"
    echo " 4. 实时日志"
    echo " 5. 深度清理"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) diag_menu ;;
        4) journalctl -f -u multix-master -u multix-agent ;;
        5) read -p "确认清理? [y/N]: " cf; [[ "$cf" == "y" ]] && { systemctl stop multix-master multix-agent; rm -rf "$M_ROOT"; echo "Done"; } ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
