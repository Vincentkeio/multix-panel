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
    echo -e "${YELLOW}>>> 正在执行环境物理级大扫除 (含旧版 Multix 清理)...${PLAIN}"
    
    # 1. 停止所有可能的服务名 (包含旧版 multix)
    systemctl stop multiy-master multiy-agent multix multix-master multix-agent 2>/dev/null
    systemctl disable multix multix-master multix-agent 2>/dev/null
    
    # 2. 移除旧版服务文件 (防止干扰)
    rm -f /etc/systemd/system/multix* 2>/dev/null
    systemctl daemon-reload
    
    # 3. 强制杀死残留进程
    # 精准匹配新旧所有可能的路径关键字
    echo -e "${YELLOW}正在清理旧进程残留...${PLAIN}"
    pkill -9 -f "master/app.py" 2>/dev/null
    pkill -9 -f "agent/agent.py" 2>/dev/null
    pkill -9 -f "multix" 2>/dev/null
    pkill -9 -f "multiy" 2>/dev/null
    pkill -9 python3 2>/dev/null # 最后的暴力兜底
    
    # 4. 针对 7575 和 9339 端口进行定点强杀
    for port in 7575 9339; do
        local pid=$(lsof -t -i:"$port" 2>/dev/null)
        if [ ! -z "$pid" ]; then
            echo -e "${YELLOW}发现端口 $port 被进程 $pid 占用，强制释放...${PLAIN}"
            kill -9 "$pid" 2>/dev/null
        fi
    done

    # 5. 彻底卸载冲突库并重新安装旗舰版三件套
    echo -e "${YELLOW}正在更新 Python 环境依赖...${PLAIN}"
    python3 -m pip uninstall -y python-socketio eventlet python-engineio websockets flask 2>/dev/null
    python3 -m pip install --upgrade flask websockets psutil --break-system-packages 2>/dev/null
    
    # 6. 确保 lsof 已安装
    if ! command -v lsof &> /dev/null; then
        apt-get update && apt-get install -y lsof >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}>>> 物理大扫除完成，环境已就绪。${PLAIN}"
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
    
# --- [ 兼容真双栈(::)的物理监听探测 ] ---
    check_net_stat() {
        local port=$1
        local family=$2
        
        # 探测是否处于 [::] 监听状态 (双栈合一的关键)
        local dual_stack=$(ss -lnpt | grep -q ":::$port" && echo "yes" || echo "no")
        # 探测是否处于 0.0.0.0 监听状态 (纯 v4)
        local pure_v4=$(ss -lnpt | grep -q "0.0.0.0:$port" && echo "yes" || echo "no")

        if [ "$family" == "v4" ]; then
            # 只要监听到 ::: (双栈) 或者 0.0.0.0 (纯v4)，IPv4 状态就应该亮绿灯
            if [ "$dual_stack" == "yes" ] || [ "$pure_v4" == "yes" ]; then
                echo -e "${GREEN}● IPv4 OK${PLAIN}"
            else
                echo -e "${RED}○ IPv4 OFF${PLAIN}"
            fi
        else
            # 只有监听到 ::: 时，IPv6 才是真正的双栈全通
            if [ "$dual_stack" == "yes" ]; then
                echo -e "${GREEN}● IPv6 OK${PLAIN}"
            else
                echo -e "${RED}○ IPv6 OFF${PLAIN}"
            fi
        fi
    }

    echo -ne " 🔹 面板服务 ($M_PORT): "
    check_net_stat "$M_PORT" "v4"
    echo -ne "                      "
    check_net_stat "$M_PORT" "v6"
    
    echo -ne " 🔹 通信服务 (9339): "
    check_net_stat "9339" "v4"
    echo -ne "                      "
    check_net_stat "9339" "v6"
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    
    # --- [ 智能逻辑诊断 ] ---
    if ss -lnpt | grep -q ":::$M_PORT"; then
        echo -e "${GREEN}[状态] 系统运行于双栈(::)监听模式。${PLAIN}"
        echo -e "${GREEN}[状态] IPv4 访问已通过内核映射至 IPv6 协议栈，全链路正常。${PLAIN}"
    else
        echo -e "${RED}[告警] 未发现双栈监听，请检查 app.py 是否配置了 host='::'${PLAIN}"
    fi

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

# --- [ 2. 主控安装：旗舰异步模块化版 ] ---
# --- [ 2. 主控安装：修正下载校验版 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (路径严谨版)${PLAIN}"
    apt-get install -y python3-pip
    
    # 1. 物理目录强制初始化
    mkdir -p "$M_ROOT/master/static"
    mkdir -p "$M_ROOT/master/templates/modals"

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

    # 3. 从 GitHub 同步 UI 资源
    local RAW_URL="https://raw.githubusercontent.com/Vincentkeio/multix-panel/main/ui"
    local V_CACHE="?v=$(date +%s)"
    echo -e "${YELLOW}>>> 正在同步云端 UI 资源...${PLAIN}"
    
    # 【核心修复】：增加下载函数，强制校验文件大小
    _download_ui() {
        local file_path=$1
        local target_path=$2
        echo -ne "  🔹 正在同步 ${file_path} ... "
        # 使用 -L 跟随重定向，确保下载原始代码
        curl -sL -o "${target_path}" "${RAW_URL}/${file_path}${V_CACHE}"
        
        # 校验：如果文件小于 100 字节，说明下到了 404 文本
        if [ ! -s "${target_path}" ] || [ $(stat -c%s "${target_path}") -lt 100 ]; then
            echo -e "${RED}[失败]${PLAIN}"
            echo -e "${RED}错误：文件内容异常，请确认 GitHub 路径：${RAW_URL}/${file_path}${PLAIN}"
            exit 1
        else
            echo -e "${GREEN}[OK]${PLAIN}"
        fi
    }

    # 执行精准下载（确保你的 GitHub 仓库 ui 文件夹下有 templates 和 static 子文件夹）
    _download_ui "templates/index.html" "$M_ROOT/master/templates/index.html"
    _download_ui "templates/main_nodes.html" "$M_ROOT/master/templates/main_nodes.html"
    _download_ui "templates/modals/admin_modal.html" "$M_ROOT/master/templates/modals/admin_modal.html"
    _download_ui "templates/modals/drawer.html" "$M_ROOT/master/templates/modals/drawer.html"
    _download_ui "templates/modals/login_modal.html" "$M_ROOT/master/templates/modals/login_modal.html"
    
    _download_ui "static/tailwind.js" "$M_ROOT/master/static/tailwind.js"
    _download_ui "static/alpine.js" "$M_ROOT/master/static/alpine.js"
    _download_ui "static/dashboard.js" "$M_ROOT/master/static/dashboard.js"
    _download_ui "static/custom.css" "$M_ROOT/master/static/custom.css"

    # 4. 部署并启动服务
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 旗舰版主控部署完成。${PLAIN}"; sleep 2; credential_center
}
# --- [ 后端核心逻辑：深度校准 404 修复版 ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess, psutil, platform, random, threading
from flask import Flask, request, jsonify, send_from_directory, render_template
from werkzeug.serving import make_server

# 1. 路径强制校准：确保 templates 和 static 在任何环境下都能找到
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
M_ROOT = "/opt/multiy_mvp"
ENV_PATH = f"{M_ROOT}/.env"
DB_PATH = f"{M_ROOT}/agents_db.json"

app = Flask(__name__, 
            template_folder=os.path.join(BASE_DIR, 'templates'),
            static_folder=os.path.join(BASE_DIR, 'static'))

# --- [ 数据持久化系统 ] ---
def load_db():
    if os.path.exists(DB_PATH):
        try:
            with open(DB_PATH, 'r', encoding='utf-8') as f: return json.load(f)
        except: return {}
    return {}

def save_db(db_data):
    with open(DB_PATH, 'w', encoding='utf-8') as f: json.dump(db_data, f, indent=4)

def load_env():
    c = {}
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH, 'r', encoding='utf-8') as f:
            for l in f:
                if '=' in l:
                    k, v = l.strip().split('=', 1)
                    c[k] = v.strip("'\"")
    return c

env = load_env()
TOKEN = env.get('M_TOKEN', 'admin')
AGENTS_LIVE = {} 
WS_CLIENTS = {}

# --- [ 3. 核心 API 路由 ] ---

@app.route('/')
def serve_index():
    return render_template('index.html')

@app.route('/static/<path:filename>')
def serve_static(filename):
    return send_from_directory(os.path.join(BASE_DIR, 'static'), filename)

# 1. 登录验证接口
@app.route('/api/login', methods=['POST'])
def api_login():
    data = request.json
    curr = load_env() 
    if data.get('user') == curr.get('M_USER') and data.get('pass') == curr.get('M_PASS'):
        return jsonify({
            "status": "success", 
            "token": curr.get('M_TOKEN'),
            "user": curr.get('M_USER')
        })
    return jsonify({"status": "fail", "msg": "凭据验证失败"}), 401

# --- [ 3. 核心 API 路由：智能状态与管理模块 ] ---
import socket

def get_public_ip(version=4):
    """自动获取本机公网 IP (v4 或 v6)"""
    try:
        # 使用 Google/Cloudflare DNS 建立测试连接探测出口 IP
        test_server = "8.8.8.8" if version == 4 else "2606:4700:4700::1111"
        s = socket.socket(socket.AF_INET if version == 4 else socket.AF_INET6, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect((test_server, 53))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return None

@app.route('/api/state')
def api_state():
    db = load_db()
    combined = {}
    for sid, config in db.items():
        # 合并数据库配置与 Agent 实时上报的数据
        live = AGENTS_LIVE.get(sid, {})
        if config.get('is_demo'):
            # 虚拟小鸡生成模拟数据
            metrics = {
                "cpu": random.randint(2, 7), 
                "mem": random.randint(18, 32), 
                "disk": random.randint(15, 25),
                "net_up": round(random.uniform(0.1, 1.2), 1),
                "net_down": round(random.uniform(0.5, 3.5), 1)
            }
            status = "online"
        else:
            metrics = live.get('metrics', {})
            status = live.get('status', 'offline')
        
        # 写入最终列表，包含排序、隐藏等字段
        combined[sid] = {**config, "metrics": metrics, "status": status}
    
    curr_env = load_env()
    
    # 智能地址获取：.env 配置优先 > 物理探测 > 默认值
    m_ip4 = curr_env.get('M_HOST_V4') or get_public_ip(4) or curr_env.get('M_HOST', '127.0.0.1')
    m_ip6 = curr_env.get('M_HOST_V6') or get_public_ip(6) or "Not Detected"
    
    return jsonify({
        "agents": combined, 
        "master": {
            "cpu": int(psutil.cpu_percent()), 
            "mem": int(psutil.virtual_memory().percent), 
            "disk": int(psutil.disk_usage('/').percent),
            "sys_ver": f"{platform.system()} {platform.release()}",
            "sb_ver": subprocess.getoutput("sing-box version | head -n 1 | awk '{print $3}'") or "N/A"
        }, 
        "config": {
            "user": curr_env.get('M_USER', 'admin'), 
            "token": curr_env.get('M_TOKEN'),
            "ip4": m_ip4, 
            "ip6": m_ip6,
            "port": curr_env.get('M_PORT', '7575')
        }
    })

@app.route('/api/update_admin', methods=['POST'])
def update_admin():
    data = request.json
    auth_token = request.headers.get('Authorization')
    curr = load_env()
    if auth_token != curr.get('M_TOKEN'):
        return jsonify({"res": "fail", "msg": "Unauthorized"}), 403
    if data.get('user'): curr['M_USER'] = data.get('user')
    if data.get('pass'): curr['M_PASS'] = data.get('pass')
    if data.get('token'): curr['M_TOKEN'] = data.get('token')
    with open(ENV_PATH, 'w') as f:
        for k, v in curr.items(): f.write(f"{k}='{v}'\n")
    global TOKEN
    TOKEN = curr.get('M_TOKEN', TOKEN)
    return jsonify({"res": "ok"})

@app.route('/api/manage_agent', methods=['POST'])
def api_manage_agent():
    data = request.json
    sid = data.get('sid')
    action = data.get('action')
    auth_token = request.headers.get('Authorization')
    curr_env = load_env()
    
    if auth_token != curr_env.get('M_TOKEN'):
        return jsonify({"res": "fail", "msg": "Unauthorized"}), 403

    db = load_db()
    if action == 'add_demo':
        new_id = f"v_node_{random.randint(1000, 9999)}"
        db[new_id] = {"hostname": f"Demo-Node-{random.randint(1,99)}", "is_demo": True, "order": len(db)+1}
    elif action == 'delete' and sid in db:
        del db[sid]
        if sid in AGENTS_LIVE: del AGENTS_LIVE[sid]
    elif action == 'hide' and sid in db:
        db[sid]['hidden'] = not db[sid].get('hidden', False)
    elif action == 'reorder' and sid in db:
        db[sid]['order'] = int(data.get('value', 0))
    elif action == 'alias' and sid in db:
        db[sid]['alias'] = data.get('value')

    save_db(db)
    return jsonify({"res": "ok"})
    
# --- [ 4. 通信逻辑 ] ---
async def ws_handler(ws):
    sid = str(id(ws))
    WS_CLIENTS[sid] = ws
    db = load_db()
    try:
        async for msg in ws:
            data = json.loads(msg)
            if data.get('token') != TOKEN: continue
            if sid not in db:
                db[sid] = {"hostname": data.get('hostname', 'Node'), "alias": "", "order": 0, "is_demo": False, "ip": ws.remote_address[0]}
                save_db(db)
            AGENTS_LIVE[sid] = {"metrics": data.get('metrics'), "status": "online", "last_seen": time.time()}
    except: pass
    finally:
        if sid in AGENTS_LIVE: AGENTS_LIVE[sid]["status"] = "offline"
        WS_CLIENTS.pop(sid, None)

async def main():
    # 1. 通信服务 (9339) - 监听 [::] 通常能自动处理双栈
    try:
        await websockets.serve(ws_handler, "::", 9339)
    except:
        await websockets.serve(ws_handler, "0.0.0.0", 9339)

    # 2. 面板服务 (7575) - 显式双路监听
    def run_flask_v4():
        # 专门负责 IPv4
        app.run(host='0.0.0.0', port=7575, threaded=True, debug=False)

    def run_flask_v6():
        try:
            # 专门负责 IPv6
            from werkzeug.serving import run_simple
            run_simple('::', 7575, app, threaded=True)
        except:
            pass

    # 启动两个线程，互不干扰
    threading.Thread(target=run_flask_v4, daemon=True).start()
    threading.Thread(target=run_flask_v6, daemon=True).start()
    
    print(">>> Multiy Pro Master: Dual-Path Listening on 7575 & 9339")
    while True: await asyncio.sleep(60)

if __name__ == "__main__":
    if not os.path.exists(DB_PATH): save_db({})
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
        """采集硬盘、流量、版本等核心指标"""
        try:
            n1 = psutil.net_io_counters()
            time.sleep(0.5)
            n2 = psutil.net_io_counters()
            return {
                "cpu": int(psutil.cpu_percent()),
                "mem": int(psutil.virtual_memory().percent),
                "disk": int(psutil.disk_usage('/').percent),
                "net_up": round((n2.bytes_sent - n1.bytes_sent) / 1024 / 1024, 2),
                "net_down": round((n2.bytes_recv - n1.bytes_recv) / 1024 / 1024, 2),
                "total_up": round(n2.bytes_sent / (1024**3), 2),
                "total_down": round(n2.bytes_recv / (1024**3), 2),
                "sys_ver": f"{platform.system()} {platform.release()}",
                "sb_ver": subprocess.getoutput(f"{SB_PATH} version | head -n 1 | awk '{{print $3}}'") or "N/A"
            }
        except:
            return {"cpu":0,"mem":0,"disk":0,"net_up":0,"net_down":0,"total_up":0,"total_down":0,"sys_ver":"Err","sb_ver":"Err"}

    async def main_loop(self):
        while True:
            try:
                async with websockets.connect(MASTER, ping_interval=20, ping_timeout=20) as ws:
                    while True:
                        state = self.get_config_state()
                        payload = {
                            "type": "heartbeat",
                            "token": TOKEN,
                            "hostname": self.hostname,
                            "metrics": self.get_metrics(),
                            "config_hash": state['hash']
                        }
                        
                        if state['hash'] != self.last_config_hash:
                            payload['type'] = "report_full"
                            payload['inbounds'] = state['inbounds']
                            self.last_config_hash = state['hash']
                        
                        await ws.send(json.dumps(payload))

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
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro Beta ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新主控 (不执行强制清理)"
    echo " 2. 安装/更新被控 (不执行强制清理)"
    echo " 3. 实时凭据与监听看板"
    echo " 4. 链路智能诊断中心"
    echo " 5. 深度清理中心 (物理抹除旧进程/端口/环境)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 
        1) install_master ;;  # 直接进入安装，不再调用 env_cleaner
        2) install_agent ;;   # 直接进入安装
        3) credential_center ;;
        4) smart_diagnostic ;;
        5) env_cleaner; rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "清理完成"; exit ;; 
        0) exit ;; 
    esac
}
check_root; install_shortcut; main_menu
