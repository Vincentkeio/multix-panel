/**
 * MULTIX PRO - 核心前端逻辑 V135.0
 * 针对 IPv6 环境及模块化 UI 深度优化
 */
function multix() {
    return {
        // --- [ 1. 状态变量 ] ---
        agents: {}, 
        master: {}, 
        config: { user: 'GUEST' }, 
        
        // 界面控制
        drawer: false, 
        adminModal: false, 
        isRefreshing: false,
        isLoggedIn: false, 
        showLoginModal: false,
        
        // 交互变量
        curSid: '', 
        curNode: {}, 
        editingSid: null,
        tempUser: '', 
        tempPass: '', 
        tempAlias: '',
        loginUser: '', 
        loginPass: '',

        // --- [ 2. 初始化 ] ---
        async init() {
            // 检查浏览器缓存，恢复登录态
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
                // 适配 IPv6/V4 双栈的相对路径请求
                const r = await fetch('/api/state');
                if (!r.ok) throw new Error("API Offline");
                const d = await r.json();
                
                this.agents = d.agents || {};
                this.master = d.master || {};
                this.config = d.config || { user: 'ADMIN' };
                
                // 如果侧边栏打开，同步当前节点实时数据
                if (this.drawer && this.curSid) {
                    this.curNode = this.agents[this.curSid];
                }
            } catch(e) { 
                console.error("数据链路异常:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 4. 登录验证核心 (重点补全) ] ---
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
                    // 登录成功：更新状态并持久化
                    this.isLoggedIn = true;
                    this.config.user = data.user;
                    this.showLoginModal = false;
                    localStorage.setItem('multiy_token', data.token);
                    
                    // 清空输入框
                    this.loginUser = '';
                    this.loginPass = '';
                    
                    await this.fetchState();
                    console.log("控制台解锁成功");
                } else {
                    alert("登录失败: " + (data.msg || "凭据不正确"));
                    this.loginPass = '';
                }
            } catch (err) {
                alert("网络连接失败，请检查 IPv6 连通性");
            }
        },

        // --- [ 5. 管理功能 ] ---
        openAdminModal() {
            this.tempUser = this.config.user || 'admin';
            this.tempPass = '';
            this.adminModal = true;
        },

        async confirmUpdateAdmin() {
            if (!this.tempUser) return alert("用户名不能为空");
            
            const res = await fetch('/api/update_admin', {
                method: 'POST', 
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    user: this.tempUser, 
                    pass: this.tempPass || null 
                })
            });
            
            if (res.ok) { 
                this.adminModal = false; 
                await this.fetchState(); 
                alert("管理凭据已更新并实时生效"); 
            }
        },

        logout() {
            if (confirm("确定要退出并锁定控制台吗？")) {
                localStorage.removeItem('multiy_token');
                this.isLoggedIn = false;
                window.location.reload();
            }
        },

        // 辅助：排序节点
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([,a], [,b]) => (a.order || 0) - (b.order || 0))
            );
        },

        openDrawer(sid) {
            // 只有登录后才允许打开详情抽屉
            if (!this.isLoggedIn) {
                this.showLoginModal = true;
                return;
            }
            this.curSid = sid;
            this.curNode = this.agents[sid];
            this.drawer = true;
        }
    }
}
