#!/bin/bash

# ==============================================================================
# MultiX Cluster Manager - v10.0 (Dashboard Edition)
# Designed for high-performance distributed network management.
# ==============================================================================

# --- 全局配置 ---
APP_DIR="/opt/multix_docker"
DEFAULT_MASTER_PORT=7575
DEFAULT_XUI_PORT=2053
DEFAULT_TOKEN="multix_secret_888"

# --- 设计风格颜色 ---
RED='\033[38;5;196m'
GREEN='\033[38;5;46m'
YELLOW='\033[38;5;226m'
BLUE='\033[38;5;39m'
MAGENTA='\033[38;5;201m'
CYAN='\033[38;5;51m'
GRAY='\033[38;5;240m'
BOLD='\033[1m'
PLAIN='\033[0m'

# --- 辅助函数 ---
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

get_status() {
    # 获取 Master 状态
    if docker ps --format '{{.Names}}' | grep -q "^multix-master$"; then
        M_STATE="${GREEN}● 运行中${PLAIN}"
        M_PORT=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' multix-master | grep MASTER_PORT | cut -d= -f2)
        M_MEM=$(docker stats --no-stream --format "{{.MemUsage}}" multix-master | awk -F'/' '{print $1}')
    else
        M_STATE="${GRAY}○ 已停止${PLAIN}"
        M_PORT="--"
        M_MEM="0B"
    fi

    # 获取 Agent 状态
    if docker ps --format '{{.Names}}' | grep -q "^multix-agent$"; then
        A_STATE="${GREEN}● 运行中${PLAIN}"
        A_MEM=$(docker stats --no-stream --format "{{.MemUsage}}" multix-agent | awk -F'/' '{print $1}')
        X_PORT=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' multix-agent | grep XUI_PORT | cut -d= -f2)
    else
        A_STATE="${GRAY}○ 已停止${PLAIN}"
        A_MEM="0B"
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
    echo -e "${BOLD}   部署 Master 主控端 (Dashboard Edition)${PLAIN}"
    echo -e "${MAGENTA}====================================================${PLAIN}"
    
    echo -e "\n${BOLD}🔐 安全设置${PLAIN}"
    echo -e "${GRAY}请设置集群通信密钥 (Cluster Token)，用于 Agent 接入鉴权。${PLAIN}"
    read -p "Token [默认: ${DEFAULT_TOKEN}]: " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/master
    cd ${APP_DIR}/master

    # --- Server Python Code ---
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

# 获取 Master 自身状态
def get_master_stats():
    return {
        'cpu': psutil.cpu_percent(interval=None),
        'mem': psutil.virtual_memory().percent,
        'disk': psutil.disk_usage('/').percent
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
        print(f"Agent Connected: {info.get('name')}")

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

# API Endpoints
@app.route('/api/stats')
def api_stats():
    return jsonify({'master': get_master_stats(), 'agents': client_info})

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

# --- UI Template (Bootstrap 5 + SweetAlert2 + Dark Mode) ---
HTML_TEMPLATE = """
<!DOCTYPE html><html lang="en" data-bs-theme="dark"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>MultiX Dashboard</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
:root{--bg-body:#0f172a;--bg-card:#1e293b;--text-main:#f8fafc;--primary:#3b82f6}
body{background-color:var(--bg-body);color:var(--text-main);font-family:'Inter',system-ui,sans-serif}
.navbar{background:rgba(30,41,59,0.8);backdrop-filter:blur(10px);border-bottom:1px solid rgba(255,255,255,0.1)}
.card{background:var(--bg-card);border:1px solid rgba(255,255,255,0.05);border-radius:12px;box-shadow:0 4px 6px -1px rgba(0,0,0,0.1);transition:transform 0.2s}
.card:hover{transform:translateY(-2px);border-color:rgba(255,255,255,0.1)}
.status-indicator{width:10px;height:10px;border-radius:50%;display:inline-block;margin-right:6px}
.online{background-color:#22c55e;box-shadow:0 0 8px rgba(34,197,94,0.4)}
.progress{height:6px;background:#334155;border-radius:3px;margin-bottom:8px}
.badge-custom{font-weight:500;padding:5px 10px;border-radius:6px}
.btn-glass{background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);color:#fff}
.btn-glass:hover{background:rgba(255,255,255,0.1)}
</style>
</head><body>

<nav class="navbar navbar-expand-lg navbar-dark sticky-top px-4 py-3">
  <div class="d-flex w-100 justify-content-between align-items-center">
    <div class="d-flex align-items-center gap-3">
        <span class="fs-5 fw-bold"><i class="bi bi-grid-fill text-primary"></i> MultiX</span>
        <span class="badge bg-primary bg-opacity-10 text-primary border border-primary border-opacity-25">v10.0 Pro</span>
    </div>
    <div class="d-flex align-items-center gap-3">
        <div class="text-end d-none d-md-block" style="line-height:1.2">
            <small class="d-block text-muted" style="font-size:0.75rem">MASTER LOAD</small>
            <span class="fw-bold text-success" id="m_cpu">CPU 0%</span>
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

    <div class="d-flex justify-content-between align-items-center mb-3">
        <h5 class="fw-bold mb-0"><i class="bi bi-hdd-stack"></i> <span data-t="list">Managed Servers</span></h5>
        <button class="btn btn-sm btn-glass" onclick="ref()"><i class="bi bi-arrow-clockwise"></i></button>
    </div>
    <div class="row g-4" id="list"></div>
</div>

<div class="modal fade" id="addModal"><div class="modal-dialog modal-dialog-centered"><div class="modal-content" style="background:var(--bg-card)"><div class="modal-header border-0"><h5 class="modal-title fw-bold" data-t="add">Add Node</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div>
<div class="modal-body">
<form id="f"><input type="hidden" id="tuuid">
<div class="form-floating mb-2"><input class="form-control bg-dark text-white border-secondary" name="remark" placeholder="Remark" value="Node-1"><label>Remark</label></div>
<div class="row g-2 mb-2"><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option></select><label>Protocol</label></div></div><div class="col"><div class="form-floating"><input type="number" class="form-control bg-dark text-white border-secondary" name="port" placeholder="Port"><label>Port</label></div></div></div>
<div class="form-floating mb-2"><input class="form-control bg-dark text-white border-secondary" name="uuid" id="uid"><label>UUID</label><button type="button" class="btn btn-sm btn-link position-absolute end-0 top-50 translate-middle-y text-decoration-none" onclick="genUUID()"><i class="bi bi-magic"></i></button></div>
<div class="form-floating mb-2"><select class="form-select bg-dark text-white border-secondary" name="listen"><option value="">🌐 Dual Stack (v4+v6)</option><option value="0.0.0.0">4️⃣ IPv4 Only</option><option value="::">6️⃣ IPv6 Only</option></select><label data-t="listen">Listen Interface</label></div>
<div class="row g-2 mb-2"><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="network" id="net" onchange="up()"><option value="tcp">TCP</option><option value="ws">WS</option></select><label>Network</label></div></div><div class="col"><div class="form-floating"><select class="form-select bg-dark text-white border-secondary" name="security" id="sec" onchange="up()"><option value="none">None</option><option value="reality">REALITY</option><option value="tls">TLS</option></select><label>Security</label></div></div></div>
<div id="ws" class="d-none mb-2"><input class="form-control bg-dark text-white border-secondary" name="ws_path" placeholder="WS Path (e.g. /ws)"></div>
<div id="rea" class="d-none mb-2 p-3 border border-secondary border-opacity-25 rounded bg-black bg-opacity-25">
    <div class="d-flex justify-content-between mb-2"><span class="text-warning small">REALITY Config</span> <button class="btn btn-sm btn-outline-warning py-0" type="button" onclick="getRealKeys()">Auto Gen Keys</button></div>
    <input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_dest" value="www.microsoft.com:443" placeholder="Dest">
    <input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_sni" value="www.microsoft.com" placeholder="SNI">
    <input class="form-control form-control-sm bg-dark text-white mb-1" name="reality_pk" id="r_pk" placeholder="Public Key" readonly>
    <input class="form-control form-control-sm bg-dark text-white" name="reality_sk" id="r_sk" placeholder="Private Key" readonly>
</div>
</form></div><div class="modal-footer border-0"><button class="btn btn-primary w-100 py-2 fw-bold" onclick="sub()" data-t="save">Deploy & Get Link</button></div></div></div></div>

<div class="modal fade" id="resModal"><div class="modal-dialog modal-dialog-centered"><div class="modal-content" style="background:var(--bg-card)"><div class="modal-header border-0"><h5 class="modal-title">Connection Info</h5><button class="btn-close btn-close-white" data-bs-dismiss="modal"></button></div><div class="modal-body text-center">
<div class="bg-white p-3 d-inline-block rounded mb-3"><div id="qrcode"></div></div>
<div class="input-group"><input class="form-control bg-dark text-white border-secondary" id="link_txt" readonly><button class="btn btn-success" onclick="copyLink()"><i class="bi bi-clipboard"></i></button></div>
</div></div></div></div>

<script>
const m=new bootstrap.Modal('#addModal'), rm=new bootstrap.Modal('#resModal');
let currId='', lang='en';
const T={
    en:{add:'Add Node',save:'Deploy & Get Link',listen:'Listen IP',list:'Managed Servers',total:'Total',online:'Online'},
    cn:{add:'添加节点',save:'部署并获取链接',listen:'监听接口',list:'被控服务器列表',total:'节点总数',online:'在线数量'}
};
function toggleLang(){lang=lang==='en'?'cn':'en';document.querySelectorAll('[data-t]').forEach(e=>e.innerText=T[lang][e.dataset.t])}
const toast=Swal.mixin({toast:true,position:'top-end',showConfirmButton:false,timer:3000,timerProgressBar:true,background:'#1e293b',color:'#fff'});

function ref(){
    fetch('/api/stats').then(r=>r.json()).then(d=>{
        // Update Master Stats
        document.getElementById('m_cpu').innerText = \`CPU \${d.master.cpu}%\`;
        // Update List
        const l=document.getElementById('list'), r=d.agents;
        l.innerHTML=''; let c=0, v4=0, v6=0;
        for(let u in r){
            c++;
            let tags = '';
            if(r[u].ipv4 && r[u].ipv6) tags+='<span class="badge bg-success bg-opacity-25 text-success border border-success border-opacity-25 me-1">Dual Stack</span>';
            else if(r[u].ipv6) {tags+='<span class="badge bg-warning bg-opacity-25 text-warning border border-warning border-opacity-25 me-1">IPv6 Only</span>'; v6++;}
            else {tags+='<span class="badge bg-info bg-opacity-25 text-info border border-info border-opacity-25 me-1">IPv4 Only</span>'; v4++;}
            
            let conn = r[u].conn_ip.includes(':') ? 'via IPv6' : 'via IPv4';
            let cpu=r[u].cpu||0, mem=r[u].mem||0;
            
            l.innerHTML+=\`
            <div class="col-md-6 col-lg-4"><div class="card h-100">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-start mb-3">
                        <div>
                            <h5 class="fw-bold mb-1" style="cursor:pointer" onclick="ren('\${u}')">\${r[u].name} <i class="bi bi-pencil-fill text-muted fs-6 opacity-50"></i></h5>
                            <div class="d-flex align-items-center"><span class="status-indicator online"></span><span class="small text-muted">\${r[u].ip}</span></div>
                        </div>
                        <span class="badge bg-secondary bg-opacity-25 text-secondary">\${conn}</span>
                    </div>
                    <div class="mb-3">\${tags}</div>
                    <div class="mb-2"><div class="d-flex justify-content-between small mb-1"><span>CPU</span><span>\${cpu}%</span></div><div class="progress"><div class="progress-bar bg-primary" style="width:\${cpu}%"></div></div></div>
                    <div><div class="d-flex justify-content-between small mb-1"><span>RAM</span><span>\${mem}%</span></div><div class="progress"><div class="progress-bar bg-info" style="width:\${mem}%"></div></div></div>
                </div>
                <div class="card-footer bg-transparent border-top border-secondary border-opacity-10 p-3 d-flex gap-2">
                    <button class="btn btn-sm btn-primary flex-grow-1 fw-bold" onclick="pop('\${u}')"><i class="bi bi-plus-lg"></i> Node</button>
                    <button class="btn btn-sm btn-outline-light" onclick="cert('\${u}')" title="SSL"><i class="bi bi-shield-check"></i></button>
                    <a href="http://\${r[u].ip}:\${r[u].xp||2053}" target="_blank" class="btn btn-sm btn-glass"><i class="bi bi-box-arrow-up-right"></i> Panel</a>
                </div>
            </div></div>\`;
        }
        document.getElementById('stat_total').innerText = c;
        document.getElementById('stat_online').innerText = c;
        document.getElementById('stat_v4').innerText = v4;
        document.getElementById('stat_v6').innerText = v6;
        if(c===0) l.innerHTML='<div class="col-12 text-center text-muted py-5"><i class="bi bi-inbox fs-1 d-block mb-3 opacity-25"></i>Waiting for agents to connect...</div>';
    })
}

function pop(u){currId=u;document.getElementById('tuuid').value=u;document.getElementById('uid').value=crypto.randomUUID();up();m.show()}
function ren(u){
    Swal.fire({title:'Rename Server',input:'text',background:'#1e293b',color:'#fff',showCancelButton:true,confirmButtonText:'Save'}).then((r)=>{
        if(r.isConfirmed && r.value){
            fetch('/api/rename',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({uuid:u,name:r.value})}).then(()=>{toast.fire({icon:'success',title:'Renamed'});ref()})
        }
    })
}
function cert(u){
    Swal.fire({title:'Apply SSL Cert',input:'text',inputPlaceholder:'Enter Domain (e.g. vpn.site.com)',background:'#1e293b',color:'#fff',showCancelButton:true,confirmButtonText:'Apply'}).then((r)=>{
        if(r.isConfirmed && r.value){
            Swal.fire({title:'Requesting...',text:'Please wait (~30s)',timer:60000,didOpen:()=>{Swal.showLoading()},background:'#1e293b',color:'#fff'});
            fetch('/api/cert',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:u,domain:r.value})})
            .then(res=>res.json()).then(res=>{
                if(res.success) Swal.fire({icon:'success',title:'Certificate Applied!',background:'#1e293b',color:'#fff'});
                else Swal.fire({icon:'error',title:'Failed',text:res.msg,background:'#1e293b',color:'#fff'});
            })
        }
    })
}

function up(){const n=document.getElementById('net').value,s=document.getElementById('sec').value;document.getElementById('ws').classList.toggle('d-none',n!=='ws');document.getElementById('rea').classList.toggle('d-none',s!=='reality')}
function genUUID(){document.getElementById('uid').value=crypto.randomUUID()}
function getRealKeys(){
    document.getElementById('r_pk').placeholder="Generating...";
    fetch('/api/keys',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:currId})})
    .then(r=>r.json()).then(r=>{if(r.success){document.getElementById('r_pk').value=r.keys.publicKey;document.getElementById('r_sk').value=r.keys.privateKey}else toast.fire({icon:'error',title:r.msg})})
}

function sub(){
    const f=document.getElementById('f'),d=Object.fromEntries(new FormData(f).entries());
    if(d.security==='tls'){d.tls_cert='/root/cert/fullchain.cer';d.tls_key='/root/cert/private.key'}
    fetch('/api/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:currId,config:d})})
    .then(r=>r.json()).then(r=>{
        if(r.success){m.hide();genLink(d, currId);}
        else toast.fire({icon:'error',title:r.msg})
    })
}

function genLink(c, uid){
    fetch('/api/stats').then(r=>r.json()).then(d=>{
        const ip = d.agents[uid].ip;
        let link = "";
        if(c.protocol === 'vless'){
            link = \`vless://\${c.uuid}@\${ip}:\${c.port}?encryption=none&security=\${c.security}&type=\${c.network}\`;
            if(c.security==='reality') link += \`&sni=\${c.reality_sni}&fp=chrome&pbk=\${c.reality_pk}&sid=\`;
            if(c.network==='ws') link += \`&path=\${encodeURIComponent(c.ws_path)}\`;
            link += \`#\${encodeURIComponent(c.remark)}\`;
        } else if(c.protocol === 'vmess'){
            const v = {v:"2",ps:c.remark,add:ip,port:c.port,id:c.uuid,aid:"0",scy:"auto",net:c.network,type:"none",host:"",path:"",tls:""};
            if(c.network==='ws') v.path=c.ws_path;
            if(c.security==='tls') v.tls="tls";
            link = "vmess://" + btoa(JSON.stringify(v));
        }
        document.getElementById('link_txt').value = link;
        document.getElementById('qrcode').innerHTML="";
        new QRCode(document.getElementById("qrcode"), {text:link,width:180,height:180});
        rm.show();
    })
}
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
    
    # Run with Host Pid for monitoring
    docker run -d --name multix-master --network host --restart always \
        --pid host \
        -e MASTER_PORT=${DEFAULT_MASTER_PORT} -e CLUSTER_TOKEN=${TOKEN} multix-master >/dev/null

    echo -e "\n${GREEN}✔ Master 部署成功!${PLAIN}"
    echo -e "   🌐 仪表盘: http://$(curl -s -4 ifconfig.me):${DEFAULT_MASTER_PORT}"
    echo -e "   🔑 Token : ${YELLOW}${TOKEN}${PLAIN} (请妥善保存)"
    echo -e "\n按回车键返回菜单..."
    read
}

# ==================================================
# 2. 安装 Agent (Network Pre-check + Host Monitor)
# ==================================================
install_agent() {
    check_docker
    clear
    echo -e "${CYAN}====================================================${PLAIN}"
    echo -e "${BOLD}   部署 Agent 被控端 (集成 3x-ui + 监控)${PLAIN}"
    echo -e "${CYAN}====================================================${PLAIN}"

    # --- 1. 网络检测 ---
    if docker ps --format '{{.Names}}' | grep -q "^multix-master$"; then
        MASTER_ADDR="127.0.0.1"
        echo -e "${GREEN}>>> [智能检测] 检测到本机运行 Master，使用本地环回连接。${PLAIN}"
    else
        echo -e "\n${BOLD}📡 连接协议选择${PLAIN}"
        echo -e "您的网络环境决定了连接稳定性。如果是 NAT 机，请根据 Master 的 IP 类型选择。"
        echo -e "   [1] IPv4 (默认 - 通用)"
        echo -e "   [2] IPv6 (NAT机/教育网推荐)"
        read -p "选择 [1/2]: " P_OPT
        
        echo -e "\n${BOLD}🌍 Master 地址${PLAIN}"
        read -p "请输入 IP 或 域名: " MASTER_ADDR

        echo -e "\n⏳ 正在进行连通性预检 (Pre-flight Check)..."
        if [[ "$P_OPT" == "2" ]]; then
            ping6 -c 2 -W 2 $MASTER_ADDR >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${RED}❌ 错误: 无法通过 IPv6 连接到 ${MASTER_ADDR}${PLAIN}"
                echo -e "   可能原因: 1. 本机无 IPv6  2. Master 无 IPv6  3. 防火墙拦截"
                read -p "按回车键退出重试..."
                return
            fi
            echo -e "${GREEN}✔ IPv6 网络通畅${PLAIN}"
        else
            ping -c 2 -W 2 $MASTER_ADDR >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${RED}❌ 错误: 无法通过 IPv4 连接到 ${MASTER_ADDR}${PLAIN}"
                read -p "按回车键退出重试..."
                return
            fi
            echo -e "${GREEN}✔ IPv4 网络通畅${PLAIN}"
        fi
    fi

    # --- 2. Token ---
    echo -e "\n${BOLD}🔑 身份验证${PLAIN}"
    read -p "请输入 Master 的 Token: " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/agent
    cd ${APP_DIR}/agent
    if [ ! -f uuid ]; then cat /proc/sys/kernel/random/uuid > uuid; fi
    MY_UUID=$(cat uuid)

    # --- Agent Python Code ---
    cat > agent.py <<EOF
import time, json, socket, os, websocket, requests, threading, psutil

M_ADDR = "${MASTER_ADDR}"
M_PORT = int(os.getenv('MASTER_PORT', 7575))
TOKEN = "${TOKEN}"
AGENT_UUID = "${MY_UUID}"
X_PORT = int(os.getenv('XUI_PORT', 2053))
X_USER = os.getenv('XUI_USER', 'admin')
X_PASS = os.getenv('XUI_PASS', 'admin123')

# Set psutil to read host proc
psutil.PROCFS_PATH = '/host/proc'

WS_URL = f"ws://{M_ADDR}:{M_PORT}/ws"
if ':' in M_ADDR and not M_ADDR.startswith('['): WS_URL = f"ws://[{M_ADDR}]:{M_PORT}/ws"

def xui_api(path, payload={}):
    s = requests.Session()
    try:
        s.post(f"http://127.0.0.1:{X_PORT}/login", data={'username': X_USER, 'password': X_PASS})
        return s.post(f"http://127.0.0.1:{X_PORT}{path}", json=payload).json()
    except Exception as e: return {'success': False, 'msg': str(e)}

def get_sys_status():
    try:
        # Disk usage of host root
        disk = psutil.disk_usage('/hostfs').percent if os.path.exists('/hostfs') else 0
        return {
            'cpu': int(psutil.cpu_percent(interval=None)),
            'mem': int(psutil.virtual_memory().percent),
            'disk': int(disk)
        }
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

            inbound = {
                "enable": True, "remark": c.get('remark'), "port": int(c.get('port')), "protocol": c.get('protocol'), "listen": listen_ip,
                "settings": json.dumps({"clients": [{"id": c.get('uuid'), "email": "m@u"}], "decryption": "none"}),
                "streamSettings": json.dumps(stream),
                "sniffing": json.dumps({"enabled": True, "destOverride": ["http","tls","quic"]})
            }
            ws.send(json.dumps(xui_api("/panel/api/inbounds/add", inbound)))

        elif act == 'apply_cert':
            dom = cmd.get('domain')
            # Using standalone mode on port 80
            if os.system(f"~/.acme.sh/acme.sh --issue -d {dom} --standalone --force") == 0:
                os.system(f"~/.acme.sh/acme.sh --install-cert -d {dom} --key-file /root/cert/private.key --fullchain-file /root/cert/fullchain.cer")
                ws.send(json.dumps({'success': True}))
            else: ws.send(json.dumps({'success': False, 'msg': 'Acme Failed. Check Port 80.'}))

    except Exception as e: ws.send(json.dumps({'success': False, 'msg': str(e)}))

def on_open(ws):
    v4 = True if os.popen("ip -4 a | grep global").read() else False
    v6 = True if os.popen("ip -6 a | grep global").read() else False
    try: pub_ip = requests.get('https://api.ipify.org', timeout=3).text
    except: pub_ip = "Unknown"
    
    info = {'token': TOKEN, 'uuid': AGENT_UUID, 'name': socket.gethostname(), 'ip': pub_ip, 'ipv4': v4, 'ipv6': v6}
    ws.send(json.dumps(info))
    
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
    
    echo -e "\n${GREEN}✔ Agent & 3x-ui 部署成功!${PLAIN}"
    echo -e "   🌐 3x-ui 面板: http://127.0.0.1:${DEFAULT_XUI_PORT}"
    echo -e "   🔗 隧道状态: 正在后台连接 Master..."
    echo -e "\n按回车键返回菜单..."
    read
}

# ==================================================
# 3. 运维功能
# ==================================================
show_logs() {
    clear
    echo -e "${YELLOW}请选择要查看日志的容器:${PLAIN}"
    echo "1. Master"
    echo "2. Agent"
    echo "3. 3x-ui"
    read -p "选择: " OPT
    NAME=""
    case $OPT in
        1) NAME="multix-master" ;;
        2) NAME="multix-agent" ;;
        3) NAME="3x-ui" ;;
    esac
    if [[ -n "$NAME" ]]; then
        echo -e "${CYAN}正在输出 $NAME 日志 (按 Ctrl+C 退出)...${PLAIN}"
        docker logs -f $NAME
    fi
}

manage_docker() {
    ACTION=$1
    if [[ "$ACTION" == "restart" ]]; then
        echo -e "${BLUE}⚡ 正在重启所有服务...${PLAIN}"
        docker restart multix-master multix-agent 3x-ui 2>/dev/null
        echo -e "${GREEN}✔ 重启完成${PLAIN}"
    elif [[ "$ACTION" == "stop" ]]; then
        echo -e "${YELLOW}⛔ 正在停止所有服务...${PLAIN}"
        docker stop multix-master multix-agent 3x-ui 2>/dev/null
        echo -e "${GREEN}✔ 已停止${PLAIN}"
    fi
    sleep 1
}

uninstall() {
    clear
    echo -e "${RED}========================================${PLAIN}"
    echo -e "${BOLD}   ⚠ 危险操作: 卸载 MultiX${PLAIN}"
    echo -e "${RED}========================================${PLAIN}"
    echo -e "1. 仅卸载容器 (保留数据库/证书 - 推荐重装用)"
    echo -e "2. 彻底粉碎数据 (删除 /opt/multix_docker)"
    echo -e "0. 取消"
    read -p "请选择: " OPT
    
    if [[ "$OPT" == "1" ]] || [[ "$OPT" == "2" ]]; then
        echo -e "${YELLOW}正在停止并删除容器...${PLAIN}"
        docker rm -f multix-master 2>/dev/null
        cd ${APP_DIR}/agent 2>/dev/null && docker compose down 2>/dev/null
        
        if [[ "$OPT" == "2" ]]; then
            echo -e "${RED}正在粉碎文件...${PLAIN}"
            rm -rf ${APP_DIR}
        fi
        echo -e "${GREEN}✔ 卸载完成${PLAIN}"
        sleep 2
    fi
}

# ==================================================
# 主菜单 (TUI Dashboard)
# ==================================================
show_menu() {
    while true; do
        get_status
        clear
        echo -e "${CYAN}################################################################${PLAIN}"
        echo -e "${CYAN}#                                                              #${PLAIN}"
        echo -e "${CYAN}#   ${BOLD}MultiX Cluster Manager${PLAIN}${CYAN} [v10.0 Dashboard Edition]           #${PLAIN}"
        echo -e "${CYAN}#   --------------------------------------------------------   #${PLAIN}"
        echo -e "${CYAN}#   * 运行模式: 纯 Docker 容器化部署 (安全/隔离)               #${PLAIN}"
        echo -e "${CYAN}#                                                              #${PLAIN}"
        echo -e "${CYAN}################################################################${PLAIN}"
        echo ""
        echo -e " [ 📦 容器实时状态 ]"
        echo -e " ---------------------------------------------------------------"
        printf " %-30s %-20s %-15s\n" "🟢 Master (主控)" "$M_STATE" "[Mem: $M_MEM]"
        printf " %-30s %-20s %-15s\n" "🔴 Agent  (被控)" "$A_STATE" "[Mem: $A_MEM]"
        echo -e " ---------------------------------------------------------------"
        echo ""
        echo -e " [ 🚀 1. 部署与升级 ]"
        echo -e "  ${BOLD}1.${PLAIN} 安装/更新 Master (主控端)"
        echo -e "  ${BOLD}2.${PLAIN} 安装/更新 Agent  (被控端)"
        echo ""
        echo -e " [ 🛠️ 2. 运维管理 ]"
        echo -e "  ${BOLD}3.${PLAIN} 查看实时日志 (Logs)"
        echo -e "  ${BOLD}4.${PLAIN} 重启容器服务 (Restart)"
        echo -e "  ${BOLD}5.${PLAIN} 停止容器服务 (Stop)"
        echo ""
        echo -e " [ 🗑️ 3. 卸载与清理 ]"
        echo -e "  ${BOLD}9.${PLAIN} 卸载管理 (保留数据 或 彻底粉碎)"
        echo ""
        echo -e " ---------------------------------------------------------------"
        echo -e "  ${BOLD}0.${PLAIN} 退出脚本"
        echo -e " ---------------------------------------------------------------"
        read -p " 请输入选项 [0-9]: " OPT

        case $OPT in
            1) install_master ;;
            2) install_agent ;;
            3) show_logs ;;
            4) manage_docker restart ;;
            5) manage_docker stop ;;
            9) uninstall ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${PLAIN}"; sleep 1 ;;
        esac
    done
}

show_menu
