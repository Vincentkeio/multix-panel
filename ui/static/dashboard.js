/**
 * MULTIX PRO - 核心前端逻辑 V155.0
 * 重点：集成 Sing-box 节点配置管理、UUID 去重兼容、管理员隐藏视图支持
 */
function multix() {
    return {
        // --- [ 1. 状态变量 ] ---
        agents: {}, 
        master: {}, 
        config: { user: 'GUEST', token: '', ip4: '', ip6: '' }, 
        
        // 界面控制
        adminModal: false, 
        nodeModal: false, // 节点管理弹窗
        isRefreshing: false,
        isLoggedIn: false, 
        showLoginModal: false,
        
        // 交互与临时变量
        editingSid: null,
        tempAlias: '',
        tempUser: '', 
        tempPass: '', 
        tempToken: '', 
        loginUser: '', 
        loginPass: '',

        // 节点配置专用
        currentNode: null,
        currentNodeInbounds: [],

        // --- [ 2. 初始化 ] ---
        async init() {
            if (localStorage.getItem('multiy_token')) {
                this.isLoggedIn = true;
            }
            await this.fetchState();
            setInterval(() => this.fetchState(), 3000); // 3秒自动刷新
        },

        // --- [ 3. 数据同步 ] ---
        async fetchState() {
            try {
                const r = await fetch('/api/state');
                if (!r.ok) throw new Error("API Offline");
                const d = await r.json();
                
                this.agents = d.agents || {};
                this.master = d.master || {};
                this.config = d.config || { user: 'ADMIN', token: '' };
                
                // 如果节点弹窗开启，同步更新弹窗内的数据
                if (this.nodeModal && this.currentNode) {
                    const latest = this.agents[this.currentNode.sid];
                    if (latest) this.currentNode = latest;
                }
            } catch(e) { 
                console.error("Data Sync Error:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 4. 登录验证 ] ---
        async doLogin() {
            if (!this.loginUser || !this.loginPass) return alert("请输入凭据");
            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ user: this.loginUser, pass: this.loginPass })
                });
                const data = await res.json();
                if (res.ok && data.status === 'success') {
                    this.isLoggedIn = true;
                    localStorage.setItem('multiy_token', data.token);
                    this.showLoginModal = false;
                    await this.fetchState();
                } else {
                    alert("登录失败: " + (data.msg || "凭据错误"));
                }
            } catch (err) {
                alert("连接主控失败");
            }
        },

        // --- [ 5. 节点管理核心逻辑 (Sing-box) ] ---
        
        // 打开节点配置弹窗
        openNodeModal(agent) {
            if (!this.isLoggedIn) return; // 游客禁止操作
            this.currentNode = agent;
            // 深拷贝 Agent 当前的 inbounds 配置，防止未保存直接修改全局状态
            this.currentNodeInbounds = JSON.parse(JSON.stringify(agent.metrics?.inbounds || []));
            this.nodeModal = true;
        },

        // 预设新增节点模板
        addNewInbound() {
            const newTag = "inbound-" + Math.floor(Math.random() * 1000);
            this.currentNodeInbounds.push({
                type: "vless",
                tag: newTag,
                listen: "::",
                listen_port: 443,
                sniff: true,
                sniff_override_destination: true
            });
        },

        // 删除单个节点
        deleteInbound(index) {
            if (confirm('确定从配置中移除该节点吗？')) {
                this.currentNodeInbounds.splice(index, 1);
            }
        },

        // 推送配置至 Agent
        async syncConfigToAgent() {
            if (!this.currentNode) return;
            const token = localStorage.getItem('multiy_token');
            try {
                const res = await fetch('/api/update_node_config', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Authorization': token 
                    },
                    body: JSON.stringify({
                        sid: this.currentNode.sid,
                        inbounds: this.currentNodeInbounds
                    })
                });
                const data = await res.json();
                if (data.res === 'ok') {
                    alert("✅ 配置已下发，Agent 正在重启 Sing-box...");
                    this.nodeModal = false;
                } else {
                    alert("❌ 下发失败: " + data.msg);
                }
            } catch (e) {
                alert("网络通讯错误");
            }
        },

        // --- [ 6. 小鸡全局控制 (原本逻辑) ] ---
        async manageAgent(sid, action, value = null) {
            const token = localStorage.getItem('multiy_token');
            if (action === 'reorder') this.agents[sid].order = parseInt(value);

            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': token 
                    },
                    body: JSON.stringify({ sid, action, value })
                });

                if (res.ok) {
                    if (action === 'delete') delete this.agents[sid];
                    await this.fetchState();
                }
            } catch (e) { console.error("Action Failed:", e); }
        },

        // --- [ 7. 辅助功能 ] ---
        get sortedAgents() {
            // 按照 Order 排序，Order 相同时在线优先
            return Object.fromEntries(
                Object.entries(this.agents).sort(([,a], [,b]) => {
                    if ((a.order || 0) !== (b.order || 0)) return (a.order || 0) - (b.order || 0);
                    return a.status === 'online' ? -1 : 1;
                })
            );
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
        },

        copyToClipboard(text) {
            if (!text) return;
            navigator.clipboard.writeText(text).then(() => alert("Token已复制"));
        },

        logout() { 
            localStorage.removeItem('multiy_token'); 
            window.location.reload(); 
        }
    }
}
