#!/bin/bash

# ==================================================
# MultiX Cluster - v9.0 (Link Export / QR / Full Features)
# ==================================================
APP_DIR="/opt/multix_docker"
DEFAULT_MASTER_PORT=7575
DEFAULT_XUI_PORT=2053
DEFAULT_TOKEN="my_secret_888"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}>>> 安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl start docker; systemctl enable docker
    fi
    if ! docker compose version &> /dev/null; then
        apt-get install -y docker-compose-plugin 2>/dev/null || yum install -y docker-compose-plugin 2>/dev/null
    fi
}

# ==================================================
# 1. 安装 Master (支持 链接生成/二维码/多语言)
# ==================================================
install_master() {
    check_docker
    echo -e "${GREEN}>>> 部署 Master (v9.0 Ultimate)...${PLAIN}"
    
    echo -e "${YELLOW}设置通信密钥 (Cluster Token):${PLAIN}"
    read -p "Token (默认 ${DEFAULT_TOKEN}): " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/master
    cd ${APP_DIR}/master

    cat > server.py <<EOF
import json, os, socket
from flask import Flask, render_template_string, request, jsonify
from flask_sock import Sock

app = Flask(__name__)
sock = Sock(app)
PORT = int(os.getenv('MASTER_PORT', 7575))
TOKEN = os.getenv('CLUSTER_TOKEN', 'my_secret_888')

clients = {}
client_info = {}

# --- WebSocket 隧道 ---
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
        # 解析连接来源 IP
        conn_ip = request.remote_addr
        # 如果 Agent 上报了 IPv6 优先，则标记
        if info.get('report_ip'): conn_ip = info.get('report_ip')
        
        info['conn_ip'] = conn_ip
        clients[agent_id] = ws
        client_info[agent_id] = info
        print(f"Agent Online: {info.get('name')} via {conn_ip}")
        
        while True:
            # 接收 Agent 上报的实时状态 (CPU/Mem/Net)
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

# --- API 接口 ---
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
    # DNS 预检 (略微简化，以实测为准)
    try:
        clients[tid].send(json.dumps({'action': 'apply_cert', 'domain': domain}))
        return jsonify(json.loads(clients[tid].receive(timeout=60)))
    except Exception as e: return jsonify({'success': False, 'msg': str(e)})

@app.route('/api/rename', methods=['POST'])
def rename():
    # 简单的内存重命名，重启失效。如需持久化需挂载文件，此处为演示逻辑
    tid = request.json.get('uuid')
    name = request.json.get('name')
    if tid in client_info: client_info[tid]['name'] = name
    return jsonify({'success': True})

@app.route('/api/agents')
def get_agents(): return jsonify(client_info)

HTML_TEMPLATE = """
<!DOCTYPE html><html lang="en" data-bs-theme="dark"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>MultiX v9.0</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
body{background:#141414;color:#e0e0e0;font-family:'Segoe UI',Roboto,sans-serif}
.navbar{background:#1f1f1f;border-bottom:1px solid #333}
.card{background:#1f1f1f;border:1px solid #333;margin-bottom:15px;transition:all 0.2s}
.card:hover{border-color:#555}
.progress{height:6px;background:#333;margin-bottom:10px}
.online{color:#52c41a;text-shadow:0 0 5px #52c41a}
.badge-v4{background:#0d6efd}.badge-v6{background:#6610f2}.badge-dual{background:#198754}
</style>
</head><body>

<nav class="navbar navbar-expand-lg navbar-dark mb-4 px-3">
  <div class="d-flex w-100 justify-content-between align-items-center">
    <div class="navbar-brand"><i class="bi bi-hdd-network"></i> MultiX <span class="badge bg-danger fs-6" style="vertical-align:top">v9.0</span></div>
    <div><button class="btn btn-sm btn-outline-secondary me-2" onclick="toggleLang()" id="langBtn">CN/EN</button></div>
  </div>
</nav>

<div class="container">
    <div class="d-flex justify-content-between mb-3"><h5 id="t_list">Server List</h5><span class="text-muted" id="agent_count">0 Online</span></div>
    <div class="row" id="list"></div>
</div>

<div class="modal fade" id="addModal"><div class="modal-dialog"><div class="modal-content"><div class="modal-header"><h5 class="modal-title" id="t_add">Add Node</h5><button class="btn-close" data-bs-dismiss="modal"></button></div>
<div class="modal-body"><form id="f"><input type="hidden" id="tuuid">
<div class="mb-2"><label>Remark</label><input class="form-control" name="remark" value="MultiX-Node"></div>
<div class="row g-2 mb-2"><div class="col"><label>Protocol</label><select class="form-select" name="protocol"><option value="vless">VLESS</option><option value="vmess">VMess</option></select></div><div class="col"><label>Port</label><input type="number" class="form-control" name="port"></div></div>
<div class="mb-2"><label>UUID</label><div class="input-group"><input class="form-control" name="uuid" id="uid"><button type="button" class="btn btn-outline-secondary" onclick="genUUID()"><i class="bi bi-arrow-repeat"></i></button></div></div>
<div class="mb-2"><label>Listen IP</label><select class="form-select" name="listen"><option value="">🌐 Dual Stack (v4+v6) [Default]</option><option value="0.0.0.0">4️⃣ IPv4 Only (0.0.0.0)</option><option value="::">6️⃣ IPv6 Only (::)</option></select></div>
<div class="row g-2 mb-2"><div class="col"><label>Network</label><select class="form-select" name="network" id="net" onchange="up()"><option value="tcp">TCP</option><option value="ws">WS</option></select></div><div class="col"><label>Security</label><select class="form-select" name="security" id="sec" onchange="up()"><option value="none">None</option><option value="reality">REALITY</option><option value="tls">TLS</option></select></div></div>
<div id="ws" class="d-none mb-2"><input class="form-control" name="ws_path" placeholder="Path (e.g. /ws)"></div>
<div id="rea" class="d-none mb-2 p-2 border border-secondary rounded">
    <label class="text-warning small">Reality Settings</label>
    <div class="input-group mb-2"><button class="btn btn-outline-warning btn-sm" type="button" onclick="getRealKeys()">Generate Keys</button></div>
    <input class="form-control mb-1 form-control-sm" name="reality_dest" value="www.microsoft.com:443" placeholder="Dest">
    <input class="form-control mb-1 form-control-sm" name="reality_sni" value="www.microsoft.com" placeholder="SNI">
    <input class="form-control mb-1 form-control-sm" name="reality_pk" id="r_pk" placeholder="Public Key" readonly>
    <input class="form-control form-control-sm" name="reality_sk" id="r_sk" placeholder="Private Key" readonly>
</div>
</form></div><div class="modal-footer"><button class="btn btn-primary w-100" onclick="sub()" id="t_save">Save & Get Link</button></div></div></div></div>

<div class="modal fade" id="resModal"><div class="modal-dialog"><div class="modal-content"><div class="modal-header"><h5 class="modal-title">Export Link</h5><button class="btn-close" data-bs-dismiss="modal"></button></div>
<div class="modal-body text-center">
    <div id="qrcode" class="d-flex justify-content-center mb-3"></div>
    <textarea class="form-control mb-2" id="link_txt" rows="3" onclick="this.select()" readonly></textarea>
    <button class="btn btn-success" onclick="copyLink()"><i class="bi bi-clipboard"></i> Copy Link</button>
</div></div></div></div>

<div class="modal fade" id="renModal"><div class="modal-dialog modal-sm"><div class="modal-content"><div class="modal-body"><input class="form-control" id="new_name" placeholder="New Name"><button class="btn btn-primary mt-2 w-100" onclick="doRen()">Save</button></div></div></div></div>

<div class="modal fade" id="certModal"><div class="modal-dialog"><div class="modal-content"><div class="modal-header"><h5 class="modal-title">Apply SSL</h5><button class="btn-close" data-bs-dismiss="modal"></button></div>
<div class="modal-body"><input class="form-control" id="domain" placeholder="Domain (e.g. vpn.site.com)"></div><div class="modal-footer"><button class="btn btn-success" onclick="applyCert()">Apply</button></div></div></div></div>

<script>
const m=new bootstrap.Modal('#addModal'), rm=new bootstrap.Modal('#resModal'), nm=new bootstrap.Modal('#renModal'), cm=new bootstrap.Modal('#certModal');
let currId='', lang='en';
const TXT={en:{list:'Server List',add:'Add Node',save:'Save & Get Link'},cn:{list:'服务器列表',add:'添加节点',save:'保存并获取链接'}};

function toggleLang(){lang=lang==='en'?'cn':'en';document.getElementById('t_list').innerText=TXT[lang].list;document.getElementById('t_add').innerText=TXT[lang].add;document.getElementById('t_save').innerText=TXT[lang].save}
function ref(){fetch('/api/agents').then(r=>r.json()).then(r=>{const l=document.getElementById('list');l.innerHTML='';let c=0;for(let u in r){
c++;
let b='badge-secondary',t='Unknown';
if(r[u].ipv4 && r[u].ipv6){b='badge-dual';t='Dual Stack'}else if(r[u].ipv6){b='badge-v6';t='IPv6 Only'}else{b='badge-v4';t='IPv4 Only'}
let con='IPv4';if(r[u].conn_ip && r[u].conn_ip.includes(':'))con='IPv6';
let cpu=r[u].cpu||0, mem=r[u].mem||0, disk=r[u].disk||0;
l.innerHTML+=\`<div class="col-md-6 col-lg-4"><div class="card p-3">
<div class="d-flex justify-content-between align-items-center mb-2">
  <h5 class="m-0 text-truncate" style="max-width:180px" onclick="ren('\${u}')" role="button">\${r[u].name} <i class="bi bi-pencil-square text-muted small"></i></h5>
  <span class="online small"><i class="bi bi-circle-fill"></i> Online</span>
</div>
<div class="mb-2"><span class="badge \${b}">\${t}</span> <span class="badge bg-dark border border-secondary">via \${con}</span></div>
<div class="small text-muted mb-2">IP: \${r[u].ip}</div>
<div class="small mb-1">CPU \${cpu}%</div><div class="progress"><div class="progress-bar bg-info" style="width:\${cpu}%"></div></div>
<div class="small mb-1">RAM \${mem}%</div><div class="progress"><div class="progress-bar bg-warning" style="width:\${mem}%"></div></div>
<div class="d-flex gap-2 mt-3">
    <button class="btn btn-primary flex-grow-1 btn-sm" onclick="pop('\${u}')"><i class="bi bi-plus-lg"></i> Node</button>
    <button class="btn btn-outline-success btn-sm" onclick="cert('\${u}')" title="SSL"><i class="bi bi-shield-lock"></i></button>
    <a href="http://\${r[u].ip}:\${r[u].xp||2053}" target="_blank" class="btn btn-outline-secondary btn-sm"><i class="bi bi-box-arrow-up-right"></i></a>
</div></div></div>\`}
document.getElementById('agent_count').innerText=c+' Online';
if(c===0)l.innerHTML='<div class="text-center text-muted py-5">Waiting for Agents...</div>'})}

function pop(u){currId=u;document.getElementById('tuuid').value=u;document.getElementById('uid').value=crypto.randomUUID();document.getElementById('r_pk').value='';document.getElementById('r_sk').value='';up();m.show()}
function cert(u){currId=u;cm.show()}
function ren(u){currId=u;nm.show()}
function doRen(){const n=document.getElementById('new_name').value;if(n)fetch('/api/rename',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({uuid:currId,name:n})}).then(()=>{nm.hide();ref()})}

function up(){const n=document.getElementById('net').value,s=document.getElementById('sec').value;document.getElementById('ws').classList.toggle('d-none',n!=='ws');document.getElementById('rea').classList.toggle('d-none',s!=='reality')}
function genUUID(){document.getElementById('uid').value=crypto.randomUUID()}

function getRealKeys(){
    document.getElementById('r_pk').placeholder="Generating...";
    fetch('/api/keys',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:currId})})
    .then(r=>r.json()).then(r=>{if(r.success){document.getElementById('r_pk').value=r.keys.publicKey;document.getElementById('r_sk').value=r.keys.privateKey}else alert(r.msg)})
}

function sub(){
    const f=document.getElementById('f'),d=Object.fromEntries(new FormData(f).entries());
    if(d.security==='tls'){d.tls_cert='/root/cert/fullchain.cer';d.tls_key='/root/cert/private.key'}
    fetch('/api/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:currId,config:d})})
    .then(r=>r.json()).then(r=>{
        if(r.success){
            m.hide();
            genLink(d, currId); // Generate Link
        }else alert(r.msg)
    })
}

function genLink(c, uid){
    // 获取 Agent IP
    fetch('/api/agents').then(r=>r.json()).then(ag=>{
        const ip = ag[uid].ip;
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

function copyLink(){document.getElementById('link_txt').select();document.execCommand('copy');alert('Copied!')}
function applyCert(){const d=document.getElementById('domain').value;if(!d)return;alert('Requesting... wait 20s');fetch('/api/cert',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target_uuid:currId,domain:d})}).then(r=>r.json()).then(r=>{if(r.success){alert('Success!');cm.hide()}else alert('Fail: '+r.msg)})}
setInterval(ref,3000);ref();
</script></body></html>
"""
@app.route('/')
def index(): return render_template_string(HTML_TEMPLATE)
if __name__ == '__main__': app.run(host='::', port=PORT, threaded=True)
EOF

    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install flask flask-sock requests simple-websocket" >> Dockerfile
    echo "COPY server.py ." >> Dockerfile
    echo "CMD [\"python\", \"server.py\"]" >> Dockerfile

    docker build -t multix-master .
    docker rm -f multix-master 2>/dev/null
    docker run -d --name multix-master --network host --restart always \
        -e MASTER_PORT=${DEFAULT_MASTER_PORT} -e CLUSTER_TOKEN=${TOKEN} multix-master

    echo -e "${GREEN}Master 安装完成。${PLAIN}"
    echo -e "访问: http://$(curl -s -4 ifconfig.me):${DEFAULT_MASTER_PORT}"
    echo -e "Token: ${YELLOW}${TOKEN}${PLAIN}"
}

# ==================================================
# 2. 安装 Agent (支持资源监控/密钥生成)
# ==================================================
install_agent() {
    check_docker
    echo -e "${GREEN}>>> 部署 Agent (v9.0)...${PLAIN}"

    if docker ps --format '{{.Names}}' | grep -q "^multix-master$"; then
        MASTER_ADDR="127.0.0.1"
    else
        echo -e "${YELLOW}请选择连接 Master 的协议:${PLAIN}"
        echo -e "[1] IPv4 (默认)   [2] IPv6 (NAT机推荐)"
        read -p "选择: " P_OPT
        echo -e "${YELLOW}请输入 Master 域名/IP:${PLAIN}"
        read -p "Address: " MASTER_ADDR
        # 简单预检
        if [[ "$P_OPT" == "2" ]]; then
            ping6 -c 1 -W 2 $MASTER_ADDR >/dev/null 2>&1
            if [ $? -ne 0 ]; then echo -e "${RED}IPv6 连接测试失败！请检查地址或网络。${PLAIN}"; return; fi
        else
            ping -c 1 -W 2 $MASTER_ADDR >/dev/null 2>&1
            if [ $? -ne 0 ]; then echo -e "${RED}IPv4 连接测试失败！${PLAIN}"; return; fi
        fi
    fi

    echo -e "${YELLOW}请输入通信密钥 (Token):${PLAIN}"
    read -p "Token: " TOKEN
    [[ -z "$TOKEN" ]] && TOKEN="${DEFAULT_TOKEN}"

    mkdir -p ${APP_DIR}/agent
    cd ${APP_DIR}/agent
    if [ ! -f uuid ]; then cat /proc/sys/kernel/random/uuid > uuid; fi
    MY_UUID=$(cat uuid)

    # Agent 代码
    cat > agent.py <<EOF
import time, json, socket, os, websocket, requests, threading, psutil

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
    except Exception as e: return {'success': False, 'msg': str(e)}

def get_sys_status():
    # 因为挂载了 /host/proc 和 /hostfs，这里尝试读取宿主机信息
    # 注意：在容器内 psutil 默认读容器信息，除非正确配置了挂载
    # 这里做简化，直接读取 psutil，因为 docker-compose 挂载了 /proc
    return {
        'cpu': int(psutil.cpu_percent(interval=None)),
        'mem': int(psutil.virtual_memory().percent),
        'disk': int(psutil.disk_usage('/hostfs').percent) if os.path.exists('/hostfs') else 0
    }

def on_message(ws, message):
    try:
        cmd = json.loads(message)
        act = cmd.get('action')
        
        if act == 'get_keys':
            # 调用 3x-ui 生成真实密钥
            res = xui_api("/server/getNewX25519Cert")
            if res.get('success'): ws.send(json.dumps({'success': True, 'keys': res.get('obj')}))
            else: ws.send(json.dumps({'success': False, 'msg': 'Gen Failed'}))

        elif act == 'add_node':
            c = cmd.get('data')
            stream = {"network": c.get('network'), "security": c.get('security'), "wsSettings": {}, "tcpSettings": {}}
            if c.get('network') == 'ws': stream['wsSettings'] = {"path": c.get('ws_path'), "headers": {"Host": ""}}
            if c.get('security') == 'reality': stream['realitySettings'] = {"show": False, "dest": c.get('reality_dest'), "serverNames": [c.get('reality_sni')], "shortIds": [""]}
            if c.get('security') == 'tls': stream['tlsSettings'] = {"certificates": [{"certificateFile": c.get('tls_cert'), "keyFile": c.get('tls_key')}]}
            
            # Listen IP 处理
            listen_ip = "" # Default dual
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
            if os.system(f"~/.acme.sh/acme.sh --issue -d {dom} --standalone --force") == 0:
                os.system(f"~/.acme.sh/acme.sh --install-cert -d {dom} --key-file /root/cert/private.key --fullchain-file /root/cert/fullchain.cer")
                ws.send(json.dumps({'success': True}))
            else: ws.send(json.dumps({'success': False, 'msg': 'Acme Failed'}))

    except Exception as e: ws.send(json.dumps({'success': False, 'msg': str(e)}))

def on_open(ws):
    # 环境识别
    v4 = True if os.popen("ip -4 a | grep global").read() else False
    v6 = True if os.popen("ip -6 a | grep global").read() else False
    try: pub_ip = requests.get('https://api.ipify.org', timeout=3).text
    except: pub_ip = "Unknown"
    
    info = {'token': TOKEN, 'uuid': AGENT_UUID, 'name': socket.gethostname(), 'ip': pub_ip, 'ipv4': v4, 'ipv6': v6}
    ws.send(json.dumps(info))
    
    # 开启心跳上报线程
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
    
    docker compose pull
    docker compose up -d --build
    echo -e "${GREEN}Agent 安装完成！${PLAIN}"
}

# ==================================================
# 菜单
# ==================================================
show_menu() {
    clear
    echo -e "${BLUE}MultiX v9.0 Ultimate${PLAIN}"
    echo "1. 安装 Master (服务端)"
    echo "2. 安装 Agent  (客户端)"
    echo "3. 卸载"
    read -p "选择: " OPT
    case $OPT in
        1) install_master ;;
        2) install_agent ;;
        3) docker rm -f multix-master 2>/dev/null; cd ${APP_DIR}/agent && docker compose down ;;
        *) exit 0 ;;
    esac
}

show_menu
