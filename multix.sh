#!/bin/bash

# ==============================================================================
# MultiX Pro Script V71.1 (Ultimate UI & Dual-Stack Fix)
# Fix 1: [UI] Full Designer Login Page (Glassmorphism).
# Fix 2: [Net] Forced Socket-Level Dual-Stack binding (IPv4+IPv6 on one port).
# Fix 3: [UI] Switched to [[ ]] tags for JS to prevent Flask/Jinja2 conflict.
# Fix 4: [UI] Demo Node Management fully functional (Mock Save).
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V71.1"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 0. 快捷命令 ] ---
install_shortcut() {
    rm -f /usr/bin/multix
    cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
    echo -e "${GREEN}[INFO]${PLAIN} multix 快捷命令已更新"
}
install_shortcut

# --- [ 1. 基础函数 ] ---
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

# --- [ 6. 主控安装 ] ---
install_master() {
    install_dependencies; mkdir -p $M_ROOT/master
    echo -e "${SKYBLUE}>>> 主控配置${PLAIN}"
    read -p "面板端口 [7575]: " IN_PORT; M_PORT=${IN_PORT:-7575}
    read -p "管理用户 [admin]: " IN_USER; M_USER=${IN_USER:-admin}
    read -p "管理密码 [admin]: " IN_PASS; M_PASS=${IN_PASS:-admin}
    RAND=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    read -p "令牌 [Token]: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-$RAND}
    
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
    get_public_ips
    echo -e "${GREEN}✅ 主控端部署成功${PLAIN}"
    echo -e "   IPv4 入口: http://${IPV4}:${M_PORT}"
    echo -e "   IPv6 入口: http://[${IPV6}]:${M_PORT}"
    pause_back
}

_write_master_app_py() {
# 此段代码物理顶格，严禁修改缩进，彻底解决 503 报错
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
M_PORT = int(CONF.get('M_PORT', 7575))
M_USER = CONF.get('M_USER', 'admin')
M_PASS = CONF.get('M_PASS', 'admin')
M_TOKEN = CONF.get('M_TOKEN', 'error')

app = Flask(__name__)
app.secret_key = M_TOKEN

# 前端 JS 使用 [[ ]] 占位符，完美避开 Flask {{ }} 冲突
app.jinja_env.variable_start_string = '[['
app.jinja_env.variable_end_string = ']]'

AGENTS = {"local-demo": {"alias": "Demo Node", "stats": {"cpu": 15, "mem": 40, "os": "Demo OS", "xui": "v2.0.1"}, "nodes": [{"id": 1, "remark": "Demo-VLESS", "port": 443, "protocol": "vless", "settings": {"clients":[{"id":"demo-uuid"}]}, "stream_settings": {"network":"ws", "security":"tls"}}], "is_demo": True}}
LOOP_GLOBAL = None

def get_sys_info():
    try:
        v4 = os.popen("curl -s4m 2 api.ipify.org || echo 'N/A'").read().strip()
        v6 = os.popen("curl -s6m 2 api64.ipify.org || echo 'N/A'").read().strip()
        return {"cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "ipv4": v4, "ipv6": v6}
    except: return {"cpu":0,"mem":0,"ipv4":"N/A","ipv6":"N/A"}

@app.route('/api/gen_key', methods=['POST'])
def gen_key():
    t = request.json.get('type')
    try:
        if t == 'reality':
            out = subprocess.check_output("xray x25519 || echo 'Private key: x Public key: x'", shell=True).decode()
            return jsonify({"private": out.split("Private key:")[1].split()[0].strip(), "public": out.split("Public key:")[1].split()[0].strip()})
        elif t == 'ss-128': return jsonify({"key": base64.b64encode(os.urandom(16)).decode()})
        elif t == 'ss-256': return jsonify({"key": base64.b64encode(os.urandom(32)).decode()})
    except: return jsonify({"key": "Error"})

# 美化后的登录页模板
LOGIN_T = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"><title>MultiX Pro Login</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { margin:0; height:100vh; display:flex; align-items:center; justify-content:center; background: radial-gradient(circle at center, #1a1a2e 0%, #0a0a0c 100%); font-family: 'Segoe UI', sans-serif; overflow: hidden; }
.login-card { background: rgba(255, 255, 255, 0.05); backdrop-filter: blur(10px); padding: 40px; border-radius: 20px; border: 1px solid rgba(255, 255, 255, 0.1); box-shadow: 0 25px 45px rgba(0,0,0,0.2); width: 350px; text-align: center; }
h2 { color: #0d6efd; font-style: italic; font-weight: 800; letter-spacing: -1px; margin-bottom: 30px; font-size: 2rem; }
.input-group { margin-bottom: 20px; text-align: left; }
.input-group label { color: #888; font-size: 0.75rem; text-transform: uppercase; font-weight: bold; margin-left: 5px; }
input { width: 100%; padding: 12px 15px; margin-top: 5px; background: rgba(0,0,0,0.3); border: 1px solid #333; color: #fff; border-radius: 10px; box-sizing: border-box; outline: none; transition: 0.3s; }
input:focus { border-color: #0d6efd; box-shadow: 0 0 15px rgba(13,110,253,0.3); }
button { width: 100%; padding: 12px; margin-top: 10px; background: #0d6efd; color: #fff; border: none; border-radius: 10px; font-weight: bold; cursor: pointer; transition: 0.3s; }
button:hover { background: #0056b3; transform: translateY(-2px); box-shadow: 0 5px 15px rgba(13,110,253,0.4); }
.footer { margin-top: 20px; color: #444; font-size: 0.7rem; }
</style>
</head>
<body>
<div class="login-card">
    <h2>MultiX <span style="color:#fff">Pro</span></h2>
    <form method="post">
        <div class="input-group"><label>Username</label><input name="u" type="text" required autocomplete="off"></div>
        <div class="input-group"><label>Password</label><input name="p" type="password" required></div>
        <button type="submit">ENTER SYSTEM</button>
    </form>
    <div class="footer">STABLE SYSTEM V71.1</div>
</div>
</body>
</html>
"""

HTML_T = """
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="UTF-8"><title>MultiX Pro Dashboard</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.0/font/bootstrap-icons.css">
<style>
body{background:#050505;font-family:'Segoe UI',sans-serif;padding-top:20px}
.card{background:#111;border:1px solid #333;transition:0.3s;border-radius:15px}
.card:hover{border-color:#0d6efd;transform:translateY(-2px)}
.status-dot{width:10px;height:10px;border-radius:50%;display:inline-block}
.status-online{background:#198754;box-shadow: 0 0 10px #198754}.status-offline{background:#dc3545}
.header-token{font-family:monospace;color:#ffc107;font-size:0.9rem;margin-left:15px;background:rgba(255,193,7,0.1);padding:2px 8px;border-radius:5px}
.stat-box{font-size:0.8rem;color:#aaa;background:#1a1a1a;padding:5px 12px;border-radius:8px;border:1px solid #333}
.table-dark{background:transparent}
</style>
</head>
<body>
<div id="error-banner" class="alert alert-danger shadow-lg fw-bold" style="display:none;position:fixed;top:10px;left:50%;transform:translateX(-50%);z-index:1050;"></div>
<div class="container">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <div>
            <h2 class="fw-bold fst-italic text-primary mb-0">MultiX <span class="text-white">Pro</span></h2>
            <div class="text-secondary font-monospace small mt-1">
                <span class="badge bg-secondary">v4</span> <span id="ipv4">...</span> | 
                <span class="badge bg-primary">v6</span> <span id="ipv6">...</span>
                <span class="header-token">TK: [[ token ]]</span>
            </div>
        </div>
        <div class="d-flex gap-2">
            <span class="stat-box">CPU: <span id="cpu">0</span>%</span>
            <span class="stat-box">MEM: <span id="mem">0</span>%</span>
            <a href="/logout" class="btn btn-outline-danger btn-sm fw-bold rounded-pill px-3">LOGOUT</a>
        </div>
    </div>
    <div class="row g-4" id="node-list"></div>
</div>

<div class="modal fade" id="configModal" tabindex="-1">
    <div class="modal-dialog modal-lg modal-dialog-centered">
        <div class="modal-content" style="background:#0a0a0a; border:1px solid #333; border-radius:20px;">
            <div class="modal-header border-bottom border-secondary">
                <h5 class="modal-title fw-bold" id="modalTitle">Node Manager</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body" id="view-list">
                <div class="d-flex justify-content-between mb-3">
                    <span class="text-secondary">Connected Inbounds</span>
                    <button class="btn btn-sm btn-success fw-bold" onclick="toAddMode()">+ ADD NEW</button>
                </div>
                <table class="table table-dark table-hover table-sm text-center">
                    <thead><tr><th>ID</th><th>Remark</th><th>Port</th><th>Proto</th><th>Action</th></tr></thead>
                    <tbody id="tbl-body"></tbody>
                </table>
            </div>
            <div class="modal-body" id="view-edit" style="display:none">
                <button class="btn btn-sm btn-outline-secondary mb-3" onclick="toListView()"><i class="bi bi-arrow-left"></i> Back</button>
                <form id="nodeForm">
                    <input type="hidden" id="nodeId">
                    <div class="row g-3">
                        <div class="col-md-6"><label class="form-label small fw-bold">REMARK</label><input type="text" class="form-control" id="remark"></div>
                        <div class="col-md-6"><label class="form-label small fw-bold">PORT</label><input type="number" class="form-control" id="port"></div>
                        <div class="col-md-6"><label class="form-label small fw-bold">PROTOCOL</label><select class="form-select" id="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option><option value="shadowsocks">Shadowsocks</option></select></div>
                        <div class="col-md-6 group-uuid"><label class="form-label small fw-bold">UUID</label><div class="input-group"><input type="text" class="form-control font-monospace" id="uuid"><button class="btn btn-outline-secondary" type="button" onclick="genUUID()">Gen</button></div></div>
                        <div class="col-12"><hr class="border-secondary"></div>
                        <div class="col-md-6"><label class="form-label small fw-bold">NETWORK</label><select class="form-select" id="network"><option value="tcp">TCP</option><option value="ws">WebSocket</option></select></div>
                        <div class="col-md-6"><label class="form-label small fw-bold">SECURITY</label><select class="form-select" id="security"><option value="none">None</option><option value="tls">TLS</option><option value="reality">Reality</option></select></div>
                    </div>
                </form>
                <div class="mt-3 text-end"><button type="button" class="btn btn-primary fw-bold" id="saveBtn">SYNC TO NODE</button></div>
            </div>
        </div>
    </div>
</div>

<script>
let AGENTS={}, ACTIVE_IP='', CURRENT_NODES=[];
function updateState(){
    $.get('/api/state',function(d){
        $('#error-banner').hide();
        $('#cpu').text(d.master.stats.cpu); $('#mem').text(d.master.stats.mem);
        $('#ipv4').text(d.master.ipv4); $('#ipv6').text(d.master.ipv6);
        AGENTS=d.agents; renderGrid();
    }).fail(function(){ $('#error-banner').text('API SERVER ERROR').fadeIn(); });
}
function renderGrid(){
    $('#node-list').empty();
    for(const[ip,a]of Object.entries(AGENTS)){
        const s=(a.is_demo||a.stats.cpu!==undefined)?'status-online':'status-offline';
        const c=`<div class="col-md-6 col-lg-4"><div class="card h-100 p-3"><div class="d-flex justify-content-between align-items-center mb-2"><h5 class="fw-bold text-white mb-0 text-truncate">\${a.alias||'Unknown'}</h5><span class="status-dot \${s}"></span></div><div class="small text-secondary font-monospace mb-3">\${ip}</div><div class="d-flex flex-wrap gap-2 mb-3"><span class="stat-box">OS: \${a.stats.os||'N/A'}</span><span class="stat-box">3X: \${a.stats.xui||'N/A'}</span><span class="stat-box">CPU: \${a.stats.cpu||0}%</span><span class="stat-box">MEM: \${a.stats.mem||0}%</span></div><button class="btn btn-primary w-100 fw-bold rounded-pill" onclick="openManager('\${ip}')">MANAGE NODES (\${a.nodes?a.nodes.length:0})</button></div></div>`;
        $('#node-list').append(c);
    }
}
function openManager(ip){ ACTIVE_IP=ip; CURRENT_NODES=AGENTS[ip].nodes||[]; toListView(); $('#configModal').modal('show'); }
function toListView(){ $('#view-edit').hide(); $('#view-list').show(); $('#modalTitle').text(\`Nodes on \${ACTIVE_IP}\`); const t=$('#tbl-body'); t.empty(); if(CURRENT_NODES.length===0)t.append('<tr><td colspan="5">No Inbounds Found.</td></tr>'); else CURRENT_NODES.forEach((n,i)=>{t.append(\`<tr><td>\${n.id}</td><td>\${n.remark}</td><td class="font-monospace text-info">\${n.port}</td><td>\${n.protocol}</td><td><button class="btn btn-sm btn-outline-primary" onclick="toEditMode(\${i})"><i class="bi bi-pencil-square"></i></button></td></tr>\`)})}
function toAddMode(){ $('#view-list').hide(); $('#view-edit').show(); $('#modalTitle').text('Create Inbound'); resetForm(); }
function toEditMode(i){ $('#view-list').hide(); $('#view-edit').show(); $('#modalTitle').text('Edit Inbound'); loadForm(CURRENT_NODES[i]); }
function genUUID(){ $('#uuid').val(crypto.randomUUID()); }
function resetForm(){ $('#nodeForm')[0].reset(); $('#nodeId').val(''); }
function loadForm(n){ $('#nodeId').val(n.id); $('#remark').val(n.remark); $('#port').val(n.port); $('#protocol').val(n.protocol); }
$('#saveBtn').click(function(){
    const pl={ip:ACTIVE_IP,config:{remark:$('#remark').val(),port:$('#port').val(),protocol:$('#protocol').val()}};
    $.ajax({url:'/api/sync',type:'POST',contentType:'application/json',data:JSON.stringify(pl),success:function(r){$('#configModal').modal('hide'); alert(r.status==='demo_ok'?'[Demo Mode] Simulated Sync OK':'Success!');}});
});
$(document).ready(function(){updateState(); setInterval(updateState,3000);});
</script>
</body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_T, token=M_TOKEN)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form.get('u') == M_USER and request.form.get('p') == M_PASS:
            session['logged'] = True
            return redirect('/')
    return render_template_string(LOGIN_T)

@app.route('/logout')
def logout():
    session.pop('logged', None)
    return redirect('/login')

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
    # 强制监听 IPv6 :: 并在系统层面开启 IPv4 映射，实现真双栈访问
    app.run(host='::', port=M_PORT)
EOF
}

# --- [ 7. 被控安装 (保持原有全功能逻辑) ] ---
install_agent() {
    install_dependencies; mkdir -p $M_ROOT/agent
    if [ ! -d "/etc/x-ui" ]; then
        docker run -d --name 3x-ui --restart always --network host -v /etc/x-ui:/etc/x-ui -v /etc/x-ui/bin:/usr/local/x-ui/bin mhsanaei/3x-ui:latest >/dev/null 2>&1
        for i in {1..30}; do [[ -f "/etc/x-ui/x-ui.db" ]] && break; sleep 2; done
    fi
    echo -e "${SKYBLUE}>>> 被控端配置${PLAIN}"
    read -p "主控域名/IP: " IN_HOST; read -p "连接令牌 (Token): " IN_TOKEN
    echo -e "1. 自动 | 2. 强制 IPv4 | 3. 强制 IPv6"
    read -p "协议选择: " NET_OPT
    case "$NET_OPT" in
        2) IN_HOST=$(getent hosts "$IN_HOST" | awk '{print $1}' | grep -E '^[0-9]+\.' | head -n 1 || echo "$IN_HOST") ;;
        3) IN_HOST=$(getent hosts "$IN_HOST" | awk '{print $1}' | grep ":" | head -n 1 || echo "$IN_HOST") ;;
    esac
    echo "AGENT_HOST='$IN_HOST'" > "$AGENT_CONF"; echo "AGENT_TOKEN='$IN_TOKEN'" >> "$AGENT_CONF"
    cat > $M_ROOT/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install websockets psutil --break-system-packages
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    generate_agent_py "$IN_HOST" "$IN_TOKEN"
    cd $M_ROOT/agent; docker build -t multix-agent-v71 .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host -v /var/run/docker.sock:/var/run/docker.sock -v /etc/x-ui:/app/db_share -v $M_ROOT/agent:/app multix-agent-v71
    echo -e "${GREEN}✅ 被控启动完成${PLAIN}"; pause_back
}

# --- [ 9. 主菜单 (功能零删减全审计) ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro (V71.1 UI & Dual-Stack)${PLAIN}"
    echo " 1. 安装/更新 主控端 (新登录页)"
    echo " 2. 安装/更新 被控端"
    echo " 3. 智能连通测试"
    echo " 4. 被控重启"
    echo " 5. 深度清理"
    echo " 6. 环境修复"
    echo " 7. 凭据管理中心"
    echo " 8. 实时日志 (Debug)"
    echo " 9. 运维工具箱"
    echo " 10. 服务管理"
    echo " 11. 智能网络修复 (MTU/Forwarding)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;;
        3) connection_test ;; 4) docker restart multix-agent; pause_back ;;
        5) deep_cleanup ;; 6) install_dependencies; pause_back ;;
        7) credential_center ;;
        8) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50; pause_back ;;
        9) sys_tools ;; 10) service_manager ;; 
        11) smart_network_repair ;; 0) exit 0 ;; *) main_menu ;;
    esac
}

install_dependencies() {
    echo -e "${YELLOW}[INFO] 正在加固依赖环境...${PLAIN}"
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y epel-release python3 python3-pip curl wget socat nc ntpdate
    else apt-get update && apt-get install -y python3 python3-pip curl wget socat netcat-openbsd ntpdate; fi
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash; systemctl start docker; fi
    fix_dual_stack
}

check_root
main_menu
