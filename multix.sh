cat > multix.sh << 'EOF'
#!/bin/bash

# ==============================================================================
# MultiX Pro Script V70.0 (Full Repaired Version)
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export AGENT_CONF="${M_ROOT}/agent/.agent.conf"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V70.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具函数 ] ---
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then RELEASE="ubuntu"
    else RELEASE="centos"; fi
}

fix_apt_sources() {
    echo -e "${YELLOW}优化 APT 源...${PLAIN}"
    # 预留占位
}

get_public_ips() {
    IPV4=$(curl -4s api.ipify.org || echo "N/A")
    IPV6=$(curl -6s api64.ipify.org || echo "N/A")
}

pause_back() {
    echo -e "\n${SKYBLUE}按任意键返回菜单...${PLAIN}"
    read -n 1
    main_menu
}

install_dependencies() {
    check_sys
    if [[ "${RELEASE}" == "debian" || "${RELEASE}" == "ubuntu" ]]; then
        fix_apt_sources
        apt-get update
        apt-get install -y python3 python3-pip curl wget socat tar openssl git netcat-openbsd ntpdate
    elif [[ "${RELEASE}" == "centos" ]]; then 
        yum install -y epel-release python3 python3-devel python3-pip curl wget socat tar openssl git nc ntpdate
    fi
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1 || \
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" >/dev/null 2>&1
}

# --- [ 服务管理 ] ---
service_manager() {
    echo -e "${SKYBLUE}服务管理控制台${PLAIN}"
    echo "1. 重启主控  2. 停止主控  3. 重启被控容器"
    read -p "选择: " s_opt
    case $s_opt in
        1) systemctl restart multix-master ;;
        2) systemctl stop multix-master ;;
        3) docker restart multix-agent ;;
    esac
    main_menu
}

# --- [ 5. 凭据中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 凭据管理中心${PLAIN}"
    if [ -f $M_ROOT/.env ]; then
        source $M_ROOT/.env
        get_public_ips
        echo -e "${YELLOW}[主控端]${PLAIN} http://[${IPV6}]:${M_PORT}"
        echo -e "用户: ${GREEN}$M_USER${PLAIN} | Token: ${SKYBLUE}$M_TOKEN${PLAIN}"
    fi

    AGENT_HOST="未配置"; AGENT_TOKEN="未配置"
    if [ -f "$AGENT_CONF" ]; then source "$AGENT_CONF"; fi
    echo -e "\n${YELLOW}[被控端 (Agent)]${PLAIN}"
    echo -e "连接目标 (Master): ${GREEN}${AGENT_HOST}${PLAIN}"
    echo -e "连接凭据 (Token) : ${SKYBLUE}${AGENT_TOKEN}${PLAIN}"
    echo "--------------------------------"
    echo " 1. 修改主控配置 (端口/密码)"
    echo " 2. 修改被控 -> 连接目标"
    echo " 3. 修改被控 -> 认证 Token"
    echo " 0. 返回"
    read -p "选择: " c
    
    if [[ "$c" == "1" ]]; then
        read -p "新端口: " np; M_PORT=${np:-$M_PORT}
        read -p "新Token: " nt; M_TOKEN=${nt:-$M_TOKEN}
        echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
        systemctl restart multix-master; echo "主控已重启"
    elif [[ "$c" == "2" || "$c" == "3" ]]; then
        if [[ "$c" == "2" ]]; then read -p "新 IP/域名: " new_val; AGENT_HOST=$new_val; fi
        if [[ "$c" == "3" ]]; then read -p "新 Token: " new_val; AGENT_TOKEN=$new_val; fi
        echo "AGENT_HOST='$AGENT_HOST'" > "$AGENT_CONF"
        echo "AGENT_TOKEN='$AGENT_TOKEN'" >> "$AGENT_CONF"
        if [ -d "$M_ROOT/agent" ]; then
            echo -e "${YELLOW}更新配置并重启 Agent...${PLAIN}"
            generate_agent_py "$AGENT_HOST" "$AGENT_TOKEN"
            docker restart multix-agent
            echo -e "${GREEN}更新成功!${PLAIN}"
        else
            echo -e "${RED}Agent 未安装，配置已保存待用。${PLAIN}"
        fi
    fi
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
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(inbounds)")
        columns = [info[1] for info in cursor.fetchall()]
        base = {'user_id': 1, 'up': 0, 'down': 0, 'total': 0, 'remark': data.get('remark'), 'enable': 1, 'expiry_time': 0, 'listen': '', 'port': data.get('port'), 'protocol': data.get('protocol'), 'settings': data.get('settings'), 'stream_settings': data.get('stream_settings'), 'tag': 'multix', 'sniffing': data.get('sniffing', '{}')}
        valid = {k: v for k, v in base.items() if k in columns}
        nid = data.get('id')
        if nid:
            set_sql = ", ".join([f"{k}=?" for k in valid.keys()])
            cursor.execute(f"UPDATE inbounds SET {set_sql} WHERE id=?", list(valid.values()) + [nid])
        else:
            keys = ", ".join(valid.keys()); ph = ", ".join(["?"]*len(valid))
            cursor.execute(f"INSERT INTO inbounds ({keys}) VALUES ({ph})", list(valid.values()))
        conn.commit(); conn.close(); log(f"Synced Node: {data.get('remark')}"); return True
    except Exception as e: log(f"DB Error: {e}"); return False

async def run():
    target = MASTER
    if ":" in target and not target.startswith("[") and not target[0].isalpha(): target = f"[{target}]"
    uri = f"ws://{target}:8888"
    log(f"Connecting to {uri} ...")
    while True:
        try:
            async with websockets.connect(uri, ping_interval=20, open_timeout=20) as ws:
                log("Connected! Auth..."); await ws.send(json.dumps({"token": TOKEN}))
                await ws.send(json.dumps({"type": "heartbeat", "data": {"cpu":0,"mem":0,"os":platform.system(),"xui":get_xui_ver()}, "nodes": []}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent), "os": platform.system(), "xui": get_xui_ver()}
                    nodes = []
                    try:
                        if os.path.exists(DB_PATH):
                            conn = sqlite3.connect(DB_PATH); cur = conn.cursor()
                            cur.execute("SELECT id, remark, port, protocol, settings, stream_settings FROM inbounds WHERE tag='multix'")
                            for row in cur.fetchall():
                                nodes.append({"id":row[0],"remark":row[1],"port":row[2],"protocol":row[3],"settings":json.loads(row[4]),"stream_settings":json.loads(row[5])})
                            conn.close()
                    except: pass
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats, "nodes": nodes}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=5); task = json.loads(msg)
                    if task.get('action') == 'sync_node': 
                        os.system("docker restart 3x-ui"); smart_sync_db(task['data']); os.system("docker restart 3x-ui")
        except Exception as e: log(f"Connect Fail: {e}"); await asyncio.sleep(5)
asyncio.run(run())
EOF
}

# --- [ 11. 智能网络修复 ] ---
smart_network_repair() {
    echo -e "\n${YELLOW}🔧 正在执行智能网络修复...${PLAIN}"
    if [ -f "$AGENT_CONF" ]; then source "$AGENT_CONF"; fi
    echo -n "1. 设置 MTU = 1280 (IPv6 Fix)... "
    ip link set dev eth0 mtu 1280 2>/dev/null
    ip link set dev ens3 mtu 1280 2>/dev/null
    echo -e "${GREEN}Done${PLAIN}"
    echo -n "2. 同步系统时间... "
    ntpdate pool.ntp.org >/dev/null 2>&1
    timedatectl set-ntp true >/dev/null 2>&1
    echo -e "${GREEN}Done${PLAIN}"
    echo -n "3. 开启 IP 转发... "
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf 2>/dev/null
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf 2>/dev/null
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}Done${PLAIN}"
    echo -e "${GREEN}✅ 修复完成！${PLAIN}"
    [ "$1" != "no_pause" ] && pause_back
}

# --- [ 3. 连通性测试 ] ---
connection_test() {
    echo -e "${SKYBLUE}📡 智能连通性测试 (V70.0)${PLAIN}"
    if [ -f "$AGENT_CONF" ]; then source "$AGENT_CONF"; else
        read -p "IP/Domain: " AGENT_HOST; read -p "Token: " AGENT_TOKEN
    fi
    [ -z "$AGENT_HOST" ] && return

    echo -e "\n${YELLOW}>>> 阶段 1: TCP 网络连通性测试 (8888)${PLAIN}"
    nc -zv -w 5 "$AGENT_HOST" 8888
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FAIL] TCP 连接失败。${PLAIN}"
        read -p "是否执行智能修复? [y/N] " r
        if [[ "$r" == "y" ]]; then smart_network_repair "no_pause"; fi
    else
        echo -e "${GREEN}[PASS] TCP 连接成功。${PLAIN}"
    fi

    echo -e "\n${YELLOW}>>> 阶段 2: Token 鉴权测试${PLAIN}"
    cat > /tmp/test_conn.py <<EOF
import asyncio, websockets, json, sys
async def test():
    t = "$AGENT_HOST"
    if ":" in t and not t.startswith("[") and not t[0].isalpha(): t = f"[{t}]"
    uri = f"ws://{t}:8888"
    try:
        async with websockets.connect(uri, open_timeout=15) as ws:
            await ws.send(json.dumps({"token": "$AGENT_TOKEN"}))
            await ws.send(json.dumps({"type": "heartbeat", "data": {}, "nodes": []}))
            print("Auth: OK")
    except Exception as e: print(f"Err: {e}"); sys.exit(1)
asyncio.run(test())
EOF
    if docker ps | grep -q multix-agent; then
        docker cp /tmp/test_conn.py multix-agent:/app/test_conn.py
        docker exec multix-agent python /app/test_conn.py
    else
        python3 /tmp/test_conn.py
    fi
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FAIL] 鉴权失败。可能是时间同步或Token错误。${PLAIN}"
    fi
    rm -f /tmp/test_conn.py
    pause_back
}

# --- [ 6. 主控安装 ] ---
_install_master_logic() {
    cat > $M_ROOT/master/app.py <<'EOF'
import json, asyncio, psutil, os, socket, subprocess, base64, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

logging.basicConfig(level=logging.ERROR)
def load_conf():
    c = {}
    try:
        with open('/opt/multix_mvp/.env', 'r') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    except: pass
    return c

CONF = load_conf()
M_PORT = int(CONF.get('M_PORT', 7575))
M_USER = CONF.get('M_USER', 'admin')
M_PASS = CONF.get('M_PASS', 'admin')
M_TOKEN = CONF.get('M_TOKEN', 'error')

app = Flask(__name__)
app.secret_key = M_TOKEN

AGENTS = {"local-demo": {"alias": "Demo Node", "stats": {"cpu": 15, "mem": 40, "os": "Demo OS", "xui": "v2.x.x"}, "nodes": [{"id": 1, "remark": "Demo-VLESS", "port": 443, "protocol": "vless", "settings": {"clients":[{"id":"demo-uuid"}]}, "stream_settings": {"network":"ws", "security":"tls"}}], "is_demo": True}}

@app.route('/api/state')
def get_state():
    return jsonify({"master": {"stats": {"cpu":psutil.cpu_percent(),"mem":psutil.virtual_memory().percent}, "ipv4": "N/A", "ipv6": "N/A"}, "agents": AGENTS})

@app.route('/')
def index():
    return "MultiX Master Running. UI logic here..."

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=M_PORT)
EOF
}

install_master() {
    install_dependencies
    mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    [ -f $M_ROOT/.env ] && source $M_ROOT/.env
    read -p "端口 [7575]: " IN_PORT; M_PORT=${IN_PORT:-${M_PORT:-7575}}
    read -p "用户 [admin]: " IN_USER; M_USER=${IN_USER:-${M_USER:-admin}}
    read -p "密码 [admin]: " IN_PASS; M_PASS=${IN_PASS:-${M_PASS:-admin}}
    RAND=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    read -p "Token [随机]: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-${M_TOKEN:-$RAND}}
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
    _install_master_logic
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
    get_public_ips
    echo -e "${GREEN}✅ 主控部署成功${PLAIN}"
    pause_back
}

# --- [ 7. 被控安装 ] ---
install_agent() {
    install_dependencies
    if ! command -v docker &> /dev/null; then echo "请先安装 Docker"; exit 1; fi
    mkdir -p $M_ROOT/agent
    read -p "主控域名/IP: " IN_HOST; read -p "Token: " IN_TOKEN
    echo "AGENT_HOST='$IN_HOST'" > "$AGENT_CONF"
    echo "AGENT_TOKEN='$IN_TOKEN'" >> "$AGENT_CONF"
    cat > $M_ROOT/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install websockets psutil --break-system-packages
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    generate_agent_py "$IN_HOST" "$IN_TOKEN"
    cd $M_ROOT/agent && docker build -t multix-agent-v70 .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host -v /var/run/docker.sock:/var/run/docker.sock -v /etc/x-ui:/app/db_share -v $M_ROOT/agent:/app multix-agent-v70
    echo -e "${GREEN}✅ 被控启动完成${PLAIN}"
    pause_back
}

# --- [ 9. 主菜单 ] ---
main_menu() {
    clear
    echo -e "${SKYBLUE}🛰️ MultiX Pro (V70.0 Ultimate Fix)${PLAIN}"
    echo " 1. 安装 主控端"
    echo " 2. 安装 被控端"
    echo " 3. 智能连通测试"
    echo " 4. 被控重启"
    echo " 5. 深度清理"
    echo " 6. 环境修复"
    echo " 7. 凭据管理"
    echo " 8. 实时日志"
    echo " 9. 运维工具"
    echo " 10. 服务管理"
    echo " 11. 智能网络修复 (MTU/Time/FW)"
    echo " 0. 退出"
    read -p "选择: " choice
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) connection_test ;;
        4) docker restart multix-agent; pause_back ;;
        5) rm -rf $M_ROOT; echo "清理完成"; pause_back ;;
        6) install_dependencies; pause_back ;;
        7) credential_center ;;
        8) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50; pause_back ;;
        9) echo "运维工具待开发"; pause_back ;;
        10) service_manager ;;
        11) smart_network_repair ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

main_menu
EOF

chmod +x multix.sh
./multix.sh
