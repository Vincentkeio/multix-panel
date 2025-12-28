#!/bin/bash
# MultiX MVP 全能管理脚本 - 核心版本
# 支持：主控/被控 独立安装与彻底卸载

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top" 

# 检查权限
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

show_menu() {
    clear
    echo "=================================="
    echo "      MultiX 集群管理系统         "
    echo "=================================="
    echo "1. 安装/更新 主控端 (Master)"
    echo "2. 卸载 主控端 (Master)"
    echo "----------------------------------"
    echo "3. 安装/更新 被控端 (Agent)"
    echo "4. 卸载 被控端 (Agent)"
    echo "----------------------------------"
    echo "5. 退出"
    echo "=================================="
    read -p "请选择操作 [1-5]: " choice
}

# --- 主控逻辑 ---
install_master() {
    echo "正在部署主控端..."
    mkdir -p ${INSTALL_PATH}/master
    apt update && apt install -y python3 python3-pip
    pip3 install flask websockets psutil --break-system-packages --quiet

    cat > ${INSTALL_PATH}/master/app.py <<'EOF'
import json, asyncio, time, psutil, secrets
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
<head><meta charset="UTF-8"><title>MultiX Manager</title>
<style>body{background:#1a1a1a;color:white;padding:20px} .card{background:#252525;padding:15px;border-radius:8px;margin-bottom:20px} input{background:#333;color:white;border:1px solid #555;padding:5px;margin:5px}</style></head>
<body>
    <h2>MultiX 控制台 (IPv6 增强版)</h2>
    <div class="card">
        <h3>在线小鸡: {{ agents_count }}</h3>
        {% for ip, info in agents.items() %}
        <div>🌐 IP: {{ ip }} | CPU: {{ info.stats.cpu }}% | MEM: {{ info.stats.mem }}%</div>
        {% endfor %}
    </div>
    <div class="card">
        <form action="/send" method="post">
            备注: <input name="remark" value="TestNode"> 端口: <input name="port" value="12345"> 协议: <input name="protocol" value="vless" readonly><br>
            UUID: <input name="uuid" value="{{ default_uuid }}" style="width:350px"><br>
            <button type="submit" style="margin-top:10px;padding:10px;background:#177ddc;color:white;border:none;cursor:pointer">立即全集群下发</button>
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
            return "指令已下发！<a href='/' style='color:white'>点此返回</a>"
    except Exception as e: return f"失败：{str(e)}"

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
    pkill -9 -f app.py
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    echo "✅ 主控安装完成！"
    echo "Web面板: http://主控IP:7575"
    read -p "按回车键返回菜单"
}

uninstall_master() {
    echo "正在卸载主控端..."
    pkill -9 -f app.py
    rm -rf ${INSTALL_PATH}/master
    echo "✅ 主控端已彻底卸载。"
    read -p "按回车键返回菜单"
}

# --- 被控逻辑 ---
install_agent() {
    echo "正在部署被控端..."
    mkdir -p ${INSTALL_PATH}/agent/db_data
    
    # 引导用户检查数据库
    if [ ! -f ${INSTALL_PATH}/agent/db_data/x-ui.db ]; then
        echo "⚠️  未发现数据库文件！"
        echo "请将小鸡的 x-ui.db 放到: ${INSTALL_PATH}/agent/db_data/x-ui.db"
        echo "提示: cp /etc/x-ui/x-ui.db ${INSTALL_PATH}/agent/db_data/"
        read -p "已放好请按回车继续，或按 Ctrl+C 退出安装"
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
        time.sleep(1)
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        sql = "INSERT OR REPLACE INTO inbounds (remark, port, protocol, settings, stream_settings, enable, sniffing, listen) VALUES (?, ?, ?, ?, ?, 1, '{\\"enabled\\": true}', '')"
        cursor.execute(sql, (data['remark'], data['port'], data['protocol'], data['settings'], data['stream_settings']))
        conn.commit()
        conn.close()
        xui.start()
        print(f"同步成功: {data['remark']}")
    except Exception as e: print(f"执行失败: {e}")

async def run_agent():
    print(f"正在连接: {MASTER_WS}")
    while True:
        try:
            async with websockets.connect(MASTER_WS, ping_interval=20) as ws:
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=15)
                    task = json.loads(msg)
                    if task.get('action') == 'sync_node': await handle_task(task['data'])
        except: await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share \
      python:3.11-slim sh -c "pip install websockets psutil docker && python /app/agent.py"
    
    echo "✅ 被控端已启动！请检查主控面板状态。"
    read -p "按回车键返回菜单"
}

uninstall_agent() {
    echo "正在卸载被控端..."
    docker rm -f multix-agent
    rm -rf ${INSTALL_PATH}/agent/agent.py
    echo "✅ 被控端容器已清理。注意：为安全起见，db_data 目录已保留。"
    read -p "按回车键返回菜单"
}

# 循环显示菜单
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
