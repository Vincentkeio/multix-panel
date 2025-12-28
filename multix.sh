#!/bin/bash

# ==============================================================================
# MultiX Cluster Manager - v10.1 (Ultimate Design)
# Designed for High-End VPS Management
# ==============================================================================

# --- Global Config ---
APP_DIR="/opt/multix_docker"
DEFAULT_MASTER_PORT=7575
DEFAULT_XUI_PORT=2053
DEFAULT_TOKEN="multix_secret_888"

# --- Design Colors ---
RED='\033[38;5;196m'
GREEN='\033[38;5;46m'
YELLOW='\033[38;5;226m'
BLUE='\033[38;5;39m'
MAGENTA='\033[38;5;201m'
CYAN='\033[38;5;51m'
GRAY='\033[38;5;240m'
WHITE='\033[38;5;255m'
BOLD='\033[1m'
PLAIN='\033[0m'

# --- Helpers ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}⚡ Installing Docker Engine...${PLAIN}"
        curl -fsSL https://get.docker.com | bash >/dev/null 2>&1
        systemctl start docker; systemctl enable docker
    fi
    if ! docker compose version &> /dev/null; then
        apt-get install -y docker-compose-plugin 2>/dev/null || yum install -y docker-compose-plugin 2>/dev/null
    fi
}

get_status() {
    # Master Status
    if docker ps --format '{{.Names}}' | grep -q "^multix-master$"; then
        M_STATE="${GREEN}● Running${PLAIN}"
        M_MEM=$(docker stats --no-stream --format "{{.MemUsage}}" multix-master | awk -F'/' '{print $1}')
    else
        M_STATE="${GRAY}○ Stopped${PLAIN}"
        M_MEM="0B"
    fi

    # Agent Status
    if docker ps --format '{{.Names}}' | grep -q "^multix-agent$"; then
        A_STATE="${GREEN}● Running${PLAIN}"
        A_MEM=$(docker stats --no-stream --format "{{.MemUsage}}" multix-agent | awk -F'/' '{print $1}')
    else
        A_STATE="${GRAY}○ Stopped${PLAIN}"
        A_MEM="0B"
    fi
}

# ==================================================
# 1. Install Master
# ==================================================
install_master() {
    check_docker
    clear
    echo -e "${MAGENTA}====================================================${PLAIN}"
    echo -e "${BOLD}   Deploy Master Server (Dashboard Edition)${PLAIN}"
    echo -e "${MAGENTA}====================================================${PLAIN}"
    
    # Clean up old container forcefully
    if docker ps -a | grep -q multix-master; then
        echo -e "${YELLOW}♻️  Cleaning up old Master container...${PLAIN}"
        docker rm -f multix-master >/dev/null 2>&1
    fi

    echo -e "\n${BOLD}🔐 Security Setup${PLAIN}"
    echo -e "${GRAY}Set a Cluster Token to prevent unauthorized Agent connections.${PLAIN}"
    read -p "Token [Default: ${DEFAULT_TOKEN}]: " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/master
    cd ${APP_DIR}/master

    # Server Code (With Dashboard & API)
    cat > server.py <<EOF
import json, os, socket, psutil
from flask import Flask, render_template_string, request, jsonify
from flask_sock import Sock

app = Flask(__name__)
sock = Sock(app)
PORT = int(os.getenv('MASTER_PORT', 7575))
TOKEN = os.getenv('CLUSTER_TOKEN', 'default')

clients = {}
client_info = {}

def get_master_stats():
    return {'cpu': psutil.cpu_percent(interval=None),'mem': psutil.virtual_memory().percent}

@sock.route('/ws')
def websocket(ws):
    agent_id = None
    try:
        data = ws.receive()
        info = json.loads(data)
        if info.get('token') != TOKEN:
            ws.send(json.dumps({'error': 'Auth Failed'}))
            return
        
        agent_id = info.get('uuid')
        conn_ip = request.remote_addr
        if info.get('report_ip'): conn_ip = info.get('report_ip')
        info['conn_ip'] = conn_ip
        clients[agent_id] = ws
        client_info[agent_id] = info

        while True:
            msg = ws.receive()
            try:
                stats = json.loads(msg)
                if 'cpu' in stats: client_info[agent_id].update(stats)
            except: pass
    except: pass
    finally:
        if agent_id and agent_id in clients:
            del clients[agent_id]
            del client_info[agent_id]

@app.route('/api/stats')
def api_stats(): return jsonify({'master': get_master_stats(), 'agents': client_info})

@app.route('/api/push', methods=['POST'])
def push():
    tid = request.json.get('target_uuid')
    if tid not in clients: return jsonify({'success': False, 'msg': 'Agent Offline'})
    try:
        clients[tid].send(json.dumps({'action': 'add_node', 'data': request.json.get('config')}))
        return jsonify(json.loads(clients[tid].receive(timeout=10)))
    except Exception as e: return jsonify({'success': False, 'msg': str(e)})

@app.route('/api/keys', methods=['POST'])
def get_keys():
    tid = request.json.get('target_uuid')
    if tid not in clients: return jsonify({'success': False, 'msg': 'Agent Offline'})
    try:
        clients[tid].send(json.dumps({'action': 'get_keys'}))
        return jsonify(json.loads(clients[tid].receive(timeout=10)))
    except Exception as e: return jsonify({'success': False, 'msg': str(e)})

@app.route('/api/cert', methods=['POST'])
def apply_cert():
    tid = request.json.get('target_uuid')
    domain = request.json.get('domain')
    if tid not in clients: return jsonify({'success': False, 'msg': 'Agent Offline'})
    try:
        clients[tid].send(json.dumps({'action': 'apply_cert', 'domain': domain}))
        return jsonify(json.loads(clients[tid].receive(timeout=60)))
    except Exception as e: return jsonify({'success': False, 'msg': str(e)})

@app.route('/api/rename', methods=['POST'])
def rename():
    tid = request.json.get('uuid')
    name = request.json.get('name')
    if tid in client_info: client_info[tid]['name'] = name
    return jsonify({'success': True})

HTML_TEMPLATE = """
<!DOCTYPE html><html lang="en" data-bs-theme="dark"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>MultiX Dashboard</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
:root{--bg-body:#0f172a;--bg-card:#1e293b;--text-main:#f8fafc;--primary:#3b82f6}
body{background-color:var(--bg-body);color:var(--text-main);font-family:'Inter',sans-serif}
.navbar{background:rgba(30,41,59,0.9);backdrop-filter:blur(10px);border-bottom:1px solid rgba(255,255,255,0.05)}
.card{background:var(--bg-card);border:1px solid rgba(255,255,255,0.05);border-radius:12px;box-shadow:0 4px 6px -1px rgba(0,0,0,0.1)}
.status-indicator{width:10px;height:10px;border-radius:50%;display:inline-block;margin-right:6px}
.online{background-color:#22c55e;box-shadow:0 0 8px rgba(34,197,94,0.4)}
.btn-glass{background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);color:#fff}
.btn-glass:hover{background:rgba(255,255,255,0.1)}
</style>
</head><body>
<nav class="navbar navbar-expand-lg navbar-dark sticky-top px-4 py-3">
  <div class="d-flex w-100 justify-content-between align-items-center">
    <div class="d-flex align-items-center gap-3"><span class="fs-5 fw-bold"><i class="bi bi-grid-fill text-primary"></i> MultiX</span><span class="badge bg-primary bg-opacity-10 text-primary border border-primary border-opacity-25">v10.1 Pro</span></div>
    <div class="d-flex align-items-center gap-3"><div class="text-end d-none d-md-block" style="line-height:1.2"><small class="d-block text-muted" style="font-size:0.75rem">MASTER LOAD</small><span class="fw-bold text-success" id="m_cpu">CPU 0%</span></div><button class="btn btn-sm btn-glass" onclick="toggleLang()" id="langBtn">🇺🇸 EN / 🇨🇳 CN</button></div>
  </div>
</nav>
<div class="container py-4">
    <div class="row g-4 mb-4">
        <div class="col-6 col-md-3"><div class="card p-3 h-100 d-flex flex-column justify-content-center align-items-center"><h3 class="fw-bold mb-0" id="stat_total">0</h3><small class="text-muted" data-t="total">Total Agents</small></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 h-100 d-flex flex-column justify-content-center align-items-center"><h3 class="fw-bold text-success mb-0" id="stat_online">0</h3><small class="text-success" data-t="online">Online</small></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 h-100 d-flex flex-column justify-content-center align-items-center"><h3 class="fw-bold text-info mb-0" id="stat_v4">0</h3><small class="text-info">IPv4 Nodes</small></div></div>
        <div class="col-6 col-md-3"><div class="card p-3 h-100 d-flex flex-column justify-content-center align-items-center"><h3 class="fw-bold text-warning mb-0" id="stat_v6">0</h3><small class="text-warning">IPv6 Nodes</small></div></div>
    </div>
    <div class="d-flex justify-content-between align-items-center mb-3"><h5 class="fw-bold mb-0"><i class="bi bi-hdd-stack"></i> <span data-t="list">Managed Servers</span></h5><button class="btn btn-sm btn-glass" onclick="ref()"><i class="bi bi-arrow-clockwise"></i></button></div>
    <div class="row g-4" id="list"></div>
</div>
<div class="modal fade" id="addModal"><div class="modal-dialog modal-dialog-centered"><div class="modal-content" style="background:var(--bg-card)"><div class="modal-header border-0"><h5 class="modal-title fw-bold" data-t="add">Add Node</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body"><form id="f"><input type="hidden" id="tuuid"><div class="form-floating mb-2"><input class="form-control bg-dark text-white border-secondary" name="remark" value="Node-1"><label>Remark</label></div><div class="row g-2 mb-2"><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option></select><label>Protocol</label></div></div><div class="col"><div class="form-floating"><input type="number" class="form-control bg-dark text-white border-secondary" name="port" placeholder="Port"><label>Port</label></div></div></div><div class="form-floating mb-2"><input class="form-control bg-dark text-white border-secondary" name="uuid" id="uid"><label>UUID</label><button type="button" class="btn btn-sm btn-link position-absolute end-0 top-50 translate-middle-y text-decoration-none" onclick="genUUID()"><i class="bi bi-magic"></i></button></div><div class="form-floating mb-2"><select class="form-select bg-dark text-white border-secondary" name="listen"><option value="">🌐 Dual Stack (v4+v6)</option><option value="0.0.0.0">4️⃣ IPv4 Only</option><option value="::">6️⃣ IPv6 Only</option></select><label data-t="listen">Listen Interface</label></div><div class="row g-2 mb-2"><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="network" id="net" onchange="up()"><option value="tcp">TCP</option><option value="ws">WS</option></select><label>Network</label></div></div><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="security" id="sec" onchange="up()"><option value="none">None</option><option value="reality">REALITY</option><option value="tls">TLS</option></select><label>Security</label></div></div></div><div id="ws" class="d-none mb-2"><input class="form-control bg-dark text-white border-secondary" name="ws_path" placeholder="WS Path"></div><div id="rea" class="d-none mb-2 p-3 border border-secondary border-opacity-25 rounded bg-black bg-opacity-25"><div class="d-flex justify-content-between mb-2"><span class="text-warning small">REALITY</span> <button class="btn btn-sm btn-outline-warning py-0" type="button" onclick="getRealKeys()">Auto Gen Keys</button></div><input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_dest" value="www.microsoft.com:443"><input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_sni" value="www.microsoft.com"><input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_pk" id="r_pk" placeholder="PK" readonly><input class="form-control form-control-sm bg-dark text-white" name="reality_sk" id="r_sk" placeholder="SK" readonly></div></form></div><div class="modal-footer border-0"><button class="btn btn-primary w-100 py-2 fw-bold" onclick="sub()" data-t="save">Deploy & Get Link</button></div></div></div></div>
<div class="modal fade" id="resModal"><div class="modal-dialog modal-dialog-centered"><div class="modal-content" style="background:var(--bg-card)"><div class="modal-header border-0"><h5 class="modal-title">Result</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body text-center"><div class="bg-white p-3 d-inline-block rounded mb-3"><div id="qrcode"></div></div><div class="input-group"><input class="form-control bg-dark text-white border-secondary" id="link_txt" readonly><button class="btn btn-success" onclick="copyLink()"><i class="bi bi-clipboard"></i></button></div></div></div></div>
<script>
const m=new bootstrap.Modal('#addModal'), rm=new bootstrap.Modal('#resModal');
let currId='', lang='en';
const T={en:{add:'Add Node',save:'Deploy & Get Link',listen:'Listen IP',list:'Managed Servers',total:'Total',online:'Online'},cn:{add:'添加节点',save:'部署并获取链接',listen:'监听接口',list:'被控服务器列表',total:'节点总数',online:'在线数量'}};
function toggleLang(){lang=lang==='en'?'cn':'en';document.querySelectorAll('[data-t]').forEach(e=>e.innerText=T[lang][e.dataset.t])}
const toast=Swal.mixin({toast:true,position:'top-end',showConfirmButton:false,timer:3000,timerProgressBar:true,background:'#1e293b',color:'#fff'});
function ref(){fetch('/api/stats').then(r=>r.json()).then(d=>{document.getElementById('m_cpu').innerText=\`CPU \${d.master.cpu}%\`;const l=document.getElementById('list'), r=d.agents;l.innerHTML=''; let c=0,v4=0,v6=0;for(let u in r){c++;let tags='';if(r[u].ipv4&&r[u].ipv6)tags+='<span class="badge bg-success bg-opacity-25 text-success border border-success border-opacity-25 me-1">Dual</span>';else if(r[u].ipv6){tags+='<span class="badge bg-warning bg-opacity-25 text-warning border border-warning border-opacity-25 me-1">v6</span>';v6++}else{tags+='<span class="badge bg-info bg-opacity-25 text-info border border-info border-opacity-25 me-1">v4</span>';v4++}let conn=r[u].conn_ip.includes(':')?'via IPv6':'via IPv4';let cpu=r[u].cpu||0,mem=r[u].mem||0;l.innerHTML+=\`<div class="col-md-6 col-lg-4"><div class="card h-100"><div class="card-body"><div class="d-flex justify-content-between align-items-start mb-3"><div><h5 class="fw-bold mb-1" style="cursor:pointer" onclick="ren('\${u}')">\${r[u].name} <i class="bi bi-pencil-fill text-muted fs-6 opacity-50"></i></h5><div class="d-flex align-items-center"><span class="status-indicator online"></span><span class="small text-muted">\${r[u].ip}</span></div></div><span class="badge bg-secondary bg-opacity-25 text-secondary">\${conn}</span></div><div class="mb-3">\${tags}</div><div class="mb-2"><div class="d-flex justify-content-between small mb-1"><span>CPU</span><span>\${cpu}%</span></div><div class="progress"><div class="progress-bar bg-primary" style="width:\${cpu}%"></div></div></div><div><div class="d-flex justify-content-between small mb-1"><span>RAM</span><span>\${mem}%</span></div><div class="progress"><div class="progress-bar bg-info" style="width:\${mem}%"></div></div></div></div><div class="card-footer bg-transparent border-top border-secondary border-opacity-10 p-3 d-flex gap-2"><button class="btn btn-sm btn-primary flex-grow-1 fw-bold" onclick="pop('\${u}')"><i class="bi bi-plus-lg"></i> Node</button><button class="btn btn-sm btn-outline-light" onclick="cert('\${u}')" title="SSL"><i class="bi bi-shield-check"></i></button><a href="http://\${r[u].ip}:\${r[u].xp||2053}" target="_blank" class="btn btn-sm btn-glass"><i class="bi bi-box-arrow-up-right"></i> Panel</a></div></div></div>\`;}document.getElementById('stat_total').innerText=c;document.getElementById('stat_online').innerText=c;document.getElementById('stat_v4').innerText=v4;document.getElementById('stat_v6').innerText=v6;if(c===0)l.innerHTML='<div class="col-12 text-center text-muted py-5">Waiting for agents...</div>'})}
function pop(u){currId=u;document.getElementById('tuuid').value=u;document.getElementById('uid').value=crypto.randomUUID();up();m.show()}
function ren(u){Swal.fire({title:'Rename',input:'text',background:'#1e293b',color:'#fff',showCancelButton:true}).then((r)=>{if(r.value)fetch('/api/rename',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({uuid:u,name:r.value})}).then(()=>{toast.fire({icon:'success'});ref()})})}
function cert(u){Swal.fire({title:'Domain',input:'text',background:'#1e293b',color:'#fff',showCancelButton:true}).then((r)=>{if(r.value){Swal.fire({title:'Applying...',timer:60000,didOpen:()=>{Swal.showLoading()},background:'#1e293b',color:'#fff'});fetch('/api/cert',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:u,domain:r.value})}).then(res=>res.json()).then(res=>{if(res.success)Swal.fire({icon:'success',background:'#1e293b',color:'#fff'});else Swal.fire({icon:'error',text:res.msg,background:'#1e293b',color:'#fff'})})}})}
function up(){const n=document.getElementById('net').value,s=document.getElementById('sec').value;document.getElementById('ws').classList.toggle('d-none',n!=='ws');document.getElementById('rea').classList.toggle('d-none',s!=='reality')}
function genUUID(){document.getElementById('uid').value=crypto.randomUUID()}
function getRealKeys(){document.getElementById('r_pk').placeholder="Generating...";fetch('/api/keys',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:currId})}).then(r=>r.json()).then(r=>{if(r.success){document.getElementById('r_pk').value=r.keys.publicKey;document.getElementById('r_sk').value=r.keys.privateKey}else toast.fire({icon:'error',title:r.msg})})}
function sub(){const f=document.getElementById('f'),d=Object.fromEntries(new FormData(f).entries());if(d.security==='tls'){d.tls_cert='/root/cert/fullchain.cer';d.tls_key='/root/cert/private.key'}fetch('/api/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:currId,config:d})}).then(r=>r.json()).then(r=>{if(r.success){m.hide();genLink(d, currId);}else toast.fire({icon:'error',title:r.msg})})}
function genLink(c,uid){fetch('/api/stats').then(r=>r.json()).then(d=>{const ip=d.agents[uid].ip;let link="";if(c.protocol==='vless'){link=\`vless://\${c.uuid}@\${ip}:\${c.port}?encryption=none&security=\${c.security}&type=\${c.network}\`;if(c.security==='reality')link+=\`&sni=\${c.reality_sni}&fp=chrome&pbk=\${c.reality_pk}&sid=\`;if(c.network==='ws')link+=\`&path=\${encodeURIComponent(c.ws_path)}\`;link+=\`#\${encodeURIComponent(c.remark)}\`}else if(c.protocol==='vmess'){const v={v:"2",ps:c.remark,add:ip,port:c.port,id:c.uuid,aid:"0",scy:"auto",net:c.network,type:"none",host:"",path:"",tls:""};if(c.network==='ws')v.path=c.ws_path;if(c.security==='tls')v.tls="tls";link="vmess://"+btoa(JSON.stringify(v))}document.getElementById('link_txt').value=link;document.getElementById('qrcode').innerHTML="";new QRCode(document.getElementById("qrcode"),{text:link,width:180,height:180});rm.show()})}
function copyLink(){document.getElementById('link_txt').select();document.execCommand('copy');toast.fire({icon:'success',title:'Copied'})}
setInterval(ref,3000);ref();
</script></body></html>
"""
@app.route('/')
def index(): return render_template_string(HTML_TEMPLATE)
if __name__ == '__main__': app.run(host='::', port=PORT, threaded=True)
EOF

    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install flask flask-sock requests simple-websocket psutil" >> Dockerfile
    echo "COPY server.py ." >> Dockerfile
    echo "CMD [\"python\", \"server.py\"]" >> Dockerfile

    # Clean build
    docker build -t multix-master . >/dev/null 2>&1
    docker rm -f multix-master >/dev/null 2>&1
    
    # Run
    docker run -d --name multix-master --network host --restart always \
        --pid host \
        -e MASTER_PORT=${DEFAULT_MASTER_PORT} -e CLUSTER_TOKEN=${TOKEN} multix-master >/dev/null

    echo -e "\n${GREEN}✔ Master Successfully Deployed!${PLAIN}"
    echo -e "   🌐 Dashboard: http://$(curl -s -4 ifconfig.me):${DEFAULT_MASTER_PORT}"
    echo -e "   🔑 Token    : ${YELLOW}${TOKEN}${PLAIN}"
    echo -e "\nPress Enter to return..."
    read
}

# ==================================================
# 2. Install Agent (Clean Install + Pre-check)
# ==================================================
install_agent() {
    check_docker
    clear
    echo -e "${CYAN}====================================================${PLAIN}"
    echo -e "${BOLD}   Deploy Agent Node (w/ 3x-ui + Monitor)${PLAIN}"
    echo -e "${CYAN}====================================================${PLAIN}"

    # Clean up old container forcefully
    if docker ps -a | grep -q multix-agent; then
        echo -e "${YELLOW}♻️  Cleaning up old Agent...${PLAIN}"
        cd ${APP_DIR}/agent && docker compose down >/dev/null 2>&1
        docker rm -f multix-agent >/dev/null 2>&1
    fi

    # Network Selection
    echo -e "\n${BOLD}📡 Connection Protocol${PLAIN}"
    echo -e "   [1] IPv4 (Default)"
    echo -e "   [2] IPv6 (Recommended for NAT/Edu)"
    read -p "Select [1/2]: " P_OPT
    
    echo -e "\n${BOLD}🌍 Master Address${PLAIN}"
    read -p "Enter IP or Domain: " MASTER_ADDR

    echo -e "\n⏳ Running Pre-flight Check..."
    if [[ "$P_OPT" == "2" ]]; then
        ping6 -c 2 -W 2 $MASTER_ADDR >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Error: Cannot reach ${MASTER_ADDR} via IPv6${PLAIN}"
            read -p "Press Enter to try again..."
            return
        fi
        echo -e "${GREEN}✔ IPv6 Reachable${PLAIN}"
    else
        ping -c 2 -W 2 $MASTER_ADDR >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Error: Cannot reach ${MASTER_ADDR} via IPv4${PLAIN}"
            read -p "Press Enter to try again..."
            return
        fi
        echo -e "${GREEN}✔ IPv4 Reachable${PLAIN}"
    fi

    echo -e "\n${BOLD}🔑 Auth Token${PLAIN}"
    read -p "Enter Cluster Token: " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/agent
    cd ${APP_DIR}/agent
    if [ ! -f uuid ]; then cat /proc/sys/kernel/random/uuid > uuid; fi
    MY_UUID=$(cat uuid)

    # Agent Code
    cat > agent.py <<EOF
import time, json, socket, os, websocket, requests, threading, psutil

M_ADDR = "${MASTER_ADDR}"
M_PORT = int(os.getenv('MASTER_PORT', 7575))
TOKEN = "${TOKEN}"
AGENT_UUID = "${MY_UUID}"
X_PORT = int(os.getenv('XUI_PORT', 2053))
X_USER = os.getenv('XUI_USER', 'admin')
X_PASS = os.getenv('XUI_PASS', 'admin123')
psutil.PROCFS_PATH = '/host/proc'

WS_URL = f"ws://{M_ADDR}:{M_PORT}/ws"
if ':' in M_ADDR and not M_ADDR.startswith('['): WS_URL = f"ws://[{M_ADDR}]:{M_PORT}/ws"

def xui_api(path, payload={}):
    s = requests.Session()
    try:
        s.post(f"http://127.0.0.1:{X_PORT}/login", data={'username': X_USER, 'password': X_PASS})
        return s.post(f"http://127.0.0.1:{X_PORT}{path}", json=payload).json()
    except: return {}

def get_sys_status():
    try:
        disk = psutil.disk_usage('/hostfs').percent if os.path.exists('/hostfs') else 0
        return {'cpu': int(psutil.cpu_percent(interval=None)),'mem': int(psutil.virtual_memory().percent),'disk': int(disk)}
    except: return {}

def on_message(ws, message):
    try:
        cmd = json.loads(message)
        act = cmd.get('action')
        if act == 'get_keys':
            res = xui_api("/server/getNewX25519Cert")
            if res.get('success'): ws.send(json.dumps({'success': True, 'keys': res.get('obj')}))
            else: ws.send(json.dumps({'success': False, 'msg': 'Gen Failed'}))
        elif act == 'add_node':
            c = cmd.get('data')
            stream = {"network": c.get('network'), "security": c.get('security'), "wsSettings": {}, "tcpSettings": {}}
            if c.get('network') == 'ws': stream['wsSettings'] = {"path": c.get('ws_path'), "headers": {"Host": ""}}
            if c.get('security') == 'reality': stream['realitySettings'] = {"show": False, "dest": c.get('reality_dest'), "serverNames": [c.get('reality_sni')], "shortIds": [""]}
            if c.get('security') == 'tls': stream['tlsSettings'] = {"certificates": [{"certificateFile": c.get('tls_cert'), "keyFile": c.get('tls_key')}]}
            listen_ip = "" 
            if c.get('listen') == '0.0.0.0': listen_ip = "0.0.0.0"
            if c.get('listen') == '::': listen_ip = "::"
            inbound = {"enable": True, "remark": c.get('remark'), "port": int(c.get('port')), "protocol": c.get('protocol'), "listen": listen_ip, "settings": json.dumps({"clients": [{"id": c.get('uuid'), "email": "m@u"}], "decryption": "none"}), "streamSettings": json.dumps(stream), "sniffing": json.dumps({"enabled": True, "destOverride": ["http","tls","quic"]})}
            ws.send(json.dumps(xui_api("/panel/api/inbounds/add", inbound)))
        elif act == 'apply_cert':
            dom = cmd.get('domain')
            if os.system(f"~/.acme.sh/acme.sh --issue -d {dom} --standalone --force") == 0:
                os.system(f"~/.acme.sh/acme.sh --install-cert -d {dom} --key-file /root/cert/private.key --fullchain-file /root/cert/fullchain.cer")
                ws.send(json.dumps({'success': True}))
            else: ws.send(json.dumps({'success': False, 'msg': 'Acme Failed'}))
    except: pass

def on_open(ws):
    v4 = True if os.popen("ip -4 a | grep global").read() else False
    v6 = True if os.popen("ip -6 a | grep global").read() else False
    try: pub_ip = requests.get('https://api.ipify.org', timeout=3).text
    except: pub_ip = "Unknown"
    ws.send(json.dumps({'token': TOKEN, 'uuid': AGENT_UUID, 'name': socket.gethostname(), 'ip': pub_ip, 'ipv4': v4, 'ipv6': v6}))
    def reporter():
        while True:
            time.sleep(3)
            try: ws.send(json.dumps(get_sys_status()))
            except: break
    threading.Thread(target=reporter, daemon=True).start()

def run_ws():
    while True:
        try:
            ws = websocket.WebSocketApp(WS_URL, on_message=on_message, on_open=on_open)
            ws.run_forever()
        except: pass
        time.sleep(5)

if __name__ == '__main__': run_ws()
EOF

    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install websocket-client requests psutil" >> Dockerfile
    echo "RUN apt-get update && apt-get install -y curl socat iproute2" >> Dockerfile
    echo "COPY agent.py ." >> Dockerfile
    echo "CMD [\"python\", \"agent.py\"]" >> Dockerfile

    cat > docker-compose.yml <<EOF
services:
  xui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    volumes:
      - ./x-ui-db:/etc/x-ui/
      - ./cert:/root/cert/
    environment:
      XUI_PORT: ${DEFAULT_XUI_PORT}
      USERNAME: ${DEFAULT_XUI_USER}
      PASSWORD: ${DEFAULT_XUI_PASS}
    network_mode: "host"
    restart: always

  agent:
    build: .
    container_name: multix-agent
    environment:
      MASTER_PORT: ${DEFAULT_MASTER_PORT}
      XUI_PORT: ${DEFAULT_XUI_PORT}
      XUI_USER: ${DEFAULT_XUI_USER}
      XUI_PASS: ${DEFAULT_XUI_PASS}
    network_mode: "host"
    restart: always
    volumes:
      - /:/hostfs:ro
      - /proc:/host/proc:ro
EOF
    
    docker compose pull >/dev/null 2>&1
    docker compose up -d --build >/dev/null 2>&1
    echo -e "\n${GREEN}✔ Agent Deployed!${PLAIN}"
    echo -e "\nPress Enter to return..."
    read
}

# ==================================================
# 3. Ops & Info
# ==================================================
view_config() {
    clear
    echo -e "${CYAN}================================================================${PLAIN}"
    echo -e "${BOLD}   🔍 MultiX Configuration Inspector${PLAIN}"
    echo -e "${CYAN}================================================================${PLAIN}"

    echo -e "\n [ 🌍 Local Network ]"
    echo -e " ---------------------------------------------------------------"
    IPV4=$(ip -4 a | grep global | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    IPV6=$(ip -6 a | grep global | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    [[ -z "$IPV4" ]] && IPV4="None"
    [[ -z "$IPV6" ]] && IPV6="None"
    echo -e " 🟢 IPv4:  ${WHITE}${IPV4}${PLAIN}"
    echo -e " 🔵 IPv6:  ${WHITE}${IPV6}${PLAIN}"
    echo -e " ---------------------------------------------------------------"

    echo -e "\n [ 🔐 Cluster Credentials ]"
    echo -e " ---------------------------------------------------------------"
    # Try getting token from running containers
    TOKEN=""
    if docker ps | grep -q multix-master; then
        TOKEN=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' multix-master | grep CLUSTER_TOKEN | cut -d= -f2)
    elif docker ps | grep -q multix-agent; then
        TOKEN=$(docker exec multix-agent cat agent.py 2>/dev/null | grep 'TOKEN =' | cut -d'"' -f2)
    fi
    [[ -z "$TOKEN" ]] && TOKEN="${RED}Not Found (Service Stopped)${PLAIN}"
    echo -e " 🔑 Token: ${YELLOW}${TOKEN}${PLAIN}"
    echo -e " ---------------------------------------------------------------"

    echo -e "\n [ 🔴 Agent / 3x-ui Info ]"
    echo -e " ---------------------------------------------------------------"
    if docker ps | grep -q 3x-ui; then
        X_USER=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' 3x-ui | grep USERNAME | cut -d= -f2)
        X_PASS=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' 3x-ui | grep PASSWORD | cut -d= -f2)
        X_PORT=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' 3x-ui | grep XUI_PORT | cut -d= -f2)
        echo -e " 3x-ui:  ${GREEN}http://127.0.0.1:${X_PORT}${PLAIN}"
        echo -e " User :  ${WHITE}${X_USER}${PLAIN}"
        echo -e " Pass :  ${WHITE}${X_PASS}${PLAIN}"
    else
        echo -e " ${GRAY}Agent not running.${PLAIN}"
    fi
    echo -e " ================================================================"
    read -p " Press Enter to return..."
}

show_logs() {
    clear
    echo -e "${YELLOW}Select Container:${PLAIN}"
    echo "1. Master"
    echo "2. Agent"
    echo "3. 3x-ui"
    read -p "Opt: " OPT
    case $OPT in
        1) NAME="multix-master" ;;
        2) NAME="multix-agent" ;;
        3) NAME="3x-ui" ;;
    esac
    if [[ -n "$NAME" ]]; then
        echo -e "${CYAN}Streaming logs for $NAME (Ctrl+C to exit)...${PLAIN}"
        docker logs -f $NAME
    fi
}

manage_docker() {
    if [[ "$1" == "restart" ]]; then
        docker restart multix-master multix-agent 3x-ui 2>/dev/null
        echo -e "${GREEN}✔ Restarted${PLAIN}"
    elif [[ "$1" == "stop" ]]; then
        docker stop multix-master multix-agent 3x-ui 2>/dev/null
        echo -e "${GREEN}✔ Stopped${PLAIN}"
    fi
    sleep 1
}

uninstall() {
    echo -e "${RED}1. Remove Containers (Keep Data)  2. Full Wipe (Delete Data)${PLAIN}"
    read -p "Opt: " OPT
    if [[ "$OPT" == "1" ]] || [[ "$OPT" == "2" ]]; then
        docker rm -f multix-master 2>/dev/null
        cd ${APP_DIR}/agent 2>/dev/null && docker compose down 2>/dev/null
        if [[ "$OPT" == "2" ]]; then rm -rf ${APP_DIR}; fi
        echo -e "${GREEN}✔ Done${PLAIN}"
    fi
}

# ==================================================
# Main Menu
# ==================================================
show_menu() {
    while true; do
        get_status
        clear
        echo -e "${CYAN}################################################################${PLAIN}"
        echo -e "${CYAN}#   ${BOLD}MultiX Cluster Manager${PLAIN}${CYAN} [v10.1 Ultimate]                    #${PLAIN}"
        echo -e "${CYAN}#   * Dockerized Environment / High Performance                #${PLAIN}"
        echo -e "${CYAN}################################################################${PLAIN}"
        echo ""
        echo -e " [ 📦 Container Status ]"
        echo -e " ---------------------------------------------------------------"
        printf " %-30s %-20s %-15s\n" "🟢 Master Node" "$M_STATE" "[$M_MEM]"
        printf " %-30s %-20s %-15s\n" "🔴 Agent Node" "$A_STATE" "[$A_MEM]"
        echo -e " ---------------------------------------------------------------"
        echo ""
        echo -e " [ 🚀 1. Deploy ]"
        echo -e "  ${BOLD}1.${PLAIN} Install/Update Master (Dashboard)"
        echo -e "  ${BOLD}2.${PLAIN} Install/Update Agent  (Client)"
        echo ""
        echo -e " [ 🛠️ 2. Ops ]"
        echo -e "  ${BOLD}3.${PLAIN} View Logs"
        echo -e "  ${BOLD}4.${PLAIN} Restart Services"
        echo -e "  ${BOLD}5.${PLAIN} Stop Services"
        echo ""
        echo -e " [ ℹ️ 3. Info & Debug ]"
        echo -e "  ${BOLD}6.${PLAIN} View Config (Token / IPs / 3x-ui Creds)"
        echo ""
        echo -e " [ 🗑️ 4. Uninstall ]"
        echo -e "  ${BOLD}9.${PLAIN} Uninstall Options"
        echo ""
        echo -e " ---------------------------------------------------------------"
        echo -e "  ${BOLD}0.${PLAIN} Exit"
        echo -e " ---------------------------------------------------------------"
        read -p " Select [0-9]: " OPT

        case $OPT in
            1) install_master ;;
            2) install_agent ;;
            3) show_logs ;;
            4) manage_docker restart ;;
            5) manage_docker stop ;;
            6) view_config ;;
            9) uninstall ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

show_menu
