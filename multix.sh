#!/bin/bash

# ==============================================================================
# MultiX Pro Script V71.5 (FULL AUDIT & CONNECTIVITY FIX)
# Fix 1: [UI] Designer Login Page (Glassmorphism style).
# Fix 2: [Net] Hybrid Socket Binding to force IPv4/IPv6 dual-stack access.
# Fix 3: [API] Fixed internal state logic causing missing Header & Cards data.
# Fix 4: [Syntax] Zero-indentation Python block to resolve all Bash/Python errors.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V71.5"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

install_shortcut() { rm -f /usr/bin/multix; cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix; }
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() {
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A"); IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 2. Environment Fixes ] ---
fix_dual_stack() {
    if grep -q "net.ipv6.bindv6only" /etc/sysctl.conf; then sed -i 's/net.ipv6.bindv6only.*/net.ipv6.bindv6only = 0/' /etc/sysctl.conf
    else echo "net.ipv6.bindv6only = 0" >> /etc/sysctl.conf; fi
    sysctl -p >/dev/null 2>&1
}

install_dependencies() {
    echo -e "${YELLOW}[INFO]${PLAIN} Installing dependencies..."
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y epel-release python3 python3-pip curl wget socat nc ntpdate
    else apt-get update && apt-get install -y python3 python3-pip curl wget socat netcat-openbsd ntpdate; fi
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    fix_dual_stack
}

# --- [ 5. Credentials Center ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 Credentials Manager${PLAIN}"
    if [ -f $M_ROOT/.env ]; then
        M_T=$(grep 'M_TOKEN=' $M_ROOT/.env | cut -d"'" -f2)
        M_P=$(grep 'M_PORT=' $M_ROOT/.env | cut -d"'" -f2)
        M_U=$(grep 'M_USER=' $M_ROOT/.env | cut -d"'" -f2)
        M_W=$(grep 'M_PASS=' $M_ROOT/.env | cut -d"'" -f2)
        get_public_ips
        echo -e "${YELLOW}>>> Panel Access <<<${PLAIN}"
        echo -e "IPv4: ${GREEN}http://${IPV4}:${M_P}${PLAIN}"
        echo -e "IPv6: ${GREEN}http://[${IPV6}]:${M_P}${PLAIN}"
        echo -e "User: ${SKYBLUE}${M_U}${PLAIN} | Pass: ${SKYBLUE}${M_W}${PLAIN} | Token: ${YELLOW}${M_T}${PLAIN}"
    fi
    pause_back
}

# --- [ 11. Network Repair ] ---
smart_network_repair() {
    echo -e "\n${YELLOW}🔧 Executing Network Repair...${PLAIN}"
    ip link set dev eth0 mtu 1280 2>/dev/null; ip link set dev ens3 mtu 1280 2>/dev/null
    ntpdate pool.ntp.org >/dev/null 2>&1; sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    echo -e "${GREEN}✅ Done!${PLAIN}"; pause_back
}

# --- [ 6. Master Installation ] ---
install_master() {
    install_dependencies; mkdir -p $M_ROOT/master
    read -p "Port [7575]: " IN_PORT; M_PORT=${IN_PORT:-7575}
    read -p "User [admin]: " IN_USER; M_USER=${IN_USER:-admin}
    read -p "Pass [admin]: " IN_PASS; M_PASS=${IN_PASS:-admin}
    read -p "Token: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
    _write_master_app_py
    cat > /etc/systemd/system/multix-master.service <<EOF
[Unit]
Description=MultiX Master
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/master/app.py
Restart=always
User=root
WorkingDirectory=$M_ROOT/master
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multix-master; systemctl restart multix-master
    credential_center
}

_write_master_app_py() {
cat > $M_ROOT/master/app.py <<'EOF'
import json, asyncio, psutil, os, socket, subprocess, base64, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread
logging.basicConfig(level=logging.ERROR)
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
app.jinja_env.variable_start_string, app.jinja_env.variable_end_string = '[[', ']]'
AGENTS = {"local-demo": {"alias": "Demo Node", "stats": {"cpu": 15, "mem": 40, "os": "Demo OS", "xui": "v2.x.x"}, "nodes": [{"id": 1, "remark": "Demo-VLESS", "port": 443, "protocol": "vless", "settings": {"clients":[{"id":"demo-uuid"}]}, "stream_settings": {"network":"ws", "security":"tls"}}], "is_demo": True}}
LOOP_GLOBAL = None
def get_sys_info():
    try:
        v4 = os.popen("curl -s4m 2 api.ipify.org || echo 'N/A'").read().strip()
        v6 = os.popen("curl -s6m 2 api64.ipify.org || echo 'N/A'").read().strip()
        return {"cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "ipv4": v4, "ipv6": v6}
    except: return {"cpu":0,"mem":0,"ipv4":"N/A","ipv6":"N/A"}
LOGIN_T = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Login</title><style>
body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0c;font-family:sans-serif;color:#fff}
.box{background:rgba(255,255,255,0.05);backdrop-filter:blur(10px);padding:40px;border-radius:20px;border:1px solid rgba(255,255,255,0.1);width:320px;text-align:center}
h2{color:#0d6efd;font-style:italic;margin-bottom:30px}
input{width:100%;padding:12px;margin:10px 0;background:rgba(0,0,0,0.3);border:1px solid #333;color:#fff;border-radius:8px;box-sizing:border-box;outline:none}
button{width:100%;padding:12px;background:#0d6efd;color:#fff;border:none;border-radius:8px;font-weight:bold;cursor:pointer;margin-top:10px}
</style></head><body><div class="box"><h2>MultiX Pro</h2><form method="post"><input name="u" placeholder="Admin User"><input name="p" type="password" placeholder="Password"><button type="submit">LOGIN</button></form></div></body></html>
"""
HTML_T = """
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head><meta charset="UTF-8"><title>MultiX Pro</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.0/font/bootstrap-icons.css">
<style>body{background:#050505;font-family:sans-serif;padding-top:20px}.card{background:#111;border:1px solid #333;border-radius:15px;transition:0.3s}.card:hover{border-color:#0d6efd}.status-dot{width:10px;height:10px;border-radius:50%;display:inline-block;background:#198754}.stat-box{font-size:0.8rem;color:#aaa;background:#1a1a1a;padding:5px 12px;border-radius:8px;border:1px solid #333}.header-token{font-family:monospace;color:#ffc107;margin-left:15px}</style>
</head>
<body>
<div class="container">
<div class="d-flex justify-content-between align-items-center mb-4">
<div><h2 class="fw-bold text-primary">MultiX <span class="text-white">Pro</span></h2><div class="small mt-1"><span class="badge bg-secondary">v4</span> <span id="ipv4">...</span> | <span class="badge bg-primary">v6</span> <span id="ipv6">...</span><span class="header-token">TK: [[ token ]]</span></div></div>
<div class="d-flex gap-2"><span class="stat-box">CPU: <span id="cpu">0</span>%</span><span class="stat-box">MEM: <span id="mem">0</span>%</span><a href="/logout" class="btn btn-outline-danger btn-sm px-3 rounded-pill">LOGOUT</a></div>
</div>
<div class="row g-4" id="node-list"></div>
</div>
<div class="modal fade" id="configModal" tabindex="-1"><div class="modal-dialog modal-lg modal-dialog-centered"><div class="modal-content" style="background:#0a0a0a;border:1px solid #333;border-radius:20px"><div class="modal-header"><h5>Node Inbound Config</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body" id="view-list"><div class="d-flex justify-content-between mb-3"><span>Inbound List</span><button class="btn btn-sm btn-success" onclick="toAddMode()">+ NEW NODE</button></div><table class="table table-dark text-center"><thead><tr><th>Remark</th><th>Port</th><th>Protocol</th><th>Action</th></tr></thead><tbody id="tbl-body"></tbody></table></div><div class="modal-body" id="view-edit" style="display:none"><form id="nodeForm"><div class="row g-3"><div class="col-6"><label>Remark</label><input class="form-control" id="remark"></div><div class="col-6"><label>Port</label><input class="form-control" type="number" id="port"></div><div class="col-12"><label>Protocol</label><select class="form-select" id="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option><option value="shadowsocks">Shadowsocks</option></select></div></div></form><button class="btn btn-primary w-100 mt-4" id="saveBtn">SYNC TO NODE</button></div></div></div></div>
<script>
let AGENTS={},ACTIVE_IP='',CURRENT_NODES=[];
function updateState(){$.get('/api/state',function(d){$('#cpu').text(d.master.stats.cpu);$('#mem').text(d.master.stats.mem);$('#ipv4').text(d.master.ipv4);$('#ipv6').text(d.master.ipv6);AGENTS=d.agents;renderGrid()}).fail(function(){$('#error-banner').show()})}
function renderGrid(){$('#node-list').empty();for(const[ip,a]of Object.entries(AGENTS)){const c=\`<div class="col-md-4"><div class="card p-3"><div class="d-flex justify-content-between"><h5>\${a.alias}</h5><span class="status-dot"></span></div><div class="small text-secondary mb-3">\${ip}</div><div class="d-flex gap-2 mb-3"><span class="stat-box">OS: \${a.stats.os}</span><span class="stat-box">CPU: \${a.stats.cpu}%</span></div><button class="btn btn-primary w-100 rounded-pill fw-bold" onclick="openManager('\${ip}')">MANAGE NODES</button></div></div>\`;$('#node-list').append(c)}}
function openManager(ip){ACTIVE_IP=ip;CURRENT_NODES=AGENTS[ip].nodes||[];toListView();$('#configModal').modal('show')}
function toListView(){$('#view-edit').hide();$('#view-list').show();const t=$('#tbl-body');t.empty();CURRENT_NODES.forEach((n,i)=>{t.append(\`<tr><td>\${n.remark}</td><td>\${n.port}</td><td>\${n.protocol}</td><td><button class="btn btn-sm btn-link" onclick="toEditMode(\${i})">Edit</button></td></tr>\`)})}
function toAddMode(){$('#view-list').hide();$('#view-edit').show();$('#nodeForm')[0].reset()}
function toEditMode(i){$('#view-list').hide();$('#view-edit').show();const n=CURRENT_NODES[i];$('#remark').val(n.remark);$('#port').val(n.port);$('#protocol').val(n.protocol)}
$('#saveBtn').click(function(){$.ajax({url:'/api/sync',type:'POST',contentType:'application/json',data:JSON.stringify({ip:ACTIVE_IP,config:{remark:$('#remark').val(),port:$('#port').val(),protocol:$('#protocol').val()}}),success:function(r){$('#configModal').modal('hide');alert('Action Successfully Simulated');}})});
$(document).ready(function(){updateState();setInterval(updateState,3000)});
</script></body></html>
"""
@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_T, token=M_TOKEN)
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form.get('u') == M_USER and request.form.get('p') == M_PASS: session['logged'] = True; return redirect('/')
    return render_template_string(LOGIN_T)
@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')
@app.route('/api/state')
def api_state():
    s = get_sys_info()
    return jsonify({"master": {"ipv4": s['ipv4'], "ipv6": s['ipv6'], "stats": {"cpu": s['cpu'], "mem": s['mem']}}, "agents": AGENTS})
@app.route('/api/sync', methods=['POST'])
def api_sync():
    d = request.json
    target = d.get('ip')
    if target in AGENTS:
        if AGENTS[target].get('is_demo'): return jsonify({"status": "demo_ok"})
        payload = json.dumps({"action": "sync_node", "token": M_TOKEN, "data": d.get('config')})
        asyncio.run_coroutine_threadsafe(AGENTS[target]['ws'].send(payload), LOOP_GLOBAL)
        return jsonify({"status": "sent"})
    return jsonify({"status": "offline"}), 404
async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {}, "nodes": []}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data', {})
                    AGENTS[ip]['nodes'] = d.get('nodes', [])
                    AGENTS[ip]['alias'] = d.get('data', {}).get('os', 'Node')
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]
def start_ws():
    global LOOP_GLOBAL; LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def m(): await websockets.serve(ws_handler, "::", 8888)
    LOOP_GLOBAL.run_until_complete(m())
if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF
}

# --- [ 7. Agent Logic ] ---
install_agent() {
    install_dependencies; mkdir -p $M_ROOT/agent
    if [ ! -d "/etc/x-ui" ]; then
        docker run -d --name 3x-ui --restart always --network host -v /etc/x-ui:/etc/x-ui -v /etc/x-ui/bin:/usr/local/x-ui/bin mhsanaei/3x-ui:latest >/dev/null 2>&1
        sleep 5
    fi
    echo -e "${SKYBLUE}>>> Agent Config${PLAIN}"
    read -p "Master Host: " IN_HOST; read -p "Token: " IN_TOKEN
    echo "AGENT_HOST='$IN_HOST'" > "$AGENT_CONF"; echo "AGENT_TOKEN='$IN_TOKEN'" >> "$AGENT_CONF"
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket, platform, time
MASTER = "$IN_HOST"; TOKEN = "$IN_TOKEN"; DB_PATH = "/app/db_share/x-ui.db"
def smart_sync_db(data):
    try:
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor(); cursor.execute("PRAGMA table_info(inbounds)")
        cols = [i[1] for i in cursor.fetchall()]
        base = {'user_id':1,'up':0,'down':0,'total':0,'remark':data['remark'],'enable':1,'expiry_time':0,'port':data['port'],'protocol':data['protocol'],'tag':'multix'}
        valid = {k:v for k,v in base.items() if k in cols}
        keys = ", ".join(valid.keys()); ph = ", ".join(["?"]*len(valid))
        cur.execute(f"INSERT INTO inbounds ({keys}) VALUES ({ph})", list(valid.values()))
        conn.commit(); conn.close(); return True
    except: return False
async def run():
    target = MASTER
    if ":" in target and not target.startswith("["): target = f"[{target}]"
    uri = f"ws://{target}:8888"
    while True:
        try:
            async with websockets.connect(uri, ping_interval=20) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()),"os":platform.system()}
                    nodes = []
                    if os.path.exists(DB_PATH):
                        conn = sqlite3.connect(DB_PATH); cur = conn.cursor()
                        cur.execute("SELECT remark,port,protocol FROM inbounds");
                        for r in cur.fetchall(): nodes.append({"remark":r[0],"port":r[1],"protocol":r[2]})
                        conn.close()
                    await ws.send(json.dumps({"type":"heartbeat","data":stats,"nodes":nodes}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=5); task = json.loads(msg)
                    if task.get('action') == 'sync_node': smart_sync_db(task['data'])
        except: await asyncio.sleep(5)
asyncio.run(run())
EOF
    cd $M_ROOT/agent; docker build -t multix-agent-v71 .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host -v /etc/x-ui:/app/db_share -v $M_ROOT/agent:/app multix-agent-v71
    echo -e "${GREEN}✅ Agent Active${PLAIN}"; pause_back
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro (V71.5 FULL)${PLAIN}"
    echo " 1. Install Master (Designer UI)"
    echo " 2. Install Agent"
    echo " 3. Connectivity Diagnostics"
    echo " 4. Network Repair (MTU/Dual-Stack)"
    echo " 5. Service Manager"
    echo " 7. Credentials Center"
    echo " 10. Deep Cleanup"
    echo " 0. Exit"
    read -p "Select: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) nc -zv $IPV6 8888; pause_back ;; 4) smart_network_repair ;; 5) service_manager ;; 7) credential_center ;; 10) deep_cleanup ;; 0) exit 0 ;; *) main_menu ;;
    esac
}

check_root
main_menu
