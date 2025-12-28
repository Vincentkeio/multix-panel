#!/bin/bash

# ==============================================================================
# MultiX Cluster Manager - MVP Test Edition (v9.0)
# ==============================================================================
# 特性：反向 WebSocket、暴力改库、Dashboard 监控、3x-ui 深度集成
# ==============================================================================

INSTALL_PATH="/opt/multix_mvp"
MASTER_PORT=7575
WS_PORT=8888

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "正在安装 Docker..."
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi
}

# ==============================================================================
# 1. 主控安装逻辑
# ==============================================================================
install_master() {
    check_docker
    mkdir -p ${INSTALL_PATH}/master
    cd ${INSTALL_PATH}/master

    # 写入 Master 后端代码
    cat > app.py <<EOF
import json, asyncio, time, psutil, secrets
from flask import Flask, render_template_string, request, jsonify, session
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)
AGENTS = {} # { "ip": { "ws": ws_obj, "stats": {} } }

# 规范化协议模板 (Master 负责拼装)
def build_vless_payload(remark, port, uuid):
    settings = json.dumps({
        "clients": [{"id": uuid, "flow": "xtls-rprx-vision"}],
        "decryption": "none"
    })
    stream_settings = json.dumps({
        "network": "tcp", "security": "reality",
        "realitySettings": {
            "show": False, "dest": "www.microsoft.com:443",
            "serverNames": ["www.microsoft.com"],
            "privateKey": "填写你的私钥", 
            "shortIds": ["abcdef123456"]
        }
    })
    return {
        "action": "sync_node",
        "data": {
            "remark": f"MX-{remark}",
            "port": int(port),
            "protocol": "vless",
            "settings": settings,
            "stream_settings": stream_settings
        }
    }

HTML = """
<!DOCTYPE html>
<html>
<head><title>MultiX Master</title><style>body{background:#1a1a1a;color:#eee;font-family:sans-serif;padding:20px}.card{background:#252525;padding:15px;margin-bottom:10px;border-radius:5px;border:1px solid #333}</style></head>
<body>
    <h2>MultiX Cluster Dashboard</h2>
    <div id="stats">在线被控: {{ agents_count }} | 本机CPU: {{ master_cpu }}%</div>
    <hr>
    <h3>节点下发 (模拟管理)</h3>
    <form action="/send" method="post" class="card">
        端口: <input name="port" value="443" style="width:50px"> 
        备注: <input name="remark" value="TestNode"> 
        UUID: <input name="uuid" value="7e74360e-7443-4903-b09e-71110750a98b">
        <button type="submit">全集群暴力同步</button>
    </form>
    <h3>被控列表</h3>
    {% for ip, info in agents.items() %}
    <div class="card">
        <b>主机: {{ info.stats.name or ip }}</b> [{{ ip }}] <br>
        CPU: {{ info.stats.cpu }}% | MEM: {{ info.stats.mem }}% | BBR: {{ 'ON' if info.stats.bbr else 'OFF' }}
    </div>
    {% endfor %}
</body>
</html>
"""

@app.route('/')
def index():
    m_cpu = psutil.cpu_percent()
    return render_template_string(HTML, agents_count=len(AGENTS), agents=AGENTS, master_cpu=m_cpu)

@app.route('/send', methods=['POST'])
def send_cmd():
    payload = build_vless_payload(request.form['remark'], request.form['port'], request.form['uuid'])
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    async def broadcast():
        for ip in list(AGENTS.keys()):
            try:
                await AGENTS[ip]['ws'].send(json.dumps(payload))
            except: del AGENTS[ip]
    loop.run_until_complete(broadcast())
    return "指令已下发！<a href='/'>返回</a>"

async def ws_server(websocket, path):
    ip = websocket.remote_address[0]
    AGENTS[ip] = {"ws": websocket, "stats": {}}
    try:
        async for msg in websocket:
            data = json.loads(msg)
            if data.get('type') == 'heartbeat':
                AGENTS[ip]['stats'] = data['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

if __name__ == '__main__':
    def run_ws():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        srv = websockets.serve(ws_server, "0.0.0.0", ${WS_PORT})
        loop.run_until_complete(srv)
        loop.run_forever()
    Thread(target=run_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=${MASTER_PORT})
EOF

    # 创建 Dockerfile
    cat > Dockerfile <<EOF
FROM python:3.9-slim
RUN pip install flask websockets psutil
COPY app.py /app.py
CMD ["python", "/app.py"]
EOF

    docker build -t multix-master .
    docker rm -f multix-master 2>/dev/null
    docker run -d --name multix-master --network host --restart always multix-master
    echo -e "${GREEN}主控安装完成！访问 http://IP:${MASTER_PORT}${PLAIN}"
}

# ==============================================================================
# 2. 被控安装逻辑
# ==============================================================================
install_agent() {
    check_docker
    read -p "请输入主控 IP: " M_IP
    mkdir -p ${INSTALL_PATH}/agent/db_data
    cd ${INSTALL_PATH}/agent

    cat > agent.py <<EOF
import asyncio, json, sqlite3, os, shutil, socket, psutil, subprocess
import websockets, docker

MASTER_WS = "ws://${M_IP}:${WS_PORT}"
DB_PATH = "/app/db_share/x-ui.db"

def get_stats():
    return {
        "name": socket.gethostname(),
        "cpu": int(psutil.cpu_percent()),
        "mem": int(psutil.virtual_memory().percent),
        "bbr": "bbr" in subprocess.getoutput("sysctl net.ipv4.tcp_congestion_control")
    }

async def handle_task(data):
    try:
        client = docker.from_env()
        xui = client.containers.get("3x-ui")
        # 1. 停止
        xui.stop()
        # 2. 写库 (暴力逻辑)
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        sql = "INSERT OR REPLACE INTO inbounds (remark, port, protocol, settings, stream_settings, enable, sniffing, listen) VALUES (?, ?, ?, ?, ?, 1, '{\"enabled\": true}', '')"
        cursor.execute(sql, (data['remark'], data['port'], data['protocol'], data['settings'], data['stream_settings']))
        conn.commit(); conn.close()
        # 3. 启动
        xui.start()
        return True
    except Exception as e:
        print(f"Error: {e}"); return False

async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER_WS) as ws:
                print("已连接主控")
                while True:
                    # 心跳
                    await ws.send(json.dumps({"type": "heartbeat", "data": get_stats()}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5)
                        task = json.loads(msg)
                        if task['action'] == 'sync_node':
                            await handle_task(task['data'])
                    except asyncio.TimeoutError:
                        continue
        except:
            print("连接断开，重试中..."); await asyncio.sleep(5)

if __name__ == '__main__':
    asyncio.run(run_agent())
EOF

    # Docker Compose
    cat > docker-compose.yml <<EOF
services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    network_mode: host
    volumes:
      - ./db_data:/etc/x-ui
    restart: always

  multix-agent:
    image: python:3.9-slim
    container_name: multix-agent
    network_mode: host
    privileged: true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./db_data:/app/db_share
      - ./agent.py:/app/agent.py
    working_dir: /app
    entrypoint: /bin/sh -c "pip install docker websockets psutil && python /app.py"
    restart: always
EOF

    docker compose up -d
    echo -e "${GREEN}被控 Agent 及 3x-ui 安装完成！${PLAIN}"
}

# ==============================================================================
# 菜单
# ==============================================================================
echo -e "${YELLOW}MultiX MVP Installer${PLAIN}"
echo "1. 安装主控端 (Master)"
echo "2. 安装被控端 (Agent)"
echo "3. 卸载全部"
read -p "选择 [1-3]: " opt

case $opt in
    1) install_master ;;
    2) install_agent ;;
    3) docker rm -f multix-master multix-agent 3x-ui; rm -rf ${INSTALL_PATH} ;;
esac
