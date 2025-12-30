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
    
# 动态获取通信端口变量，如果脚本中未定义则兜底 9339
    WS_PORT=${M_WS_PORT:-9339}

    echo -e "\n${GREEN}[ 2. Agent 接入配置 (原生 WS) ]${PLAIN}"
    echo -e " 🔹 接入地址: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 通信端口: ${SKYBLUE}$WS_PORT${PLAIN}"
    echo -e " 🔹 通信令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 双栈监听物理状态 ]${PLAIN}"
    
# --- [ 提升版：双栈解耦物理探测 ] ---
    check_net_stat() {
        local port=$1
        local family=$2
        
        # 使用 ss 分别提取 IPv4 和 IPv6 栈的真实监听状态
        local has_v4=$(ss -lnpt4 | grep -q ":$port " && echo "yes" || echo "no")
        local has_v6=$(ss -lnpt6 | grep -q ":$port " && echo "yes" || echo "no")

        if [ "$family" == "v4" ]; then
            # 只要 IPv4 栈有监听，或者 IPv6 栈处于双栈合一 (::) 模式，v4 就算 OK
            if [ "$has_v4" == "yes" ] || ss -lnpt | grep -q ":::$port"; then
                echo -e "${GREEN}● IPv4 OK${PLAIN}"
            else
                echo -e "${RED}○ IPv4 OFF${PLAIN}"
            fi
        else
            # 显式检查 IPv6 协议栈是否有监听
            if [ "$has_v6" == "yes" ]; then
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
    
    # --- [ 深度自诊逻辑 ] ---
    if ss -lnpt | grep -q ":::$M_PORT"; then
        echo -e "${GREEN}[状态] 检测到双栈(::)监听模式。${PLAIN}"
        echo -e "${GREEN}[状态] 内核已自动将 IPv4 流量映射至 IPv6 协议栈。${PLAIN}"
    elif ss -lnpt | grep -q "0.0.0.0:$M_PORT"; then
        echo -e "${YELLOW}[状态] 仅检测到纯 IPv4 监听。IPv6 访问可能受限。${PLAIN}"
    else
        echo -e "${RED}[告警] 端口 $M_PORT 未处于监听状态，请检查进程。${PLAIN}"
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
    
    # 1. 面板端口交互：增加数字合法性校验
    read -p "1. 面板 Web 端口 [默认 7575]: " M_PORT
    if [[ ! "$M_PORT" =~ ^[0-9]+$ ]] || [ "$M_PORT" -lt 1 ] || [ "$M_PORT" -gt 65535 ]; then
        M_PORT=7575
        echo -e "${YELLOW}[提示] 输入端口无效或为空，已回退至默认: 7575${PLAIN}"
    fi

    read -p "2. 管理员账号 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "3. 管理员密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    read -p "4. 主控公网地址: " M_HOST; M_HOST=${M_HOST:-$(curl -s4 api.ipify.org)}
    
    # 5. Token 生成与交互
    TK_RAND=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    read -p "5. 通信令牌 Token [回车使用: $TK_RAND]: " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}

    # --- [ 写入环境变量：确保持久化 ] ---
    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF

    # 2. 生成后端核心 (app.py)
    # 请确保脚本下方的 _generate_master_py 函数已更新为包含 /sub 和 /api/gen_keys 的版本
    _generate_master_py

    # 3. 从 GitHub 同步 UI 资源
    local RAW_URL="https://raw.githubusercontent.com/Vincentkeio/multix-panel/main/ui"
    local V_CACHE="?v=$(date +%s)"
    echo -e "${YELLOW}>>> 正在同步云端 UI 资源 (全量自动化清单)...${PLAIN}"
    
    # 【重构下载函数】：支持自动创建目录并强制校验
    _download_ui() {
        local file=$1
        local target="$M_ROOT/master/$file"
        
        # 自动创建子目录 (如 static/ 或 templates/modals/)
        mkdir -p "$(dirname "$target")"
        
        echo -ne "  🔹 正在同步 ${file} ... "
        # 使用 -L 跟随重定向，确保下载原始代码
        curl -sL -o "$target" "${RAW_URL}/${file}${V_CACHE}"
        
        # 校验：检查文件是否存在且大小是否正常（防止下到404页面）
        if [ ! -s "$target" ] || [ $(stat -c%s "$target") -lt 50 ]; then
            echo -e "${RED}[失败]${PLAIN}"
            echo -e "${RED}错误：文件 ${file} 内容异常或路径不存在。${PLAIN}"
            exit 1
        else
            echo -e "${GREEN}[OK]${PLAIN}"
        fi
    }

    # 【核心配置】：UI 文件全量清单
    # 未来若增加新文件，只需在此数组添加路径，无需修改下载逻辑
    UI_FILES=(
        "templates/index.html"
        "templates/main_nodes.html"
        "templates/modals/admin_modal.html"
        "templates/modals/drawer.html"
        "templates/modals/login_modal.html"
        "static/tailwind.js"
        "static/alpine.js"
        "static/dashboard.js"
        "static/custom.css"
        "static/qrcode.min.js"
    )

    # 执行循环精准同步
    for file in "${UI_FILES[@]}"; do
        _download_ui "$file"
    done
    # 4. 部署并启动服务
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 旗舰版主控部署完成。${PLAIN}"; sleep 2; credential_center
}
# --- [ 后端核心逻辑：固化版 (支持超级订阅与密钥生成) ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess, psutil, platform, random, threading, socket, base64
from flask import Flask, request, jsonify, send_from_directory, render_template

# 1. 基础配置与路径校准
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
M_ROOT = "/opt/multiy_mvp"
ENV_PATH = f"{M_ROOT}/.env"
DB_PATH = f"{M_ROOT}/agents_db.json"

app = Flask(__name__, 
            template_folder=os.path.join(BASE_DIR, 'templates'),
            static_folder=os.path.join(BASE_DIR, 'static'))

# --- [ 数据库管理 ] ---
def load_db():
    if not os.path.exists(DB_PATH): return {}
    try:
        with open(DB_PATH, 'r', encoding='utf-8') as f:
            db = json.load(f)
        nodes = list(db.items())
        nodes.sort(key=lambda x: (x[1].get('order') == 0, x[1].get('order', 999)))
        cleaned_db = {}
        for i, (uid, data) in enumerate(nodes, 1):
            data['order'] = i
            cleaned_db[uid] = data
        return cleaned_db
    except: return {}

def save_db(db_data):
    with open(DB_PATH, 'w', encoding='utf-8') as f:
        json.dump(db_data, f, indent=4, ensure_ascii=False)

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

# --- [ 核心 API 路由 ] ---
@app.route('/')
def serve_index(): 
    return render_template('index.html')

@app.route('/static/<path:filename>')
def serve_static(filename):
    return send_from_directory(os.path.join(BASE_DIR, 'static'), filename)

@app.route('/api/state')
def api_state():
    db = load_db()
    combined = {}
    for sid, config in db.items():
        live = AGENTS_LIVE.get(sid, {})
        if config.get('is_demo'):
            metrics = {"cpu": random.randint(2,8), "mem": random.randint(15,30), "disk": 20, "net_up": 0.5, "net_down": 1.2}
            status = "online"
        else:
            metrics = live.get('metrics', {})
            status = live.get('status', 'offline')
        combined[sid] = {**config, "metrics": metrics, "status": status, "sid": sid}
    
    curr = load_env()
    return jsonify({
        "agents": combined,
        "master": {
            "cpu": int(psutil.cpu_percent()), 
            "mem": int(psutil.virtual_memory().percent), 
            "disk": int(psutil.disk_usage('/').percent),
            "sys_ver": f"{platform.system()} {platform.release()}",
            "sb_ver": subprocess.getoutput("sing-box version | head -n 1 | awk '{print $3}'") or "N/A"
        },
        "config": {"user": curr.get('M_USER'), "token": TOKEN, "ip4": curr.get('M_HOST')}
    })

# --- [ 新增：超级订阅转换器 ] ---
@app.route('/sub')
def sub_handler():
    db = load_db()
    curr_env = load_env()
    token = request.args.get('token')
    sub_type = request.args.get('type', 'v2ray')
    
    if token != TOKEN:
        return "Unauthorized", 403
    
    links = []
    clash_proxies = []
    
    for sid, agent in db.items():
        if agent.get('hidden'): continue
        ip = agent.get('ip') or curr_env.get('M_HOST')
        inbounds = agent.get('metrics', {}).get('inbounds', [])
        
        for inb in inbounds:
            if inb.get('type') == 'vless':
                # 隐私脱敏：仅使用节点 Tag
                tag = inb.get('tag', 'VLESS_Node')
                uuid = inb.get('uuid')
                port = inb.get('listen_port') or inb.get('port')
                sni = inb.get('reality_dest', '').split(':')[0] or 'yahoo.com'
                pbk = inb.get('reality_pub', '')
                sid_param = inb.get('short_id', '')
                
                # V2Ray 格式
                links.append(f"vless://{uuid}@{ip}:{port}?security=reality&sni={sni}&fp=chrome&pbk={pbk}&sid={sid_param}&type=tcp&flow=xtls-rprx-vision#{tag}")
                
                # Clash 格式
                clash_proxies.append({
                    "name": tag, "type": "vless", "server": ip, "port": port, "uuid": uuid,
                    "udp": True, "tls": True, "flow": "xtls-rprx-vision", "servername": sni,
                    "reality-opts": {"public-key": pbk, "short-id": sid_param}, "client-fingerprint": "chrome"
                })

    if sub_type == 'clash':
        # 极简 YAML 构造
        res = "proxies:\n"
        for p in clash_proxies:
            res += f"  - {{name: \"{p['name']}\", type: vless, server: \"{p['server']}\", port: {p['port']}, uuid: \"{p['uuid']}\", udp: true, tls: true, flow: \"xtls-rprx-vision\", servername: \"{p['servername']}\", reality-opts: {{public-key: \"{p['reality-opts']['public-key']}\", short-id: \"{p['reality-opts']['short-id']}\"}}, client-fingerprint: chrome}}\n"
        res += "proxy-groups:\n  - {name: \"GLOBAL\", type: select, proxies: [" + ",".join([f"\"{p['name']}\"" for p in clash_proxies]) + "]}\n"
        res += "rules:\n  - MATCH,GLOBAL"
        return res, 200, {'Content-Type': 'text/yaml; charset=utf-8'}
    
    return base64.b64encode('\n'.join(links).encode()).decode()

# --- [ 新增：密钥生成接口 ] ---
@app.route('/api/gen_keys')
def gen_keys():
    try:
        out = subprocess.getoutput("sing-box generate reality-keypair")
        lines = out.split('\n')
        return jsonify({
            "private_key": lines[0].split(': ')[1].strip(),
            "public_key": lines[1].split(': ')[1].strip()
        })
    except: return jsonify({"private_key": "", "public_key": ""})

@app.route('/api/login', methods=['POST'])
def api_login():
    d = request.json
    c = load_env()
    if d.get('user') == c.get('M_USER') and d.get('pass') == c.get('M_PASS'):
        return jsonify({"status": "success", "token": TOKEN})
    return jsonify({"status": "fail"}), 401

@app.route('/api/manage_agent', methods=['POST'])
def api_manage_agent():
    d = request.json
    if request.headers.get('Authorization') != TOKEN: return jsonify({"res":"fail"}), 403
    db = load_db()
    sid, action = d.get('sid'), d.get('action')
    if sid in db:
        if action == 'delete': del db[sid]
        elif action == 'hide': db[sid]['hidden'] = not db[sid].get('hidden', False)
        elif action == 'alias': db[sid]['alias'] = d.get('value', '').strip()
    save_db(db)
    return jsonify({"res": "ok"})

@app.route('/api/update_node_config', methods=['POST'])
def api_update_node_config():
    d = request.json
    if request.headers.get('Authorization') != TOKEN: return jsonify({"res":"fail"}), 403
    # JSON 透传逻辑：直接下发给 Agent
    live = AGENTS_LIVE.get(d.get('sid'))
    if live and live.get('session') in WS_CLIENTS:
        ws = WS_CLIENTS[live['session']]
        cmd = json.dumps({"action": "update_config", "inbounds": d.get('inbounds')})
        asyncio.run_coroutine_threadsafe(ws.send(cmd), asyncio.get_event_loop())
        return jsonify({"res": "ok"})
    return jsonify({"res": "fail", "msg": "Agent Offline"})

# --- [ 通信逻辑 ] ---
async def ws_handler(ws):
    sid = str(id(ws))
    WS_CLIENTS[sid] = ws
    node_uuid = None
    try:
        async for m in ws:
            d = json.loads(m)
            if d.get('token') != TOKEN: continue
            node_uuid = d.get('node_id')
            if not node_uuid: continue
            db = load_db()
            if node_uuid not in db:
                db[node_uuid] = {"hostname": d.get('hostname', 'Node'), "order": len(db)+1, "ip": ws.remote_address[0], "hidden": False, "alias": ""}
                save_db(db)
            AGENTS_LIVE[node_uuid] = {"metrics": d.get('metrics'), "status": "online", "session": sid, "last_seen": time.time()}
    except: pass
    finally:
        if node_uuid in AGENTS_LIVE: AGENTS_LIVE[node_uuid]['status'] = 'offline'
        WS_CLIENTS.pop(sid, None)

async def main():
    try: await websockets.serve(ws_handler, "::", 9339, reuse_address=True)
    except: await websockets.serve(ws_handler, "0.0.0.0", 9339, reuse_address=True)
    
    def run_web():
        from werkzeug.serving import make_server
        try: 
            srv = make_server('::', 7575, app, threaded=True)
            srv.serve_forever()
        except: 
            app.run(host='0.0.0.0', port=7575, threaded=True)
    
    threading.Thread(target=run_web, daemon=True).start()
    while True: await asyncio.sleep(3600)

if __name__ == "__main__":
    if not os.path.exists(DB_PATH): save_db({})
    asyncio.run(main())
EOF
}
# --- [ 通信逻辑：UUID 硬件指纹识别 ] ---
async def ws_handler(ws):
    sid = str(id(ws))
    WS_CLIENTS[sid] = ws
    node_uuid = None
    try:
        async for m in ws:
            d = json.loads(m)
            if d.get('token') != TOKEN: continue
            node_uuid = d.get('node_id')
            if not node_uuid: continue
            db = load_db()
            if node_uuid not in db:
                db[node_uuid] = {"hostname": d.get('hostname', 'Node'), "order": len(db)+1, "ip": ws.remote_address[0], "hidden": False, "alias": ""}
                save_db(db)
            AGENTS_LIVE[node_uuid] = {"metrics": d.get('metrics'), "status": "online", "session": sid, "last_seen": time.time()}
    except: pass
    finally:
        if node_uuid in AGENTS_LIVE and AGENTS_LIVE[node_uuid].get('session') == sid:
            AGENTS_LIVE[node_uuid]['status'] = 'offline'
        WS_CLIENTS.pop(sid, None)

async def main():
    # 1. 动态获取环境配置
    curr_env = load_env()
    
    # 2. 读取自定义端口逻辑：优先自定义，无效则回退默认
    try:
        raw_port = curr_env.get('M_PORT', '7575')
        # 校验：必须是纯数字且在合法范围内，否则视为无效
        if str(raw_port).isdigit() and 1 <= int(raw_port) <= 65535:
            web_port = int(raw_port)
        else:
            web_port = 7575
    except:
        web_port = 7575
        
    ws_port = 9339 
    
    # 3. 启动双栈 WS 通信服务
    try: 
        await websockets.serve(ws_handler, "::", ws_port, reuse_address=True)
    except: 
        await websockets.serve(ws_handler, "0.0.0.0", ws_port, reuse_address=True)
    
    # 4. 启动 Web 面板服务 (Flask)
    def run_web():
        from werkzeug.serving import make_server
        try: 
            # A. 尝试使用用户自定义端口
            print(f"[*] 正在尝试启动 Web 面板 (端口: {web_port})...")
            srv = make_server('::', web_port, app, threaded=True)
            srv.serve_forever()
        except Exception as e:
            # B. 如果自定义端口无效（如被占用），强制回退到默认 7575
            if web_port != 7575:
                print(f"[!] 端口 {web_port} 绑定失败或无效，正在回退至默认端口 7575...")
                try:
                    srv_default = make_server('::', 7575, app, threaded=True)
                    srv_default.serve_forever()
                except:
                    app.run(host='0.0.0.0', port=7575, threaded=True, debug=False)
            else:
                print(f"[!!] 默认端口 7575 亦无法启动，请检查系统端口占用。")

    # 5. 在独立线程运行 Web 服务并保持主循环
    threading.Thread(target=run_web, daemon=True).start()
    print(f"[*] Multiy Master 运行中 | WS通信端口: {ws_port}")
    
    while True: 
        await asyncio.sleep(3600)

if __name__ == "__main__":
    if not os.path.exists(DB_PATH): save_db({})
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
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
    # 动态获取通信端口，如果主控端未来修改了 9339，此处可同步适配
    WS_PORT=${M_WS_PORT:-9339}

    if [[ "$M_INPUT" == *:* ]]; then
        echo -e "${YELLOW}[物理自愈] 正在为 IPv6 执行 hosts 劫持映射...${PLAIN}"
        # 移除旧的映射防止冲突
        sed -i "/multiy.local.master/d" /etc/hosts
        echo "$M_INPUT multiy.local.master" >> /etc/hosts
        FINAL_URL="ws://multiy.local.master:$WS_PORT"
    else
        FINAL_URL="ws://$M_INPUT:$WS_PORT"
    fi
    
    echo -e "${GREEN}>>> 接入地址已锁定: $FINAL_URL${PLAIN}"
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
        # --- [ 核心重构：提取硬件唯一 UUID ] ---
        self.node_id = self._get_unique_id()

    def _get_unique_id(self):
        """尝试多种方式提取物理唯一 ID，确保重装不重名"""
        try:
            # 1. 优先读取 Linux 系统机器 ID
            if os.path.exists("/etc/machine-id"):
                with open("/etc/machine-id", 'r') as f:
                    return f.read().strip()
            # 2. 备选：使用网卡硬件 MAC 地址生成的 UUID
            return str(uuid.getnode())
        except:
            # 3. 兜底：随机生成一个并记录（不推荐，通常前两步能成功）
            return "unknown-" + socket.gethostname()

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
        """被控端核心循环：上报状态 + 监听双向指令"""
        while True:
            try:
                # 建立 WebSocket 连接，增加超时保护
                async with websockets.connect(MASTER, ping_interval=20, ping_timeout=20) as ws:
                    print(f"[{time.ctime()}] 已连接至主控: {MASTER}")
                    
                    while True:
                        # 1. 采集当前配置状态与硬件指标
                        state = self.get_config_state()
                        payload = {
                            "type": "heartbeat",
                            "token": TOKEN,
                            "node_id": self.node_id,
                            "hostname": self.hostname,
                            "metrics": self.get_metrics(),
                            "config_hash": state['hash']
                        }
                        
                        # 2. 如果配置发生变化，主动上报完整 inbounds 列表
                        if state['hash'] != self.last_config_hash:
                            payload['type'] = "report_full"
                            payload['inbounds'] = state['inbounds']
                            self.last_config_hash = state['hash']
                        
                        # 3. 发送数据包
                        await ws.send(json.dumps(payload))

                        # 4. 进入指令监听状态，限时 5 秒防止阻塞心跳
                        try:
                            msg = await asyncio.wait_for(ws.recv(), timeout=5)
                            task = json.loads(msg)
                            
                            # A. 执行远程命令
                            if task.get('type') == 'exec_cmd' or task.get('action') == 'exec_cmd':
                                res = subprocess.getoutput(task.get('cmd'))
                                await ws.send(json.dumps({"type": "cmd_res", "data": res}))
                            
                            # B. 精准同步 Inbounds 节点配置
                            elif task.get('type') == 'update_config' or task.get('action') == 'update_config':
                                new_inbounds = task.get('inbounds', [])
                                
                                if os.path.exists(SB_CONF):
                                    # 读取本地完整配置
                                    with open(SB_CONF, 'r', encoding='utf-8') as f:
                                        full_config = json.load(f)
                                    
                                    # 仅替换 inbounds 部分，保留路由和出口设置
                                    full_config['inbounds'] = new_inbounds
                                    
                                    # 写入临时文件校验
                                    with open(SB_CONF + ".tmp", 'w', encoding='utf-8') as f:
                                        json.dump(full_config, f, indent=4)
                                    
                                    # 校验配置合法性
                                    if os.system(f"{SB_PATH} check -c {SB_CONF}.tmp") == 0:
                                        os.replace(SB_CONF + ".tmp", SB_CONF)
                                        os.system("systemctl restart sing-box")
                                        await ws.send(json.dumps({"type": "msg", "res": "Sync OK", "hash": self.get_config_state()['hash']}))
                                    else:
                                        await ws.send(json.dumps({"type": "msg", "res": "Config Error"}))
                                        if os.path.exists(SB_CONF + ".tmp"): os.remove(SB_CONF + ".tmp")
                                        
                        except asyncio.TimeoutError:
                            # 没收到指令，继续下一个心跳循环
                            continue
            except Exception as e:
                print(f"[{time.ctime()}] 连接异常: {e}，10秒后重试...")
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
