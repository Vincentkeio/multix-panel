# --- [ 后端核心逻辑：旗舰全功能固化版 ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess, psutil, platform, random, threading, socket, base64
from flask import Flask, request, jsonify, send_from_directory, render_template

# 1. 基础配置
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
        # 排序逻辑：Order 为 0 的排最后，其他按数字升序
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
ADMIN_USER = env.get('M_USER', 'admin')
ADMIN_PASS = env.get('M_PASS', 'admin')
TOKEN = env.get('M_TOKEN', 'admin')
AGENTS_LIVE = {}
WS_CLIENTS = {}

# --- [ 1. 认证路由：解决登录点击没反应 ] ---
@app.route('/api/login', methods=['POST'])
def login():
    try:
        data = request.get_json()
        if data.get('user') == ADMIN_USER and data.get('pass') == ADMIN_PASS:
            return jsonify({"status": "success", "token": TOKEN})
        return jsonify({"status": "fail", "msg": "Invalid Credentials"}), 401
    except:
        return jsonify({"status": "error"}), 500

# --- [ 2. 状态路由：解决主控 0% 加载问题 ] ---
@app.route('/api/state')
def get_state():
    db = load_db()
    # 采集主控硬件数据
    master_info = {
        "cpu": psutil.cpu_percent(),
        "mem": psutil.virtual_memory().percent,
        "disk": psutil.disk_usage('/').percent,
        "sys_ver": f"{platform.system()} {platform.release()}",
        "sb_ver": subprocess.getoutput("sing-box version").split(' ')[2] if os.path.exists("/usr/bin/sing-box") else "N/A"
    }
    # 合并 WebSocket 实时数据与数据库数据
    processed_agents = {}
    for sid, agent in db.items():
        processed_agents[sid] = agent
        if sid in AGENTS_LIVE:
            processed_agents[sid]['status'] = 'online'
            processed_agents[sid]['metrics'] = AGENTS_LIVE[sid].get('metrics', {})
        else:
            processed_agents[sid]['status'] = 'offline'
            
    return jsonify({
        "master": master_info,
        "agents": processed_agents,
        "config": {"user": ADMIN_USER, "token": TOKEN, "ip4": env.get('M_IP4', '0.0.0.0')}
    })

# --- [ 3. 管理路由：管理中心各种功能归位 ] ---
@app.route('/api/manage_agent', methods=['POST'])
def manage_agent():
    d = request.json
    if request.headers.get('Authorization') != TOKEN: return jsonify({"res":"fail"}), 403
    db = load_db()
    sid, action, val = d.get('sid'), d.get('action'), d.get('value')
    
    if sid not in db and action != 'add_virtual': return jsonify({"res":"fail"})
    
    if action == 'alias': db[sid]['alias'] = val
    elif action == 'hide': db[sid]['hidden'] = not db[sid].get('hidden', False)
    elif action == 'reorder': db[sid]['order'] = int(val)
    elif action == 'delete': del db[sid]
    elif action == 'add_virtual':
        db[sid] = {"hostname": "VIRTUAL-NODE", "alias": "演示节点", "is_demo": True, "order": 99}
        
    save_db(db)
    return jsonify({"res": "ok"})

# --- [ 原有逻辑：静态文件与订阅 ] ---
@app.route('/')
def serve_index(): return render_template('index.html')

@app.route('/static/<path:filename>')
def serve_static(filename): return send_from_directory(os.path.join(BASE_DIR, 'static'), filename)

@app.route('/sub')
def sub_handler():
    db, curr_env = load_db(), load_env()
    token, sub_type = request.args.get('token'), request.args.get('type', 'v2ray')
    if token != TOKEN: return "Unauthorized", 403
    links, clash_proxies = [], []
    for sid, agent in db.items():
        if agent.get('hidden'): continue
        ip = agent.get('ip') or curr_env.get('M_IP4')
        for inb in agent.get('metrics', {}).get('inbounds', []):
            if inb.get('type') == 'vless':
                tag, uuid = inb.get('tag', 'Node'), inb.get('uuid')
                port = inb.get('listen_port') or inb.get('port')
                sni = inb.get('reality_dest', '').split(':')[0] or 'yahoo.com'
                links.append(f"vless://{uuid}@{ip}:{port}?security=reality&sni={sni}&fp=chrome&pbk={inb.get('reality_pub','')}&sid={inb.get('short_id','')}&type=tcp&flow=xtls-rprx-vision#{tag}")
                clash_proxies.append({"name": tag, "type": "vless", "server": ip, "port": port, "uuid": uuid, "tls": True, "flow": "xtls-rprx-vision", "servername": sni, "reality-opts": {"public-key": inb.get('reality_pub',''), "short-id": inb.get('short_id','')}, "client-fingerprint": "chrome"})
    if sub_type == 'clash':
        res = "proxies:\n" + "\n".join([f"  - {{name: \"{p['name']}\", type: vless, server: \"{p['server']}\", port: {p['port']}, uuid: \"{p['uuid']}\", udp: true, tls: true, flow: \"xtls-rprx-vision\", servername: \"{p['servername']}\", reality-opts: {{public-key: \"{p['reality-opts']['public-key']}\", short-id: \"{p['reality-opts']['short-id']}\"}}, client-fingerprint: chrome}}" for p in clash_proxies])
        res += "\nproxy-groups:\n  - {name: \"GLOBAL\", type: select, proxies: [" + ",".join([f"\"{p['name']}\"" for p in clash_proxies]) + "]}\nrules:\n  - MATCH,GLOBAL"
        return res, 200, {'Content-Type': 'text/yaml; charset=utf-8'}
    return base64.b64encode('\n'.join(links).encode()).decode()

@app.route('/api/gen_keys')
def gen_keys():
    try:
        out = subprocess.getoutput("sing-box generate reality-keypair").split('\n')
        return jsonify({"private_key": out[0].split(': ')[1].strip(), "public_key": out[1].split(': ')[1].strip()})
    except: return jsonify({"private_key": "", "public_key": ""})

# --- [ WebSocket 实时通信 ] ---
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
    curr_env = load_env()
    web_port = int(curr_env.get('M_PORT', 7575))
    ws_port = 9339 
    try: await websockets.serve(ws_handler, "::", ws_port, reuse_address=True)
    except: await websockets.serve(ws_handler, "0.0.0.0", ws_port, reuse_address=True)
    
    def run_web():
        from werkzeug.serving import make_server
        # 强制双栈监听：支持 IPv6
        try: srv = make_server('::', web_port, app, threaded=True); srv.serve_forever()
        except: app.run(host='0.0.0.0', port=web_port, threaded=True, debug=False)
        
    threading.Thread(target=run_web, daemon=True).start()
    while True: await asyncio.sleep(3600)

if __name__ == "__main__":
    if not os.path.exists(DB_PATH): save_db({})
    try: asyncio.run(main())
    except KeyboardInterrupt: pass
EOF
}
