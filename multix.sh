#!/bin/bash
# MultiX MVP V3.5 - 数据库字段修复 + 3x-ui 环境自建版
# 适用：NAT小鸡、IPv6双栈、mhsanaei/3x-ui 容器版

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top"

# 颜色
G='\033[0;32m'
R='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V3.5        "
    echo -e "    适配 mhsanaei/3x-ui 容器版    "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 🗑️  卸载 主控端 (Master)"
    echo "----------------------------------"
    echo "3. 📡 安装/重装 被控端 (Agent + 3x-ui)"
    echo "4. 🗑️  卸载 被控端 (Agent)"
    echo "----------------------------------"
    echo "5. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [1-5]: " choice
}

install_master() {
    echo -e "${G}[+] 正在加固主控环境...${NC}"
    mkdir -p ${INSTALL_PATH}/master
    apt update && apt install -y python3 python3-pip net-tools
    pip3 install flask websockets psutil --break-system-packages --quiet || pip3 install flask websockets psutil --quiet

    cat > ${INSTALL_PATH}/master/app.py <<'EOF'
import json, asyncio, time, psutil, secrets, os
from flask import Flask, render_template_string, request
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)
AGENTS = {} 
LOOP = None

def generate_xui_sql(remark, port, protocol, uuid):
    sniffing = {"enabled": True, "destOverride": ["http", "tls", "quic"]}
    settings = {"clients": [{"id": uuid, "flow": "xtls-rprx-vision"}], "decryption": "none"}
    stream_settings = {"network": "tcp", "security": "reality", "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": "YOUR_KEY", "shortIds": ["abcdef123456"]}}
    return {"remark": f"MX-{remark}", "port": int(port), "protocol": protocol, "settings": json.dumps(settings), "stream_settings": json.dumps(stream_settings), "sniffing": json.dumps(sniffing)}

HTML = """
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>MultiX V3.5</title>
<style>body{background:#1a1a1a;color:white;padding:20px} .card{background:#252525;padding:15px;border-radius:8px;margin-bottom:20px;border:1px solid #444} input{background:#333;color:white;border:1px solid #555;padding:8px;margin:5px;border-radius:4px} .btn{background:#177ddc;color:white;border:none;padding:10px 20px;border-radius:4px;cursor:pointer}</style></head>
<body>
    <h2>🛰️ MultiX V3.5 控制台</h2>
    <div class="card">
        <h3>在线节点: {{ agents_count }}</h3>
        {% for ip, info in agents.items() %}
        <div style="padding:5px;border-bottom:1px solid #333">🌐 {{ ip }} | CPU: {{ info.stats.cpu }}% | MEM: {{ info.stats.mem }}%</div>
        {% endfor %}
    </div>
    <div class="card">
        <form action="/send" method="post">
            备注: <input name="remark" value="V35_Test"> 端口: <input name="port" value="12345"> UUID: <input name="uuid" value="{{ default_uuid }}" style="width:300px"><br><br>
            <button type="submit" class="btn">🚀 全集群一键同步</button>
        </form>
    </div>
</body></html>
"""

@app.route('/')
def index():
    return render_template_string(HTML, agents_count=len(AGENTS), agents=AGENTS, default_uuid=secrets.token_hex(16))

@app.route('/send', methods=['POST'])
def send_cmd():
    try:
        node_data = generate_xui_sql(request.form['remark'], request.form['port'], "vless", request.form['uuid'])
        payload = json.dumps({"action": "sync_node", "data": node_data})
        if LOOP:
            for ip in list(AGENTS.keys()):
                LOOP.call_soon_threadsafe(asyncio.create_task, AGENTS[ip]['ws'].send(payload))
            return "✅ 已发送指令！<a href='/' style='color:white'>返回</a>"
    except Exception as e: return f"错误：{e}"

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
    try:
        async for msg in websocket:
            data = json.loads(msg)
            if data.get('type') == 'heartbeat': AGENTS[ip]['stats'] = data['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

async def start_ws():
    global LOOP
    LOOP = asyncio.get_running_loop()
    async with websockets.serve(ws_server, "::", 8888):
        await asyncio.Future()

if __name__ == '__main__':
    Thread(target=lambda: asyncio.run(start_ws()), daemon=True).start()
    app.run(host='0.0.0.0', port=7575)
EOF

    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    sleep 2
    echo -e "${G}✅ 主控端已启动成功！${NC}"
    read -p "按回车键返回菜单"
}

install_agent() {
    echo -e "${G}[+] 正在清理冲突并部署环境...${NC}"
    mkdir -p ${INSTALL_PATH}/agent/db_data
    
    # 强制释放可能冲突的端口
    fuser -k 2053/tcp 2096/tcp 2>/dev/null
    
    # 自动安装/重置 3x-ui 容器
    echo -e "${G}[+] 正在部署 3x-ui 核心容器...${NC}"
    docker rm -f 3x-ui 2>/dev/null
    docker run -d \
      --name 3x-ui \
      --restart always \
      --network host \
      -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui \
      ghcr.io/mhsanaei/3x-ui:latest

    # 构建 Agent 镜像
    echo -e "${G}[+] 正在构建 Agent 镜像...${NC}"
    cat > ${INSTALL_PATH}/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil docker -i https://pypi.tuna.tsinghua.edu.cn/simple
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF

    # 写入适配后的 Agent 逻辑
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, docker, time
MASTER_WS = "ws://${MASTER_DOMAIN}:8888"
DB_PATH = "/app/db_share/x-ui.db"

async def handle_task(data):
    try:
        client = docker.from_env()
        xui = client.containers.get("3x-ui")
        print(f"[*] 收到任务，开始写库，端口: {data['port']}")
        xui.stop()
        time.sleep(2)
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # 针对 mhsanaei/3x-ui 的全字段插入
        sql = """
        INSERT OR REPLACE INTO inbounds 
        (remark, port, protocol, settings, stream_settings, enable, sniffing, listen, total, up, down, expiry_time, client_stats, tag) 
        VALUES (?, ?, ?, ?, ?, 1, ?, '', 0, 0, 0, 0, 0, ?)
        """
        sniffing = '{"enabled": true, "destOverride": ["http", "tls", "quic"]}'
        tag = f"inbound-{data['port']}"
        
        cursor.execute(sql, (
            data['remark'], data['port'], data['protocol'], 
            data['settings'], data['stream_settings'], sniffing, tag
        ))
        
        conn.commit()
        conn.close()
        xui.start()
        print(f"[+] 暴力写库及容器重启成功!")
    except Exception as e:
        print(f"[!] 报错: {e}")

async def run_agent():
    print(f"[*] 正在尝试连接: {MASTER_WS}")
    while True:
        try:
            async with websockets.connect(MASTER_WS, ping_interval=20) as ws:
                print("[+] 双栈隧道已打通")
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    task = json.loads(msg)
                    if task.get('action') == 'sync_node': await handle_task(task['data'])
        except Exception as e:
            print(f"[-] 连接断开: {e}")
            await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    cd ${INSTALL_PATH}/agent
    docker build -t multix-agent-image .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share \
      multix-agent-image

    echo -e "${G}✅ 全套环境部署完成！2053 面板已就绪。${NC}"
    read -p "按回车键返回菜单"
}

uninstall_master() {
    pkill -9 -f app.py && rm -rf ${INSTALL_PATH}/master
    echo "主控已卸载"
}

uninstall_agent() {
    docker rm -f multix-agent 3x-ui && docker rmi multix-agent-image
    echo "被控已卸载"
}

while true; do show_menu; case $choice in 1) install_master ;; 2) uninstall_master ;; 3) install_agent ;; 4) uninstall_agent ;; 5) exit 0 ;; esac; done
