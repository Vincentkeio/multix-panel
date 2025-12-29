#!/bin/bash

# ==============================================================================
# MultiX Pro Script V71.3 (FULL FUNCTIONAL RESTORATION)
# Restore 1: All Menu Options (1-11) fully restored from V68.0 & V70.x.
# Restore 2: Full UI assets, CSS, and JS logic for Node Management.
# Fix 1: [503] Absolute zero-indentation for Python block to fix Syntax errors.
# Fix 2: [Login] Designer Glassmorphism login page added.
# Fix 3: [Dual-Stack] IPv4 & IPv6 visibility and accessibility fixed.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V71.3"
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

# --- [ 2. 环境修复 ] ---
fix_dual_stack() {
    if grep -q "net.ipv6.bindv6only" /etc/sysctl.conf; then sed -i 's/net.ipv6.bindv6only.*/net.ipv6.bindv6only = 0/' /etc/sysctl.conf
    else echo "net.ipv6.bindv6only = 0" >> /etc/sysctl.conf; fi
    sysctl -p >/dev/null 2>&1
}

fix_apt_sources() {
    if ! apt-get update -y >/dev/null 2>&1; then
        apt-get update --allow-releaseinfo-change >/dev/null 2>&1
        if grep -q "bullseye-backports" /etc/apt/sources.list; then
            sed -i '/bullseye-backports/s/^/#/' /etc/apt/sources.list
            sed -i '/bullseye-backports/s/^/#/' /etc/apt/sources.list.d/*.list 2>/dev/null
        fi
        apt-get update -y
    fi
}

install_dependencies() {
    echo -e "${YELLOW}[INFO]${PLAIN} 检查并安装依赖..."
    check_sys
    if [[ "${RELEASE}" == "debian" || "${RELEASE}" == "ubuntu" ]]; then
        fix_apt_sources
        apt-get install -y python3 python3-pip curl wget socat tar openssl git netcat-openbsd ntpdate
    elif [[ "${RELEASE}" == "centos" ]]; then 
        yum install -y epel-release python3 python3-devel python3-pip curl wget socat tar openssl git nc ntpdate
    fi
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1 || \
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" >/dev/null 2>&1
    if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash; systemctl start docker; fi
    fix_dual_stack
}

# --- [ 3. 深度清理 ] ---
deep_cleanup() {
    echo -e "${RED}⚠️  警告：此操作将删除所有 MultiX 组件！${PLAIN}"; read -p "确认? [y/N]: " confirm
    [[ "$confirm" != "y" ]] && return
    systemctl stop multix-master 2>/dev/null
    systemctl disable multix-master 2>/dev/null
    rm -f /etc/systemd/system/multix-master.service
    systemctl daemon-reload
    docker stop multix-agent 3x-ui 2>/dev/null; docker rm -f multix-agent 3x-ui 2>/dev/null
    pkill -9 -f "master/app.py"; pkill -9 -f "agent/agent.py"
    rm -rf "$M_ROOT"
    echo -e "${GREEN}[INFO]${PLAIN} 清理完成"; pause_back
}

# --- [ 4. 服务管理 ] ---
service_manager() {
    while true; do
        clear; echo -e "${SKYBLUE}⚙️ 服务管理${PLAIN}"
        echo " 1. 启动 主控端"
        echo " 2. 停止 主控端"
        echo " 3. 重启 主控端"
        echo " 4. 查看 主控状态"
        echo "----------------"
        echo " 5. 重启 被控端 (Agent)"
        echo " 6. 查看 被控日志 (Debug)"
        echo " 0. 返回"
        read -p "选择: " s
        case $s in
            1) systemctl start multix-master && echo "Done" ;; 2) systemctl stop multix-master && echo "Done" ;;
            3) systemctl restart multix-master && echo "Done" ;; 4) systemctl status multix-master -l --no-pager ;;
            5) docker restart multix-agent && echo "Done" ;; 6) docker logs multix-agent --tail 50 ;; 0) break ;;
        esac; read -n 1 -s -r -p "继续..."
    done; main_menu
}

# --- [ 5. 凭据管理中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 凭据管理中心 (V71.3)${PLAIN}"
    if [ -f $M_ROOT/.env ]; then
        M_T=$(grep 'M_TOKEN=' $M_ROOT/.env | cut -d"'" -f2)
        M_P=$(grep 'M_PORT=' $M_ROOT/.env | cut -d"'" -f2)
        M_U=$(grep 'M_USER=' $M_ROOT/.env | cut -d"'" -f2)
        M_W=$(grep 'M_PASS=' $M_ROOT/.env | cut -d"'" -f2)
        get_public_ips
        echo -e "${YELLOW}>>> 主控管理入口 <<<${PLAIN}"
        [[ "$IPV4" != "N/A" ]] && echo -e "IPv4 入口: ${GREEN}http://${IPV4}:${M_P}${PLAIN}"
        [[ "$IPV6" != "N/A" ]] && echo -e "IPv6 入口: ${GREEN}http://[${IPV6}]:${M_P}${PLAIN}"
        echo -e "用户: ${SKYBLUE}${M_U}${PLAIN} | 密码: ${SKYBLUE}${M_W}${PLAIN} | Token: ${YELLOW}${M_T}${PLAIN}"
    fi
    AGENT_HOST="未配置"; AGENT_TOKEN="未配置"
    if [ -f "$AGENT_CONF" ]; then 
        AGENT_HOST=$(grep 'AGENT_HOST=' "$AGENT_CONF" | cut -d"'" -f2)
        AGENT_TOKEN=$(grep 'AGENT_TOKEN=' "$AGENT_CONF" | cut -d"'" -f2)
    fi
    echo -e "\n${YELLOW}>>> 被控端 (Agent) 配置 <<<${PLAIN}"
    echo -e "连接目标: ${GREEN}${AGENT_HOST}${PLAIN} | 令牌: ${SKYBLUE}${AGENT_TOKEN}${PLAIN}"
    echo "--------------------------------"
    echo " 1. 修改主控配置 | 2. 修改被控连接 | 0. 返回"
    read -p "选择: " c
    if [[ "$c" == "1" ]]; then
        read -p "新端口: " np; M_PORT=${np:-$M_P}
        read -p "新Token: " nt; M_TOKEN=${nt:-$M_T}
        echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
        systemctl restart multix-master
    elif [[ "$c" == "2" ]]; then
        read -p "新主控目标: " nh; AGENT_HOST=${nh:-$AGENT_HOST}
        read -p "新令牌: " ntk; AGENT_TOKEN=${ntk:-$AGENT_TOKEN}
        echo "AGENT_HOST='$AGENT_HOST'" > "$AGENT_CONF"; echo "AGENT_TOKEN='$AGENT_TOKEN'" >> "$AGENT_CONF"
        if [ -d "$M_ROOT/agent" ]; then generate_agent_py "$AGENT_HOST" "$AGENT_TOKEN"; docker restart multix-agent; fi
    fi
    pause_back
}

# --- [ 11. 智能修复 ] ---
smart_network_repair() {
    echo -e "\n${YELLOW}🔧 正在执行智能网络修复...${PLAIN}"
    ip link set dev eth0 mtu 1280 2>/dev/null
    ip link set dev ens3 mtu 1280 2>/dev/null
    ntpdate pool.ntp.org >/dev/null 2>&1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}✅ 修复完成！${PLAIN}"; pause_back
}

connection_test() {
    echo -e "${SKYBLUE}📡 智能连通性测试${PLAIN}"
    if [ -f "$AGENT_CONF" ]; then
        AGENT_HOST=$(grep 'AGENT_HOST=' "$AGENT_CONF" | cut -d"'" -f2)
        AGENT_TOKEN=$(grep 'AGENT_TOKEN=' "$AGENT_CONF" | cut -d"'" -f2)
    else
        read -p "IP/Domain: " AGENT_HOST; read -p "Token: " AGENT_TOKEN
    fi
    [ -z "$AGENT_HOST" ] && return
    nc -zv -w 5 "$AGENT_HOST" 8888
    if [ $? -ne 0 ]; then echo -e "${RED}[FAIL] TCP 连接失败${PLAIN}"; else echo -e "${GREEN}[PASS] TCP 正常${PLAIN}"; fi
    pause_back
}

# --- [ 辅助：生成 Agent 代码 ] ---
generate_agent_py() {
    local host=$1; local token=$2
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket, platform, time
MASTER = "$host"; TOKEN = "$token"; DB_PATH = "/app/db_share/x-ui.db"
def log(msg): print(f"[Agent] {msg}", flush=True)
def get_xui_ver(): return "Installed" if os.path.exists(DB_PATH) else "Not Found"
def smart_sync_db(data):
    try:
        if not os.path.exists(DB_PATH): log("DB missing"); return False
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor(); cursor.execute("PRAGMA table_info(inbounds)")
        cols = [info[1] for info in cursor.fetchall()]
        base = {'user_id':1,'up':0,'down':0,'total':0,'remark':data['remark'],'enable':1,'expiry_time':0,'listen':'','port':data['port'],'protocol':data['protocol'],'settings':data['settings'],'stream_settings':data['stream_settings'],'tag':'multix','sniffing':data.get('sniffing','{}')}
        valid = {k: v for k, v in base.items() if k in columns}
        nid = data.get('id')
        if nid:
            set_c = ", ".join([f"{k}=?" for k in valid.keys()])
            cursor.execute(f"UPDATE inbounds SET {set_c} WHERE id=?", list(valid.values()) + [nid])
        else:
            keys = ", ".join(valid.keys()); ph = ", ".join(["?"]*len(valid))
            cursor.execute(f"INSERT INTO inbounds ({keys}) VALUES ({ph})", list(valid.values()))
        conn.commit(); conn.close(); return True
    except Exception as e: log(f"DB Error: {e}"); return False
async def run():
    target = MASTER
    if ":" in target and not target.startswith("[") and not target[0].isalpha(): target = f"[{target}]"
    uri = f"ws://{target}:8888"
    while True:
        try:
            async with websockets.connect(uri, ping_interval=20, open_timeout=20) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()),"mem":int(psutil.virtual_memory().percent),"os":platform.system(),"xui":get_xui_ver()}
                    nodes = []
                    if os.path.exists(DB_PATH):
                        try:
                            conn = sqlite3.connect(DB_PATH); cur = conn.cursor()
                            cur.execute("SELECT id,remark,port,protocol,settings,stream_settings FROM inbounds")
                            for r in cur.fetchall(): nodes.append({"id":r[0],"remark":r[1],"port":r[2],"protocol":r[3],"settings":json.loads(r[4]),"stream_settings":json.loads(r[5])})
                            conn.close()
                        except: pass
                    await ws.send(json.dumps({"type":"heartbeat","data":stats,"nodes":nodes}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5); task = json.loads(msg)
                        if task.get('action') == 'sync_node': os.system("docker restart 3x-ui"); smart_sync_db(task['data']); os.system("docker restart 3x-ui")
                    except: continue
        except Exception as e: log(f"Fail: {e}"); await asyncio.sleep(5)
asyncio.run(run())
EOF
}

# --- [ 6. 主控安装 ] ---
install_master() {
    install_dependencies; mkdir -p $M_ROOT/master
    echo -e "${SKYBLUE}>>> 主控配置${PLAIN}"
    read -p "端口 [7575]: " IN_PORT; M_PORT=${IN_PORT:-7575}
    read -p "管理用户 [admin]: " IN_USER; M_USER=${IN_USER:-admin}
    read -p "管理密码 [admin]: " IN_PASS; M_PASS=${IN_PASS:-admin}
    read -p "令牌 [随机]: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
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

# --- [ 核心业务逻辑写入 ] ---
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
        v4 = os.popen("curl -s4 api.ipify.org || echo 'N/A'").read().strip()
        v6 = os.popen("curl -s6 api64.ipify.org || echo 'N/A'").read().strip()
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
LOGIN_T = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Login</title><style>
body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0c;font-family:sans-serif;color:#fff}
.box{background:rgba(255,255,255,0.05);backdrop-filter:blur(10px);padding:40px;border-radius:20px;border:1px solid rgba(255,255,255,0.1);width:320px;text-align:center}
h2{color:#0d6efd;font-style:italic;margin-bottom:30px}
input{width:100%;padding:12px;margin:10px 0;background:rgba(0,0,0,0.3);border:1px solid #333;color:#fff;border-radius:8px;box-sizing:border-box;outline:none}
button{width:100%;padding:12px;background:#0d6efd;color:#fff;border:none;border-radius:8px;font-weight:bold;cursor:pointer;margin-top:10px}
</style></head><body><div class="box"><h2>MultiX Pro</h2><form method="post"><input name="u" placeholder="User"><input name="p" type="password" placeholder="Pass"><button type="submit">LOGIN</button></form></div></body></html>
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
<div class="d-flex gap-2"><span class="stat-box">CPU: <span id="cpu">0</span>%</span><span class="stat-box">MEM: <span id="mem">0</span>%</span><a href="/logout" class="btn btn-outline-danger btn-sm">LOGOUT</a></div>
</div>
<div class="row g-4" id="node-list"></div>
</div>
<div class="modal fade" id="configModal" tabindex="-1"><div class="modal-dialog modal-lg modal-dialog-centered"><div class="modal-content" style="background:#0a0a0a;border:1px solid #333;border-radius:20px"><div class="modal-header"><h5>Node Management</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body" id="view-list"><div class="d-flex justify-content-between mb-3"><span>Inbound Nodes</span><button class="btn btn-sm btn-success" onclick="toAddMode()">+ Add Node</button></div><table class="table table-dark text-center"><thead><tr><th>Remark</th><th>Port</th><th>Protocol</th><th>Action</th></tr></thead><tbody id="tbl-body"></tbody></table></div><div class="modal-body" id="view-edit" style="display:none"><button class="btn btn-sm btn-link" onclick="toListView()">Back</button><form id="nodeForm"><div class="row g-3"><div class="col-6"><label>Remark</label><input class="form-control" id="remark"></div><div class="col-6"><label>Port</label><input class="form-control" type="number" id="port"></div><div class="col-12"><label>Protocol</label><select class="form-select" id="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option><option value="shadowsocks">Shadowsocks</option></select></div></div></form><button class="btn btn-primary w-100 mt-4" id="saveBtn">SYNC TO NODE</button></div></div></div></div>
<script>
let AGENTS={},ACTIVE_IP='',CURRENT_NODES=[];
function updateState(){$.get('/api/state',function(d){$('#cpu').text(d.master.stats.cpu);$('#mem').text(d.master.stats.mem);$('#ipv4').text(d.master.ipv4);$('#ipv6').text(d.master.ipv6);AGENTS=d.agents;renderGrid()}).fail(function(){$('#error-banner').text('API Fail').show()})}
function renderGrid(){$('#node-list').empty();for(const[ip,a]of Object.entries(AGENTS)){const c=\`<div class="col-md-4"><div class="card p-3"><div class="d-flex justify-content-between"><h5>\${a.alias}</h5><span class="status-dot"></span></div><div class="small text-secondary mb-3">\${ip}</div><div class="d-flex gap-2 mb-3"><span class="stat-box">OS: \${a.stats.os}</span><span class="stat-box">CPU: \${a.stats.cpu}%</span></div><button class="btn btn-primary w-100" onclick="openManager('\${ip}')">MANAGE NODES (\${a.nodes?a.nodes.length:0})</button></div></div>\`;$('#node-list').append(c)}}
function openManager(ip){ACTIVE_IP=ip;CURRENT_NODES=AGENTS[ip].nodes||[];toListView();$('#configModal').modal('show')}
function toListView(){$('#view-edit').hide();$('#view-list').show();const t=$('#tbl-body');t.empty();CURRENT_NODES.forEach((n,i)=>{t.append(\`<tr><td>\${n.remark}</td><td>\${n.port}</td><td>\${n.protocol}</td><td><button class="btn btn-sm btn-link" onclick="toEditMode(\${i})">Edit</button></td></tr>\`)})}
function toAddMode(){$('#view-list').hide();$('#view-edit').show();$('#nodeForm')[0].reset()}
function toEditMode(i){$('#view-list').hide();$('#view-edit').show();const n=CURRENT_NODES[i];$('#remark').val(n.remark);$('#port').val(n.port);$('#protocol').val(n.protocol)}
$('#saveBtn').click(function(){$.ajax({url:'/api/sync',type:'POST',contentType:'application/json',data:JSON.stringify({ip:ACTIVE_IP,config:{remark:$('#remark').val(),port:$('#port').val(),protocol:$('#protocol').val()}}),success:function(r){$('#configModal').modal('hide');alert('Sync OK');}})});
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
    async def m(): await websockets.serve(ws_handler, "0.0.0.0", 8888)
    LOOP_GLOBAL.run_until_complete(m())
if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=M_PORT)
EOF
}

# --- [ 7. 被控安装 ] ---
install_agent() {
    install_dependencies; mkdir -p $M_ROOT/agent
    if [ ! -d "/etc/x-ui" ]; then
        docker run -d --name 3x-ui --restart always --network host -v /etc/x-ui:/etc/x-ui -v /etc/x-ui/bin:/usr/local/x-ui/bin mhsanaei/3x-ui:latest >/dev/null 2>&1
        for i in {1..30}; do [[ -f "/etc/x-ui/x-ui.db" ]] && break; sleep 2; done
    fi
    echo -e "${SKYBLUE}>>> 被控端配置${PLAIN}"
    read -p "主控域名/IP: " IN_HOST; read -p "连接令牌 (Token): " IN_TOKEN
    echo -e "1. 自动 | 2. 强制 IPv4 | 3. 强制 IPv6"
    read -p "选择: " NET_OPT
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

# --- [ 8. 运维工具箱 ] ---
sys_tools() {
    while true; do
        clear; echo -e "${SKYBLUE}🧰 运维工具箱${PLAIN}"
        echo " 1. 安装/重置 3X-UI (Docker版)"
        echo " 2. 重置 3X-UI 面板账号"
        echo " 3. 清空节点总流量统计"
        echo " 4. 彻底清理 MultiX 组件"
        echo " 0. 返回"
        read -p "选择: " t
        case $t in
            1) bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) ;;
            2) docker exec -it 3x-ui x-ui setting ;;
            3) sqlite3 $M_ROOT/agent/db_data/x-ui.db "UPDATE client_traffics SET up=0, down=0;" && echo "已清空" ;;
            4) deep_cleanup ;;
            0) break ;;
        esac; read -n 1 -s -r -p "继续..."
    done; main_menu
}

# --- [ 9. 主菜单 (全量还原) ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro (V71.3 FULL RESTORED)${PLAIN}"
    echo " 1. 安装/更新 主控端 (设计师 UI)"
    echo " 2. 安装/更新 被控端 (Agent)"
    echo " 3. 智能连通测试"
    echo " 4. 服务管理 (启动/停止/重启)"
    echo " 5. 凭据管理中心 (修改端口/Token)"
    echo " 6. 环境修复 & 依赖加固"
    echo " 7. 实时系统日志 (Debug)"
    echo " 8. 运维工具箱 (3X-UI 管理)"
    echo " 9. 智能网络修复 (MTU/Forwarding)"
    echo " 10. 深度清理所有组件"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;;
        3) connection_test ;; 4) service_manager ;;
        5) credential_center ;; 6) install_dependencies; pause_back ;;
        7) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50; pause_back ;;
        8) sys_tools ;; 9) smart_network_repair ;; 
        10) deep_cleanup ;; 0) exit 0 ;; *) main_menu ;;
    esac
}

check_root
main_menu
