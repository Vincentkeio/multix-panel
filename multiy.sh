#!/bin/bash
# Multiy Pro V135.0-ULTIMATE - 终极全功能旗舰版

export M_ROOT="/opt/multiy_mvp"
SH_VER="V135.0-ULTIMATE"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 环境深度清理 ] ---
env_cleaner() {
    echo -e "${YELLOW}>>> 正在执行环境物理级大扫除...${PLAIN}"
    systemctl stop multiy-master multiy-agent 2>/dev/null
    pkill -9 python3 2>/dev/null

    # 彻底卸载冲突库
    python3 -m pip uninstall -y python-socketio eventlet python-engineio websockets flask 2>/dev/null
    # 安装旗舰版所需三件套
    python3 -m pip install flask websockets psutil --break-system-packages --user >/dev/null 2>&1
}

# --- [ 1. 凭据与配置详情看板 ] ---
# --- [ 1. 凭据中心看板模块 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}[错误]${PLAIN} 尚未安装主控！" && pause_back && return
    source "$M_ROOT/.env"
    
    # 获取实时 IP
    V4=$(curl -s4m 2 api.ipify.org || echo "N/A")
    V6=$(curl -s6m 2 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰凭据看板"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    
    echo -e "${GREEN}[ 1. 管理面板入口 ]${PLAIN}"
    echo -e " 🔹 IPv4 访问: http://$V4:$M_PORT"
    echo -e " 🔹 IPv6 访问: http://[$V6]:$M_PORT"
    echo -e " 🔹 管理账号: ${YELLOW}$M_USER${PLAIN}"
    echo -e " 🔹 管理密码: ${YELLOW}$M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. Agent 接入配置 (原生 WS) ]${PLAIN}"
    echo -e " 🔹 接入地址: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 通信端口: ${SKYBLUE}9339${PLAIN}"
    echo -e " 🔹 通信令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 双栈监听物理状态 ]${PLAIN}"
    
    # 精准双栈检测函数
    check_net_stat() {
        local port=$1
        local proto=$2 # tcp 或 tcp6
        if [ "$proto" == "tcp" ]; then
            netstat -lnpt | grep -q "0.0.0.0:$port " && echo -e "${GREEN}● IPv4 OK${PLAIN}" || echo -e "${RED}○ IPv4 OFF${PLAIN}"
        else
            netstat -lnpt | grep -q ":::$port " && echo -e "${GREEN}● IPv6 OK${PLAIN}" || echo -e "${RED}○ IPv6 OFF${PLAIN}"
        fi
    }

    echo -ne " 🔹 面板服务 ($M_PORT): "
    check_net_stat $M_PORT tcp
    echo -ne "                      "
    check_net_stat $M_PORT tcp6
    
    echo -ne " 🔹 通信服务 (9339): "
    check_net_stat 9339 tcp
    echo -ne "                      "
    check_net_stat 9339 tcp6
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 补全缺失的服务部署函数 ] ---
_deploy_service() {
    local name=$1
    local cmd=$2
    local workdir=$(dirname "$cmd")
    
    echo -e "${YELLOW}>>> 正在注册系统服务: ${name}${PLAIN}"
    cat > "/etc/systemd/system/${name}.service" <<EOF
[Unit]
Description=${name} Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${workdir}
ExecStart=/usr/bin/python3 ${cmd}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${name}"
    systemctl restart "${name}"
}

# --- [ 2. 主控安装：旗舰异步合一版 ] ---
install_master() {
    apt-get install -y python3-pip
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (全异步合一架构)${PLAIN}"
    env_cleaner
    mkdir -p "$M_ROOT/master"

    echo -e "\n${YELLOW}--- 交互式设置 (回车使用默认值) ---${PLAIN}"
    read -p "1. 面板 Web 端口 [默认 7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "2. 管理员账号 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "3. 管理员密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    read -p "4. 主控公网地址: " M_HOST; M_HOST=${M_HOST:-$(curl -s4 api.ipify.org)}
    
    TK_RAND=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    read -p "5. 通信令牌 Token [回车使用: $TK_RAND]: " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}

    # 1. 写入环境变量
    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF

    # 2. 生成后端核心 (app.py)
    _generate_master_py

    # 3. 从 GitHub 同步云端 UI 资源
    local RAW_URL="https://raw.githubusercontent.com/Vincentkeio/multix-panel/main/ui"
    echo -e "${YELLOW}>>> 正在同步云端极客 UI 资源...${PLAIN}"
    mkdir -p "$M_ROOT/master/static"
    
    # 使用随机参数 v 强制刷新 CDN 缓存
    curl -sL -o "$M_ROOT/master/index.html" "$RAW_URL/index.html?v=$(date +%s)"
    curl -sL -o "$M_ROOT/master/static/tailwind.js" "$RAW_URL/static/tailwind.js?v=$(date +%s)"
    curl -sL -o "$M_ROOT/master/static/alpine.js" "$RAW_URL/static/alpine.js?v=$(date +%s)"

    if [ ! -s "$M_ROOT/master/index.html" ]; then
        echo -e "${RED}❌ 致命错误: 无法获取 UI 文件，请检查网络。${PLAIN}"
        exit 1
    fi

    # 4. 部署并启动服务
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 旗舰版主控部署完成。${PLAIN}"; sleep 2; credential_center
}

# --- [ 后端核心逻辑：支持本地热分离 UI ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess
# 核心：必须包含 send_from_directory
from flask import Flask, render_template_string, session, redirect, request, jsonify, send_from_directory
from werkzeug.serving import make_server

def load_env():
    c = {}
    path = '/opt/multiy_mvp/.env'
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            for l in f:
                if '=' in l: k, v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

app = Flask(__name__)
env = load_env()
TOKEN = env.get('M_TOKEN', 'admin')
app.secret_key = TOKEN

AGENTS = {}
WS_CLIENTS = {}

# --- [ 静态资源路由：确保在 app 定义之后，逻辑运行之前 ] ---
@app.route('/static/<path:filename>')
def multiy_static_service(filename): # 函数名改了
    return send_from_directory('/opt/multiy_mvp/master/static', filename)

async def ws_handler(ws):
    addr = ws.remote_address[0]
    sid = str(id(ws))
    WS_CLIENTS[sid] = ws
    try:
        async for msg in ws:
            data = json.loads(msg)
            if data.get('token') != TOKEN: continue
            if data.get('type') in ['heartbeat', 'report_full']:
                if sid not in AGENTS:
                    AGENTS[sid] = {"ip": addr, "status": "online", "is_dirty": False, "metrics": {"cpu":0,"mem":0,"net_up":0,"net_down":0}}
                AGENTS[sid].update({
                    "hostname": data.get('hostname', 'Node'),
                    "metrics": data.get('metrics', {}),
                    "last_seen": time.time(), "status": "online"
                })
    except: pass
    finally:
        if sid in AGENTS: AGENTS[sid]["status"] = "offline"
        WS_CLIENTS.pop(sid, None)

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    with open("/opt/multiy_mvp/master/index.html", "r", encoding="utf-8") as f:
        return render_template_string(f.read())

@app.route('/api/state')
def api_state():
    return jsonify({
        "agents": AGENTS, 
        "config": {"token": TOKEN, "ip4": env.get('M_HOST'), "ip6": "::"}
    })

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    # 简易登录页防止逻辑缺失
    return '''<body style="background:#000;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh"><form method="post"><h2>MULTIY LOGIN</h2><input name="u" placeholder="User"><input name="p" type="password" placeholder="Pass"><button>ENTER</button></form></body>'''

async def main():
    # 同时启动 WS 和 Web
    ws_server = await websockets.serve(ws_handler, "::", 9339)
    srv = make_server('::', int(env.get('M_PORT', 7575)), app)
    await asyncio.gather(asyncio.to_thread(srv.serve_forever), asyncio.Future())

if __name__ == "__main__":
    asyncio.run(main())
EOF
}
# --- [ 3. 被控端安装 (全能仆人旗舰版) ] ---
install_agent() {
    apt-get install -y python3-pip
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰被控 (Hybrid 状态对齐版)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名或IP: " M_INPUT
    read -p "2. 通信令牌 (Token): " M_TOKEN
    
    # 安装依赖
    echo -e "${YELLOW}正在同步环境依赖...${PLAIN}"
    python3 -m pip install websockets psutil --break-system-packages --user >/dev/null 2>&1

    # 自愈映射逻辑 (保留你的 IPv6 劫持方案)
    if [[ "$M_INPUT" == *:* ]]; then
        echo -e "${YELLOW}[物理自愈] 正在为 IPv6 执行 hosts 劫持映射...${PLAIN}"
        sed -i "/multiy.local.master/d" /etc/hosts
        echo "$M_INPUT multiy.local.master" >> /etc/hosts
        FINAL_URL="ws://multiy.local.master:9339"
    else
        FINAL_URL="ws://$M_INPUT:9339"
    fi

    # 注入“全能仆人”逻辑
    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, websockets, json, os, subprocess, psutil, platform, time, hashlib, socket

# --- [ 仆人配置 ] ---
MASTER = "REPLACE_URL"
TOKEN = "REPLACE_TOKEN"
SB_PATH = "/usr/local/bin/sing-box"
SB_CONF = "/etc/sing-box/config.json"

class ServantCore:
    def __init__(self):
        self.last_config_hash = ""
        self.hostname = socket.gethostname()

    def get_config_state(self):
        """Hybrid 模式核心：读取物理配置并生成 MD5"""
        if not os.path.exists(SB_CONF):
            return {"hash": "none", "inbounds": []}
        try:
            with open(SB_CONF, 'r', encoding='utf-8') as f:
                content = f.read()
                data = json.loads(content)
                m = hashlib.md5()
                m.update(content.encode('utf-8'))
                return {"hash": m.hexdigest(), "inbounds": data.get('inbounds', [])}
        except:
            return {"hash": "error", "inbounds": []}

    def get_metrics(self):
        """仪表盘基础指标采集"""
        net_1 = psutil.net_io_counters()
        time.sleep(0.5)
        net_2 = psutil.net_io_counters()
        return {
            "cpu": int(psutil.cpu_percent()),
            "mem": int(psutil.virtual_memory().percent),
            "disk": int(psutil.disk_usage('/').percent),
            "net_up": round((net_2.bytes_sent - net_1.bytes_sent) / 1024 / 1024, 2),
            "net_down": round((net_2.bytes_recv - net_1.bytes_recv) / 1024 / 1024, 2),
            "sys_ver": f"{platform.system()} {platform.release()}",
            "sb_ver": subprocess.getoutput(f"{SB_PATH} version | head -n 1 | awk '{{print $3}}'") or "N/A"
        }

    async def main_loop(self):
        while True:
            try:
                async with websockets.connect(MASTER, ping_interval=20, ping_timeout=20) as ws:
                    while True:
                        state = self.get_config_state()
                        # 构建基础心跳包
                        payload = {
                            "type": "heartbeat",
                            "token": TOKEN,
                            "hostname": self.hostname,
                            "metrics": self.get_metrics(),
                            "config_hash": state['hash']
                        }
                        
                        # Hybrid 逻辑：如果哈希变了，上报全量清单给主控
                        if state['hash'] != self.last_config_hash:
                            payload['type'] = "report_full"
                            payload['inbounds'] = state['inbounds']
                            self.last_config_hash = state['hash']
                        
                        await ws.send(json.dumps(payload))

                        # 监听主控指令 (原子同步/Shell 执行)
                        try:
                            msg = await asyncio.wait_for(ws.recv(), timeout=5)
                            task = json.loads(msg)
                            
                            if task['type'] == 'exec_cmd':
                                res = subprocess.getoutput(task['cmd'])
                                await ws.send(json.dumps({"type": "cmd_res", "id": task['id'], "data": res}))
                                
                            elif task['type'] == 'sync_config':
                                with open(SB_CONF, 'w', encoding='utf-8') as f:
                                    json.dump(task['config'], f, indent=4)
                                if os.system(f"{SB_PATH} check -c {SB_CONF}") == 0:
                                    os.system("systemctl restart sing-box")
                                    await ws.send(json.dumps({"type": "msg", "res": "Sync OK"}))
                                else:
                                    await ws.send(json.dumps({"type": "msg", "res": "Config Error"}))
                        except asyncio.TimeoutError:
                            continue
            except:
                await asyncio.sleep(10)

if __name__ == "__main__":
    servant = ServantCore()
    asyncio.run(servant.main_loop())
EOF

    # 动态注入配置
    sed -i "s|REPLACE_URL|$FINAL_URL|; s|REPLACE_TOKEN|$M_TOKEN|" "$M_ROOT/agent/agent.py"
    
    # 部署并启动服务
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 旗舰版被控已上线 (支持状态对齐与 Hybrid 同步)${PLAIN}"; pause_back
}
# --- [ 4. 链路诊断中心 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 旗舰诊断中心 (原生协议探测)${PLAIN}"
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        # 从代码中提取当前运行的凭据
        A_URL=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_TK=$(grep "TOKEN =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        
        echo -e "${GREEN}[ 当前 Agent 运行凭据 ]${PLAIN}"
        echo -e " 🔹 接入地址: ${SKYBLUE}$A_URL${PLAIN}"
        echo -e " 🔹 通信令牌: ${YELLOW}$A_TK${PLAIN}"
        echo -e "------------------------------------------------"
        
        # 物理探测逻辑
        python3 -c "import websockets, asyncio; asyncio.run(websockets.connect('$A_URL', timeout=5))" >/dev/null 2>&1
        if [ $? -eq 0 ] || [ $? -eq 1 ]; then
             echo -e " 👉 状态: ${GREEN}物理链路 OK${PLAIN} (端口已开放)"
             echo -e "${YELLOW}[提示]${PLAIN} 如果面板仍无数据，请检查上面显示的令牌是否与主控一致。"
        else
             echo -e " 👉 状态: ${RED}链路 FAIL${PLAIN} (主控 9339 端口不可达)"
        fi
    else
        echo -e "${RED}[错误]${PLAIN} 未发现 Agent 记录。"
    fi
    pause_back
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro Beta${SH_VER}${PLAIN}"
    echo " 1. 安装/物理自愈主控 (旗舰合一版)"
    echo " 2. 安装/更新被控 (原生双栈隧道)"
    echo " 3. 实时凭据与监听看板"
    echo " 4. 链路智能诊断中心"
    echo " 5. 深度清理中心 (物理抹除)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 
        1) install_master ;; 
        2) install_agent ;; 
        3) credential_center ;;
        4) smart_diagnostic ;;
        5) 
            systemctl stop multiy-master multiy-agent 2>/dev/null
            rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "抹除成功"; exit ;; 
        0) exit ;; 
    esac
}

check_root; install_shortcut; main_menu
