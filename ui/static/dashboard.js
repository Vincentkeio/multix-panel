/**
 * MULTIX PRO - 核心前端逻辑 V140.0
 * 支持管理员凭据(含Token)轮换与动态脱敏渲染
 */
function multix() {
    return {
        // --- [ 1. 状态变量 ] ---
        agents: {}, 
        master: {}, 
        config: { user: 'GUEST', token: '' }, 
        
        // 界面控制
        drawer: false, 
        adminModal: false, 
        isRefreshing: false,
        isLoggedIn: false, 
        showLoginModal: false,
        
        // 交互与临时变量
        curSid: '', 
        curNode: {}, 
        editingSid: null,
        tempUser: '', 
        tempPass: '', 
        tempToken: '', // 新增：用于修改 Token
        tempAlias: '',
        loginUser: '', 
        loginPass: '',

        // --- [ 2. 初始化 ] ---
        async init() {
            // 检查浏览器缓存恢复登录态
            const savedToken = localStorage.getItem('multiy_token');
            if (savedToken) {
                this.isLoggedIn = true;
            }
            
            await this.fetchState();
            // 每 3 秒自动刷新一次集群数据
            setInterval(() => this.fetchState(), 3000);
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
                
                if (this.drawer && this.curSid) {
                    this.curNode = this.agents[this.curSid];
                }
            } catch(e) { 
                console.error("数据链路异常:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 4. 登录验证 ] ---
        async doLogin() {
            if (!this.loginUser || !this.loginPass) {
                alert("请输入完整的管理账号和密码");
                return;
            }

            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ 
                        user: this.loginUser, 
                        pass: this.loginPass 
                    })
                });

                const data = await res.json();

                if (res.ok && data.status === 'success') {
                    this.isLoggedIn = true;
                    this.config.user = data.user;
                    this.showLoginModal = false;
                    // 保存 Token 用于后续 API 鉴权
                    localStorage.setItem('multiy_token', data.token);
                    
                    this.loginUser = '';
                    this.loginPass = '';
                    
                    await this.fetchState();
                } else {
                    alert("登录失败: " + (data.msg || "凭据不正确"));
                    this.loginPass = '';
                }
            } catch (err) {
                alert("网络连接失败，请检查 IPv6 连通性");
            }
        },

        // --- [ 5. 管理功能 ] ---
        
        // 修改凭据核心逻辑
        async confirmUpdateAdmin() {
            if (!this.tempUser) return alert("用户名不能为空");
            
            const token = localStorage.getItem('multiy_token');
            const res = await fetch('/api/update_admin', {
                method: 'POST', 
                headers: { 
                    'Content-Type': 'application/json',
                    'Authorization': token // 带上凭据进行后端鉴权
                },
                body: JSON.stringify({ 
                    user: this.tempUser, 
                    pass: this.tempPass || null,
                    token: this.tempToken || null // 支持轮换 Token
                })
            });
            
            if (res.ok) { 
                this.adminModal = false; 
                alert("管理凭据已更新。为保障安全，请重新登录。"); 
                this.logout(); // 强制注销以验证新凭据
            } else {
                const err = await res.json();
                alert("更新失败: " + (err.msg || "权限不足"));
            }
        },

        // 辅助：一键复制 Token
        copyToClipboard(text) {
            if(!text) return;
            navigator.clipboard.writeText(text).then(() => {
                alert("Token 已成功复制到剪贴板");
            }).catch(err => {
                console.error('无法复制:', err);
            });
        },

        // 登出逻辑
        logout() {
            localStorage.removeItem('multiy_token');
            this.isLoggedIn = false;
            window.location.reload();
        },

        // 辅助：排序节点
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([,a], [,b]) => (a.order || 0) - (b.order || 0))
            );
        },

        // 节点抽屉控制
        openDrawer(sid) {
            if (!this.isLoggedIn) {
                this.showLoginModal = true;
                return;
            }
            this.curSid = sid;
            this.curNode = this.agents[sid];
            this.drawer = true;
        },

        // 虚拟节点管理
        async addVirtualNode() {
            // 调用后端的虚拟节点增加接口
            const res = await fetch('/api/manage_agent', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'Authorization': localStorage.getItem('multiy_token')
                },
                body: JSON.stringify({ action: 'add_demo' })
            });
            if(res.ok) await this.fetchState();
        }
    }
}
