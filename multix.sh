#!/bin/bash

# ==============================================================================
# MultiX Cluster - v12.0 (Precision Edition)
# Focused on Connectivity, Security, and Proxy Management.
# ==============================================================================

# --- 全局配置 ---
APP_DIR="/opt/multix_docker"
DEFAULT_MASTER_PORT=7575
DEFAULT_XUI_PORT=2053
DEFAULT_TOKEN="multix_secret_888"

# --- 颜色定义 ---
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

# --- 基础检测与信息获取 ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}⚡ 正在安装 Docker 引擎...${PLAIN}"
        curl -fsSL https://get.docker.com | bash >/dev/null 2>&1
        systemctl start docker; systemctl enable docker
    fi
    if ! docker compose version &> /dev/null; then
        apt-get install -y docker-compose-plugin 2>/dev/null || yum install -y docker-compose-plugin 2>/dev/null
    fi
}

get_sys_info() {
    # 获取静态硬件信息
    CPU_MODEL=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)
    [[ -z "$CPU_MODEL" ]] && CPU_MODEL="Unknown CPU"
    
    MEM_TOTAL=$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)
    
    OS_INFO=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    KERNEL=$(uname -r)
    
    # 检测 BBR
    TCP_ALG=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "$TCP_ALG" == "bbr" ]]; then
        BBR_STATUS="${GREEN}BBR (开启)${PLAIN}"
    else
        BBR_STATUS="${YELLOW}Cubic (未开启)${PLAIN}"
    fi

    # 获取容器状态
    if docker ps --format '{{.Names}}' | grep -q "^multix-master$"; then
        M_STATE="${GREEN}● 运行中${PLAIN}"
        M_PORT=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' multix-master | grep MASTER_PORT | cut -d= -f2)
    else
        M_STATE="${GRAY}○ 已停止${PLAIN}"
        M_PORT="--"
    fi

    if docker ps --format '{{.Names}}' | grep -q "^multix-agent$"; then
        A_STATE="${GREEN}● 运行中${PLAIN}"
        X_PORT=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' multix-agent | grep XUI_PORT | cut -d= -f2)
    else
        A_STATE="${GRAY}○ 已停止${PLAIN}"
        X_PORT="--"
    fi
}

# ==================================================
# 1. 安装 Master (Web Dashboard)
# ==================================================
install_master() {
    check_docker
    clear
    echo -e "${MAGENTA}====================================================${PLAIN}"
    echo -e "${BOLD}   部署 Master 主控端 (Precision UI)${PLAIN}"
    echo -e "${MAGENTA}====================================================${PLAIN}"
    
    # 强制清理旧容器
    if docker ps -a | grep -q multix-master; then
        echo -e "${YELLOW}♻️  清理旧版 Master 容器...${PLAIN}"
        docker rm -f multix-master >/dev/null 2>&1
    fi

    echo -e "\n${BOLD}🔐 鉴权配置${PLAIN}"
    echo -e "${GRAY}设置集群通信密钥 (Token)，Agent 必须凭此接入。${PLAIN}"
    read -p "Token [默认: ${DEFAULT_TOKEN}]: " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/master
    cd ${APP_DIR}/master

    # Server Python Code
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

# 获取 Master 自身宿主机信息 (通过挂载 /proc)
def get_master_stats():
    # 尝试读取宿主机 BBR
    bbr = 'unknown'
    try:
        with open('/host/proc/sys/net/ipv4/tcp_congestion_control', 'r') as f:
            bbr = f.read().strip()
    except: pass
    
    return {
        'cpu': psutil.cpu_percent(interval=None),
        'mem': psutil.virtual_memory().percent,
        'bbr': bbr
    }

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
                # 更新心跳数据
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
body{background-color:var(--bg-body);color:var(--text-main);font-family:'Inter',system-ui,sans-serif}
.navbar{background:rgba(30,41,59,0.9);backdrop-filter:blur(10px);border-bottom:1px solid rgba(255,255,255,0.05)}
.card{background:var(--bg-card);border:1px solid rgba(255,255,255,0.05);border-radius:12px;box-shadow:0 4px 6px -1px rgba(0,0,0,0.1)}
.status-indicator{width:10px;height:10px;border-radius:50%;display:inline-block;margin-right:6px}
.online{background-color:#22c55e;box-shadow:0 0 8px rgba(34,197,94,0.4)}
.btn-glass{background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);color:#fff}
.btn-glass:hover{background:rgba(255,255,255,0.1)}
.bbr-on{color:#22c55e;font-size:0.8rem;font-weight:bold;border:1px solid #22c55e;padding:2px 6px;border-radius:4px}
.bbr-off{color:#eab308;font-size:0.8rem;font-weight:bold;border:1px solid #eab308;padding:2px 6px;border-radius:4px}
</style>
</head><body>
<nav class="navbar navbar-expand-lg navbar-dark sticky-top px-4 py-3">
  <div class="d-flex w-100 justify-content-between align-items-center">
    <div class="d-flex align-items-center gap-3"><span class="fs-5 fw-bold"><i class="bi bi-grid-fill text-primary"></i> MultiX</span><span class="badge bg-primary bg-opacity-10 text-primary border border-primary border-opacity-25">v12.0</span></div>
    <div class="d-flex align-items-center gap-3">
        <div class="text-end d-none d-md-block" style="line-height:1.2">
            <small class="d-block text-muted" style="font-size:0.7rem">MASTER</small>
            <span class="fw-bold text-light" id="m_stat">Loading...</span>
        </div>
        <button class="btn btn-sm btn-glass" onclick="toggleLang()" id="langBtn">🇺🇸 EN / 🇨🇳 CN</button>
    </div>
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

<div class="modal fade" id="addModal"><div class="modal-dialog modal-dialog-centered"><div class="modal-content" style="background:var(--bg-card)"><div class="modal-header border-0"><h5 class="modal-title fw-bold" data-t="add">Add Node</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body"><form id="f"><input type="hidden" id="tuuid"><div class="form-floating mb-2"><input class="form-control bg-dark text-white border-secondary" name="remark" value="Node-1"><label>Remark</label></div><div class="row g-2 mb-2"><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option></select><label>Protocol</label></div></div><div class="col"><div class="form-floating"><input type="number" class="form-control bg-dark text-white border-secondary" name="port" placeholder="Port"><label>Port</label></div></div></div><div class="form-floating mb-2"><input class="form-control bg-dark text-white border-secondary" name="uuid" id="uid"><label>UUID</label><button type="button" class="btn btn-sm btn-link position-absolute end-0 top-50 translate-middle-y text-decoration-none" onclick="genUUID()"><i class="bi bi-magic"></i></button></div><div class="form-floating mb-2"><select class="form-select bg-dark text-white border-secondary" name="listen"><option value="">🌐 Dual Stack (Default)</option><option value="0.0.0.0">4️⃣ IPv4 Only</option><option value="::">6️⃣ IPv6 Only</option></select><label data-t="listen">Listen Interface</label></div><div class="row g-2 mb-2"><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="network" id="net" onchange="up()"><option value="tcp">TCP</option><option value="ws">WS</option></select><label>Network</label></div></div><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="security" id="sec" onchange="up()"><option value="none">None</option><option value="reality">REALITY</option><option value="tls">TLS</option></select><label>Security</label></div></div></div><div id="ws" class="d-none mb-2"><input class="form-control bg-dark text-white border-secondary" name="ws_path" placeholder="WS Path"></div><div id="rea" class="d-none mb-2 p-3 border border-secondary border-opacity-25 rounded bg-black bg-opacity-25"><div class="d-flex justify-content-between mb-2"><span class="text-warning small">REALITY</span> <button class="btn btn-sm btn-outline-warning py-0" type="button" onclick="getRealKeys()">Auto Gen Keys</button></div><input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_dest" value="www.microsoft.com:443"><input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_sni" value="www.microsoft.com"><input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_pk" id="r_pk" placeholder="PK" readonly><input class="form-control form-control-sm bg-dark text-white" name="reality_sk" id="r_sk" placeholder="SK" readonly></div></form></div><div class="modal-footer border-0"><button class="btn btn-primary w-100 py-2 fw-bold" onclick="sub()" data-t="save">Deploy & Get Link</button></div></div></div></div>
<div class="modal fade" id="resModal"><div class="modal-dialog modal-dialog-centered"><div class="modal-content" style="background:var(--bg-card)"><div class="modal-header border-0"><h5 class="modal-title">Result</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body text-center"><div class="bg-white p-3 d-inline-block rounded mb-3"><div id="qrcode"></div></div><div class="input-group"><input class="form-control bg-dark text-white border-secondary" id="link_txt" readonly><button class="btn btn-success" onclick="copyLink()"><i class="bi bi-clipboard"></i></button></div></div></div></div>

<script>
const m=new bootstrap.Modal('#addModal'), rm=new bootstrap.Modal('#resModal');
let currId='', lang='en';
const T={en:{add:'Add Node',save:'Deploy & Get Link',listen:'Listen IP',list:'Managed Servers',total:'Total',online:'Online'},cn:{add:'添加节点',save:'部署并获取链接',listen:'监听接口',list:'被控服务器列表',total:'节点总数',online:'在线数量'}};
function toggleLang(){lang=lang==='en'?'cn':'en';document.querySelectorAll('[data-t]').forEach(e=>e.innerText=T[lang][e.dataset.t])}
const toast=Swal.mixin({toast:true,position:'top-end',showConfirmButton:false,timer:3000,timerProgressBar:true,background:'#1e293b',color:'#fff'});
function ref(){
    fetch('/api/stats').then(r=>r.json()).then(d=>{
        // Master Stat
        let mbbr = d.master.bbr==='bbr'?'<span class="text-success small">BBR ON</span>':'<span class="text-warning small">NO BBR</span>';
        document.getElementById('m_stat').innerHTML = \`CPU \${d.master.cpu}% | \${mbbr}\`;
        // List
        const l=document.getElementById('list'), r=d.agents;
        l.innerHTML=''; let c=0,v4=0,v6=0;
        for(let u in r){
            c++;
            let tags='';
            if(r[u].ipv4&&r[u].ipv6)tags+='<span class="badge bg-success bg-opacity-25 text-success border border-success border-opacity-25 me-1">Dual</span>';
            else if(r[u].ipv6){tags+='<span class="badge bg-warning bg-opacity-25 text-warning border border-warning border-opacity-25 me-1">v6</span>';v6++}
            else{tags+='<span class="badge bg-info bg-opacity-25 text-info border border-info border-opacity-25 me-1">v4</span>';v4++}
            let conn=r[u].conn_ip.includes(':')?'IPv6':'IPv4';
            let cpu=r[u].cpu||0,mem=r[u].mem||0;
            // BBR Status
            let bbr_badge = r[u].bbr==='bbr' ? '<span class="bbr-on">🚀 BBR</span>' : '<span class="bbr-off">⚠️ No BBR</span>';
            
            l.innerHTML+=\`
            <div class="col-md-6 col-lg-4"><div class="card h-100"><div class="card-body">
                <div class="d-flex justify-content-between align-items-start mb-3">
                    <div><h5 class="fw-bold mb-1" style="cursor:pointer" onclick="ren('\${u}')">\${r[u].name} <i class="bi bi-pencil-fill text-muted fs-6 opacity-50"></i></h5>
                    <div class="d-flex align-items-center"><span class="status-indicator online"></span><span class="small text-muted">\${r[u].ip}</span></div></div>
                    <div class="text-end"><span class="badge bg-secondary bg-opacity-25 text-secondary d-block mb-1">via \${conn}</span>\${bbr_badge}</div>
                </div>
                <div class="mb-3">\${tags}</div>
                <div class="mb-2"><div class="d-flex justify-content-between small mb-1"><span>CPU</span><span>\${cpu}%</span></div><div class="progress"><div class="progress-bar bg-primary" style="width:\${cpu}%"></div></div></div>
                <div><div class="d-flex justify-content-between small mb-1"><span>RAM</span><span>\${mem}%</span></div><div class="progress"><div class="progress-bar bg-info" style="width:\${mem}%"></div></div></div>
            </div>
            <div class="card-footer bg-transparent border-top border-secondary border-opacity-10 p-3 d-flex gap-2">
                <button class="btn btn-sm btn-primary flex-grow-1 fw-bold" onclick="pop('\${u}')"><i class="bi bi-plus-lg"></i> Node</button>
                <button class="btn btn-sm btn-outline-light" onclick="cert('\${u}')" title="SSL"><i class="bi bi-shield-check"></i></button>
                <a href="http://\${r[u].ip}:\${r[u].xp||2053}" target="_blank" class="btn btn-sm btn-glass"><i class="bi bi-box-arrow-up-right"></i> Panel</a>
            </div></div></div>\`;
        }
        document.getElementById('stat_total').innerText=c;document.getElementById('stat_online').innerText=c;document.getElementById('stat_v4').innerText=v4;document.getElementById('stat_v6').innerText=v6;if(c===0)l.innerHTML='<div class="col-12 text-center text-muted py-5">Waiting for agents...</div>'
    })
}
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

    # Build Master
    docker build -t multix-master . >/dev/null 2>&1
    docker rm -f multix-master >/dev/null 2>&1
    
    # Run with pid:host to read host proc
    docker run -d --name multix-master --network host --restart always \
        --pid host \
        --volume /proc:/host/proc:ro \
        -e MASTER_PORT=${DEFAULT_MASTER_PORT} -e CLUSTER_TOKEN=${TOKEN} multix-master >/dev/null

    echo -e "\n${GREEN}✔ Master Deployed!${PLAIN}"
    echo -e "   🌐 Dashboard: http://$(curl -s -4 ifconfig.me):${DEFAULT_MASTER_PORT}"
    echo -e "   🔑 Token    : ${YELLOW}${TOKEN}${PLAIN}"
    echo -e "\nPress Enter..."
    read
}

# ==================================================
# 2. Install Agent (Client)
# ==================================================
install_agent() {
    check_docker
    clear
    echo -e "${CYAN}====================================================${PLAIN}"
    echo -e "${BOLD}   Deploy Agent Node${PLAIN}"
    echo -e "${CYAN}====================================================${PLAIN}"

    if docker ps -a | grep -q multix-agent; then
        echo -e "${YELLOW}♻️  Removing old Agent...${PLAIN}"
        cd ${APP_DIR}/agent && docker compose down >/dev/null 2>&1
        docker rm -f multix-agent >/dev/null 2>&1
    fi

    # Protocol Select
    echo -e "\n${BOLD}📡 Connect Protocol${PLAIN}"
    echo -e "   [1] IPv4 (Default)"
    echo -e "   [2] IPv6 (Use this for NAT/IPv6-Only)"
    read -p "Select [1/2]: " P_OPT
    
    echo -e "\n${BOLD}🌍 Master Address${PLAIN}"
    read -p "IP/Domain: " MASTER_ADDR

    echo -e "\n⏳ Checking Connectivity..."
    if [[ "$P_OPT" == "2" ]]; then
        ping6 -c 2 -W 2 $MASTER_ADDR >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Connection Failed (IPv6). Check IP or Firewall.${PLAIN}"; read; return
        fi
        echo -e "${GREEN}✔ IPv6 Reachable${PLAIN}"
    else
        ping -c 2 -W 2 $MASTER_ADDR >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Connection Failed (IPv4). Check IP or Firewall.${PLAIN}"; read; return
        fi
        echo -e "${GREEN}✔ IPv4 Reachable${PLAIN}"
    fi

    echo -e "\n${BOLD}🔑 Auth Token${PLAIN}"
    read -p "Token: " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/agent
    cd ${APP_DIR}/agent
    if [ ! -f uuid ]; then cat /proc/sys/kernel/random/uuid > uuid; fi
    MY_UUID=$(cat uuid)

    # Agent Code
    cat > agent.py <<EOF
import time, json, socket, os, websocket, requests, threading, psutil
psutil.PROCFS_PATH = '/host/proc'

M_ADDR = "${MASTER_ADDR}"
M_PORT = int(os.getenv('MASTER_PORT', 7575))
TOKEN = "${TOKEN}"
AGENT_UUID = "${MY_UUID}"
X_PORT = int(os.getenv('XUI_PORT', 2053))
X_USER = os.getenv('XUI_USER', 'admin')
X_PASS = os.getenv('XUI_PASS', 'admin123')

WS_URL = f"ws://{M_ADDR}:{M_PORT}/ws"
if ':' in M_ADDR and not M_ADDR.startswith('['): WS_URL = f"ws://[{M_ADDR}]:{M_PORT}/ws"

def xui_api(path, payload={}):
    s = requests.Session()
    try:
        s.post(f"http://127.0.0.1:{X_PORT}/login", data={'username': X_USER, 'password': X_PASS})
        return s.post(f"http://127.0.0.1:{X_PORT}{path}", json=payload).json()
    except: return {}

def get_sys_status():
    bbr = 'unknown'
    try:
        with open('/host/proc/sys/net/ipv4/tcp_congestion_control', 'r') as f:
            bbr = f.read().strip()
    except: pass
    try:
        disk = psutil.disk_usage('/hostfs').percent if os.path.exists('/hostfs') else 0
        return {'cpu': int(psutil.cpu_percent(interval=None)),'mem': int(psutil.virtual_memory().percent),'disk': int(disk), 'bbr': bbr}
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
    echo -e "\nPress Enter..."
    read
}

# ==================================================
# 3. Operations
# ==================================================
enable_bbr() {
    echo -e "${GREEN}>>> Enabling BBR on Host...${PLAIN}"
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${GREEN}✔ BBR Enabled (Restart not required for newer kernels).${PLAIN}"
    else
        echo -e "${YELLOW}BBR already configured.${PLAIN}"
    fi
    read -p "Press Enter..."
}

view_config() {
    clear
    echo -e "${CYAN}================================================================${PLAIN}"
    echo -e "${BOLD}   🔍 Config Inspector${PLAIN}"
    echo -e "${CYAN}================================================================${PLAIN}"

    echo -e "\n [ 🌍 Local IP ]"
    IPV4=$(ip -4 a | grep global | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    IPV6=$(ip -6 a | grep global | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    echo -e " 🟢 IPv4:  ${WHITE}${IPV4:-None}${PLAIN}"
    echo -e " 🔵 IPv6:  ${WHITE}${IPV6:-None}${PLAIN}"

    echo -e "\n [ 🔐 Cluster ]"
    TOKEN=""
    if docker ps | grep -q multix-master; then
        TOKEN=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' multix-master | grep CLUSTER_TOKEN | cut -d= -f2)
    elif docker ps | grep -q multix-agent; then
        TOKEN=$(docker exec multix-agent cat agent.py 2>/dev/null | grep 'TOKEN =' | cut -d'"' -f2)
    fi
    echo -e " 🔑 Token: ${YELLOW}${TOKEN:-Stopped}${PLAIN}"

    echo -e "\n [ 🚀 3x-ui Creds ]"
    if docker ps | grep -q 3x-ui; then
        X_USER=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' 3x-ui | grep USERNAME | cut -d= -f2)
        X_PASS=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' 3x-ui | grep PASSWORD | cut -d= -f2)
        echo -e " User : ${WHITE}${X_USER}${PLAIN} / Pass : ${WHITE}${X_PASS}${PLAIN}"
    else
        echo -e " ${GRAY}Not Running${PLAIN}"
    fi
    echo -e " ================================================================"
    read -p " Press Enter..."
}

change_config() {
    echo -e "\n${BOLD}⚠️  This will restart containers.${PLAIN}"
    echo "1. Change Master Port"
    echo "2. Change 3x-ui Port"
    echo "3. Change Cluster Token"
    read -p "Select: " OPT
    
    if [[ "$OPT" == "1" ]]; then
        read -p "New Master Port: " P
        sed -i "s/DEFAULT_MASTER_PORT=.*/DEFAULT_MASTER_PORT=$P/" $0
        echo -e "${GREEN}Config updated. Please Re-install Master to apply.${PLAIN}"
    elif [[ "$OPT" == "2" ]]; then
        read -p "New 3x-ui Port: " P
        sed -i "s/DEFAULT_XUI_PORT=.*/DEFAULT_XUI_PORT=$P/" $0
        echo -e "${GREEN}Config updated. Please Re-install Agent to apply.${PLAIN}"
    fi
    read -p "Press Enter..."
}

view_logs() {
    clear
    echo "1. Master Log  2. Agent Log"
    read -p "Opt: " OPT
    if [[ "$OPT" == "1" ]]; then docker logs -f multix-master; fi
    if [[ "$OPT" == "2" ]]; then docker logs -f multix-agent; fi
}

uninstall() {
    echo -e "${RED}1. Remove Containers (Keep Data)  2. Full Wipe${PLAIN}"
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
        get_sys_info
        clear
        echo -e " ┌── [ 🖥️ System Info ] ────────────────────────────────────────┐"
        echo -e " │  Model    :  ${WHITE}${CPU_MODEL:0:30}...${PLAIN}"
        echo -e " │  Kernel   :  ${WHITE}${KERNEL}${PLAIN}          [ TCP: ${BBR_STATUS} ]"
        echo -e " │  Memory   :  ${WHITE}${MEM_TOTAL}${PLAIN}"
        echo -e " └──────────────────────────────────────────────────────────────┘"
        echo -e " ┌── [ 📦 Docker Status ] ──────────────────────────────────────┐"
        printf " │  Master : %-20s  Agent : %-20s │\n" "${M_STATE} : ${M_PORT}" "${A_STATE} : ${X_PORT}"
        echo -e " └──────────────────────────────────────────────────────────────┘"
        echo ""
        echo -e " [ 🚀 1. Deploy ]"
        echo -e "  1. Install Master (Dashboard)"
        echo -e "  2. Install Agent  (Client)"
        echo ""
        echo -e " [ ⚙️ 2. Network & Config ]"
        echo -e "  3. Enable BBR (Host)"
        echo -e "  4. Change Ports / Token"
        echo -e "  5. View Logs (Debug)"
        echo ""
        echo -e " [ ℹ️ 3. Info ]"
        echo -e "  6. View Config (Tokens/IPs/Creds)"
        echo ""
        echo -e " [ 🗑️ 4. Uninstall ]"
        echo -e "  9. Uninstall Options"
        echo ""
        echo -e " ---------------------------------------------------------------"
        echo -e "  0. Exit"
        echo -e " ---------------------------------------------------------------"
        read -p " Select [0-9]: " OPT

        case $OPT in
            1) install_master ;;
            2) install_agent ;;
            3) enable_bbr ;;
            4) change_config ;;
            5) view_logs ;;
            6) view_config ;;
            9) uninstall ;;
            0) exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

show_menu
