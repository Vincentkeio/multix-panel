#!/bin/bash
# MultiX MVP 终极版 - 支持双栈/自动同步/安装即运行

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top" 

# 核心配色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${GREEN}==================================${NC}"
    echo -e "      MultiX 集群管理系统 (V2.0)   "
    echo -e "${GREEN}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 🗑️  卸载 主控端 (Master)"
    echo "----------------------------------"
    echo "3. 📡 安装/重装 被控端 (Agent)"
    echo "4. 🗑️  卸载 被控端 (Agent)"
    echo "----------------------------------"
    echo "5. 🚪 退出"
    echo -e "${GREEN}==================================${NC}"
    read -p "请选择操作 [1-5]: " choice
}

# --- 主控逻辑 ---
install_master() {
    echo -e "${GREEN}[+] 正在部署主控端环境...${NC}"
    mkdir -p ${INSTALL_PATH}/master
    apt update && apt install -y python3 python3-pip net-tools
    pip3 install flask websockets psutil --break-system-packages --quiet

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
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>MultiX Manager</title>
<style>body{background:#1a1a1a;color:white;font-family:sans-serif;padding:20px} .card{background:#252525;padding:15px;border-radius:8px;margin-bottom:20px;border:1px solid #444} input,select{background:#333;color:white;border:1px solid #555;padding:8px;margin:5px;border-radius:4px} .btn{background:#177ddc;color:white;border:none;padding:10px 20px;border-radius:4px;cursor:pointer;font-weight:bold} .btn:hover{background:#40a9ff}</style></head>
<body>
    <h2>🛰️ MultiX 集群控制台</h2>
    <div class="card">
        <h3>在线节点: <span style="color:#52c41a">{{ agents_count }}</span></h3>
        {% for ip, info in agents.items() %}
        <div style="padding:10px;border-bottom:1px solid #333">🌐 IP: {{ ip }} | 🚀 CPU: {{ info.stats.cpu }}% | 💾 MEM: {{ info.stats.mem }}%</div>
        {% endfor %}
    </div>
    <div class="card">
        <form action="/send" method="post">
            备注: <input name="remark" value="V6_Node"> 
            端口: <input name="port" value="12345" type="number"> 
            协议: <select name="protocol"><option value="vless">VLESS</option></select><br>
            UUID: <input name="uuid" value="{{ default_uuid }}" style="width:320px"><br><br>
            <button type="submit" class="btn">🚀 全集群暴力同步同步</button>
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
        node_data = generate_xui_sql(request.form['remark'], request.form['port'], request.form['protocol'], request.form['uuid'])
        payload = json.dumps({"action": "sync_node", "data": node_data})
        if LOOP:
            for ip in list(AGENTS.keys()):
                LOOP.call_soon_threadsafe(asyncio.create_task, AGENTS[ip]['ws'].send(payload))
            return "<h1>✅ 指令已送达全集群 WebSocket！</h1><a href='/' style='color:#177ddc'>点此返回</a>"
    except Exception as e: return f"下发失败：{str(e)}"

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
    async with websockets.serve(ws_server, "::", 8888): # 强制双栈监听
        await asyncio.Future()

if __name__ == '__main__':
    Thread(target=lambda: asyncio.run(start_ws()), daemon=True).start()
    app.run(host='0.0.0.0', port=7575)
EOF

    echo -e "${GREEN}[+] 正在启动服务...${NC}"
    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    
    sleep 2 # 等待启动
    if netstat -tunlp | grep -q 7575; then
        echo -e "${GREEN}✅ 主控端已成功启动并常驻后台！${NC}"
        echo -e "Web 面板: http://主控IP:7575"
    else
        echo -e "${RED}❌ 启动失败，请检查 /opt/multix_mvp/master/master.log${NC}"
    fi
    read -p "按回车键返回菜单"
}

uninstall_master() {
    pkill -9 -f app.py
    rm -rf ${INSTALL_PATH}/master
    echo -e "${GREEN}✅ 主控端已彻底卸载。${NC}"
    read -p "按回车键返回菜单"
}

# --- 被控逻辑 ---
install_agent() {
    echo -e "${GREEN}[+] 正在部署被控端...${NC}"
    mkdir -p ${INSTALL_PATH}/agent/db_data
    
    # 检测数据库
    if [ ! -f ${INSTALL_PATH}/agent/db_data/x-ui.db ]; then
        echo -e "${RED}⚠️  未发现 x-ui.db 数据库文件！${NC}"
        echo "请执行: cp /etc/x-ui/x-ui.db ${INSTALL_PATH}/agent/db_data/"
        read -p "放好后按回车继续，或 Ctrl+C 退出"
    fi

    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, socket, psutil, websockets, docker, time
MASTER_WS = "ws://${MASTER_DOMAIN}:8888"
DB_PATH = "/app/db_share/x-ui.db"

async def handle_task(data):
    try:
        client = docker.from_env()
        xui = client.containers.get("3x-ui")
        xui.stop()
        time.sleep(1.5) # 增加延迟确保文件锁释放
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        sql = "INSERT OR REPLACE INTO inbounds (remark, port, protocol, settings, stream_settings, enable, sniffing, listen) VALUES (?, ?, ?, ?, ?, 1, '{\\"enabled\\": true}', '')"
        cursor.execute(sql, (data['remark'], data['port'], data['protocol'], data['settings'], data['stream_settings']))
        conn.commit()
        conn.close()
        xui.start()
        print(f"[*] 暴力同步成功: {data['remark']}")
    except Exception as e: print(f"[!] 执行失败: {e}")

async def run_agent():
    print(f"[*] 正在尝试连接主控: {MASTER_WS}")
    while True:
        try:
            async with websockets.connect(MASTER_WS, ping_interval=20, ping_timeout=10) as ws:
                print("[+] 已建立 WebSocket 链路 (IPv6 优先)")
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=20)
                    task = json.loads(msg)
                    if task.get('action') == 'sync_node': await handle_task(task['data'])
        except Exception as e:
            print(f"[-] 连接异常: {e}, 5秒后重试...")
            await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share \
      python:3.11-slim sh -c "pip install websockets psutil docker && python /app/agent.py"
    
    echo -e "${GREEN}✅ 被控端已通过 Docker 启动！${NC}"
    echo "你可以通过 docker logs -f multix-agent 查看连接状态。"
    read -p "按回车键返回菜单"
}

uninstall_agent() {
    docker rm -f multix-agent
    echo -e "${GREEN}✅ 被控端容器已清理。${NC}"
    read -p "按回车键返回菜单"
}

while true; do
    show_menu
    case $choice in
        1) install_master ;;
        2) uninstall_master ;;
        3) install_agent ;;
        4) uninstall_agent ;;
        5) exit 0 ;;
        *) echo "无效选项"; sleep 1 ;;
    esac
done
