#!/bin/bash

# ==================================================
# MultiX Cluster - v5.2 (Smart Detection)
# ==================================================
APP_DIR="/opt/multix_docker"
# 默认配置
DEFAULT_MASTER_PORT=7575
DEFAULT_XUI_PORT=2053
DEFAULT_XUI_USER="admin"
DEFAULT_XUI_PASS="admin123"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# ==================================================
# 环境检查
# ==================================================
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}>>> 正在安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi
    if ! docker compose version &> /dev/null; then
        apt-get install -y docker-compose-plugin 2>/dev/null || yum install -y docker-compose-plugin 2>/dev/null
    fi
}

# ==================================================
# 1. 安装 Master (仅控制面板)
# ==================================================
install_master() {
    check_docker
    echo -e "${GREEN}>>> 正在部署 Master 主控端...${PLAIN}"
    mkdir -p ${APP_DIR}/master
    cd ${APP_DIR}/master

    # 写入 Server 代码 (v4.0 UI)
    cat > server.py <<EOF
import json, requests, socket, uuid, os
from flask import Flask, request, render_template_string, jsonify

app = Flask(__name__)
agents = {}
PORT = int(os.getenv('MASTER_PORT', 7575))

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="UTF-8"><title>MultiX Manager</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<style>body{background:#141414;color:#fff}.card{background:#1f1f1f;margin-bottom:15px}.online{color:#52c41a}</style>
</head>
<body>
<div class="container mt-4"><h3>MultiX Cluster <small class="text-muted fs-6">v5.2 Smart</small></h3><div class="row" id="list"></div></div>
<div class="modal fade" id="addModal"><div class="modal-dialog"><div class="modal-content"><div class="modal-header"><h5 class="modal-title">Add Node</h5><button class="btn-close" data-bs-dismiss="modal"></button></div><div class="modal-body">
<form id="f"><input type="hidden" id="ip"><div class="mb-2"><label>Remark</label><input class="form-control" name="remark"></div>
<div class="row"><div class="col"><label>Proto</label><select class="form-select" name="protocol" id="pro" onchange="up()"><option value="vless">VLESS</option><option value="vmess">VMess</option></select></div><div class="col"><label>Port</label><input type="number" class="form-control" name="port"></div></div>
<div class="mb-2"><label>UUID</label><input class="form-control" name="uuid" id="uid"></div>
<div class="row"><div class="col"><label>Net</label><select class="form-select" name="network" id="net" onchange="up()"><option value="tcp">TCP</option><option value="ws">WS</option></select></div><div class="col"><label>Sec</label><select class="form-select" name="security" id="sec" onchange="up()"><option value="none">None</option><option value="reality">REALITY</option></select></div></div>
<div id="ws" class="d-none"><input class="form-control mt-2" name="ws_path" placeholder="Path"></div>
<div id="rea" class="d-none mt-2"><input class="form-control mb-1" name="reality_sni" placeholder="SNI"><input class="form-control" name="reality_dest" placeholder="Dest"></div>
</form></div><div class="modal-footer"><button class="btn btn-primary" onclick="sub()">Save</button></div></div></div></div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
let d={};const m=new bootstrap.Modal('#addModal');
function ref(){fetch('/api/agents').then(r=>r.json()).then(r=>{d=r;document.getElementById('list').innerHTML='';for(let i in d){
document.getElementById('list').innerHTML+=\`<div class="col-md-4"><div class="card p-3"><h5>\${d[i].name} <span class="online">●</span></h5><p>\${i}</p><button class="btn btn-primary btn-sm" onclick="pop('\${i}')">Add</button> <a href="http://\${i}:\${d[i].xp||2053}" target="_blank" class="btn btn-outline-secondary btn-sm">Panel</a></div></div>\`}})}
function pop(i){document.getElementById('ip').value=i;document.getElementById('uid').value=crypto.randomUUID();up();m.show()}
function up(){const p=document.getElementById('pro').value,n=document.getElementById('net').value,s=document.getElementById('sec').value;
document.getElementById('ws').classList.toggle('d-none',n!=='ws');document.getElementById('rea').classList.toggle('d-none',s!=='reality')}
function sub(){const f=document.getElementById('f'),o=Object.fromEntries(new FormData(f).entries());o.target=document.getElementById('ip').value;
fetch('/api/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({target:o.target,config:o})}).then(r=>r.json()).then(r=>{if(r.success){alert('OK');m.hide()}else alert(r.msg)})}
setInterval(ref,3000);ref();
</script></body></html>
"""

@app.route('/')
def index(): return render_template_string(HTML_TEMPLATE)

@app.route('/api/heartbeat', methods=['POST'])
def hb():
    ip = request.remote_addr
    data = request.json
    agents[ip] = {'name': data.get('name'), 'xp': data.get('xp')}
    return jsonify({'status':'ok'})

@app.route('/api/agents')
def get_agents(): return jsonify(agents)

@app.route('/api/push', methods=['POST'])
def push():
    data = request.json
    target = data.get('target')
    url = f"http://[{target}]:{PORT}/agent/add" if ':' in target else f"http://{target}:{PORT}/agent/add"
    if target == '127.0.0.1': url = f"http://127.0.0.1:{PORT}/agent/add"
    try:
        r = requests.post(url, json=data.get('config'), timeout=5)
        return jsonify(r.json())
    except Exception as e:
        return jsonify({'success': False, 'msg': str(e)})

if __name__ == '__main__':
    app.run(host='::', port=PORT)
EOF

    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install flask requests" >> Dockerfile
    echo "COPY server.py ." >> Dockerfile
    echo "CMD [\"python\", \"server.py\"]" >> Dockerfile

    docker build -t multix-master .
    docker rm -f multix-master 2>/dev/null
    
    docker run -d \
        --name multix-master \
        --network host \
        --restart always \
        -e MASTER_PORT=${DEFAULT_MASTER_PORT} \
        multix-master

    echo -e "${GREEN}Master 主控端安装完成！${PLAIN}"
    echo -e "管理面板地址: http://$(curl -s -4 ifconfig.me):${DEFAULT_MASTER_PORT}"
}

# ==================================================
# 2. 安装 Agent (智能检测版)
# ==================================================
install_agent() {
    check_docker
    echo -e "${GREEN}>>> 正在部署 Agent 被控端 (含 3x-ui)...${PLAIN}"
    
    # --- 智能检测逻辑 START ---
    if docker ps --format '{{.Names}}' | grep -q "^multix-master$"; then
        # 如果发现本机运行了 Master，自动设置为本地连接
        MASTER_IP="127.0.0.1"
        
        # 尝试从 Master 容器获取当前运行的端口 (防止用户修改过端口)
        DETECTED_PORT=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' multix-master | grep MASTER_PORT | cut -d= -f2)
        if [[ -n "$DETECTED_PORT" ]]; then
            DEFAULT_MASTER_PORT=$DETECTED_PORT
        fi
        
        echo -e "${GREEN}>>> [智能检测] 本机运行中 Master (端口 ${DEFAULT_MASTER_PORT})${PLAIN}"
        echo -e "${YELLOW}>>> 已自动跳过配置，Agent 将直接连接: 127.0.0.1${PLAIN}"
        sleep 1
    else
        # 没发现 Master，说明是远程机，正常询问
        echo -e "${YELLOW}请输入 Master (主控) 的 域名 或 IP 地址:${PLAIN}"
        echo -e "例如: vpn.example.com 或 1.2.3.4 (无需 http 前缀)"
        read -p "Address: " MASTER_IP
        [[ -z "${MASTER_IP}" ]] && echo "地址不能为空" && return
    fi
    # --- 智能检测逻辑 END ---

    mkdir -p ${APP_DIR}/agent
    cd ${APP_DIR}/agent

    # Agent 代码
    cat > agent.py <<EOF
import time, requests, json, socket, os
from flask import Flask, request, jsonify

app = Flask(__name__)
M_IP = "${MASTER_IP}"
M_PORT = int(os.getenv('MASTER_PORT', 7575)) 
MY_PORT = int(os.getenv('MASTER_PORT', 7575)) 
X_PORT = int(os.getenv('XUI_PORT', 2053))
X_USER = os.getenv('XUI_USER', 'admin')
X_PASS = os.getenv('XUI_PASS', 'admin123')

def get_session():
    s = requests.Session()
    try: s.post(f"http://127.0.0.1:{X_PORT}/login", data={'username': X_USER, 'password': X_PASS})
    except: pass
    return s

@app.route('/agent/add', methods=['POST'])
def add():
    c = request.json
    stream = {"network": c.get('network'), "security": c.get('security'), "wsSettings": {}, "tcpSettings": {}}
    if c.get('network') == 'ws': stream['wsSettings'] = {"path": c.get('ws_path'), "headers": {"Host": ""}}
    if c.get('security') == 'reality':
        stream['realitySettings'] = {"show": False, "dest": c.get('reality_dest'), "serverNames": [c.get('reality_sni')], "shortIds": [""]}
    
    inbound = {
        "enable": True, "remark": c.get('remark'), "port": int(c.get('port')), "protocol": c.get('protocol'),
        "settings": json.dumps({"clients": [{"id": c.get('uuid'), "email": "m@u"}], "decryption": "none"}),
        "streamSettings": json.dumps(stream),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http","tls","quic"]})
    }
    try:
        r = get_session().post(f"http://127.0.0.1:{X_PORT}/panel/api/inbounds/add", json=inbound)
        return jsonify(r.json())
    except Exception as e: return jsonify({'success': False, 'msg': str(e)})

def beat():
    while True:
        try:
            u = f"http://[{M_IP}]:{M_PORT}/api/heartbeat" if ':' in M_IP else f"http://{M_IP}:{M_PORT}/api/heartbeat"
            requests.post(u, json={'name': socket.gethostname(), 'xp': X_PORT}, timeout=5)
        except: pass
        time.sleep(10)

if __name__ == '__main__':
    import threading
    threading.Thread(target=beat).start()
    app.run(host='::', port=MY_PORT)
EOF

    echo "FROM python:3.9-slim" > Dockerfile
    echo "RUN pip install flask requests" >> Dockerfile
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
EOF
    
    docker compose pull
    docker compose up -d --build

    echo -e "${GREEN}Agent 安装完成！${PLAIN}"
    echo -e "本机 3x-ui 面板: http://127.0.0.1:${DEFAULT_XUI_PORT}"
}

# ==================================================
# 3. 卸载功能
# ==================================================
uninstall() {
    echo -e "${RED}>>> 警告：即将卸载。${PLAIN}"
    echo "1. 仅卸载 Master (保留 3x-ui)"
    echo "2. 仅卸载 Agent & 3x-ui (保留 Master)"
    echo "3. 全部卸载 (清空)"
    read -p "选择: " OPT
    
    case $OPT in
        1|3) 
            docker rm -f multix-master 2>/dev/null
            rm -rf ${APP_DIR}/master
            echo "Master 已卸载" ;;
    esac
    case $OPT in
        2|3)
            cd ${APP_DIR}/agent 2>/dev/null
            if [ -f "docker-compose.yml" ]; then docker compose down; fi
            rm -rf ${APP_DIR}/agent
            echo "Agent 已卸载" ;;
    esac
}

# ==================================================
# 4. 配置修改
# ==================================================
modify_config() {
    echo -e "${BLUE}>>> 修改配置${PLAIN}"
    echo "1. 修改 MultiX 面板端口 (默认 7575)"
    echo "2. 修改 3x-ui 面板端口 (默认 2053)"
    echo "3. 修改 3x-ui 账号密码"
    read -p "请选择: " OPT

    case $OPT in
        1)
            read -p "新 MultiX 端口: " P
            if docker ps | grep -q multix-master; then
                docker rm -f multix-master
                docker run -d --name multix-master --network host --restart always -e MASTER_PORT=$P multix-master
            fi
            if [ -f "${APP_DIR}/agent/docker-compose.yml" ]; then
                sed -i "s/MASTER_PORT=.*/MASTER_PORT=$P/" ${APP_DIR}/agent/docker-compose.yml
                cd ${APP_DIR}/agent && docker compose up -d
            fi
            echo "端口已修改，请使用新端口访问。"
            ;;
        2)
            read -p "新 3x-ui 端口: " P
            docker exec -it 3x-ui x-ui setting -port $P
            docker restart 3x-ui
            echo "3x-ui 端口已修改。"
            ;;
        3)
            read -p "新用户名: " U
            read -p "新密码: " P
            docker exec -it 3x-ui x-ui setting -username $U -password $P
            docker restart 3x-ui
            echo "账号密码已修改。"
            ;;
    esac
}

show_menu() {
    clear
    echo -e "${BLUE}MultiX Cluster v5.2 (Smart Mode)${PLAIN}"
    echo -e "1. 安装 Master"
    echo -e "2. 安装 Agent (自动检测主控)"
    echo -e "3. 修改配置"
    echo -e "4. 卸载"
    echo -e "---------------------------"
    echo -e "提示: 域名/IP 请直接输入 (如 vpn.com)，无需 http://"
    read -p "选择: " OPT
    case $OPT in
        1) install_master ;;
        2) install_agent ;;
        3) modify_config ;;
        4) uninstall ;;
        *) exit 0 ;;
    esac
}

show_menu
