/**
 * MULTIX PRO - 核心前端逻辑 V150.0
 * 重点修复：带确认机制的序号修改、物理删除同步、双栈IP展示支持
 */
function multix() {
    return {
        // --- [ 1. 状态变量 ] ---
        agents: {}, 
        master: {}, 
        config: { user: 'GUEST', token: '', ip4: '', ip6: '' }, 
        
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
        tempToken: '', 
        tempAlias: '',
        loginUser: '', 
        loginPass: '',

        // --- [ 2. 初始化 ] ---
        async init() {
            // 恢复登录态
            if (localStorage.getItem('multiy_token')) {
                this.isLoggedIn = true;
            }
            await this.fetchState();
            // 每 3 秒自动刷新
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
                // 确保包含后端新传的 ip4, ip6 字段
                this.config = d.config || { user: 'ADMIN', token: '' };
                
                if (this.drawer && this.curSid) {
                    this.curNode = this.agents[this.curSid];
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

        // --- [ 5. 小鸡全局控制核心逻辑 ] ---
        async manageAgent(sid, action, value = null) {
            const token = localStorage.getItem('multiy_token');
            
            // 1. 立即前端响应：序号修改预防闪烁
            if (action === 'reorder') {
                this.agents[sid].order = parseInt(value);
            }

            // 2. 发送指令
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
                    if (action === 'delete') {
                        delete this.agents[sid]; // 物理删除：立即移除
                        alert("小鸡已执行物理断连并删除配置");
                    } else if (action === 'hide') {
                        this.agents[sid].hidden = true; // 隐藏：从主页顺延移除
                        alert("小鸡已在主页隐藏");
                    }
                    // 操作成功后静默刷新
                    await this.fetchState();
                }
            } catch (e) {
                console.error("Action Failed:", e);
            }
        },

        // --- [ 6. 管理员凭据修改 ] ---
        async confirmUpdateAdmin() {
            if (!this.tempUser) return alert("用户名不能为空");
            const token = localStorage.getItem('multiy_token');
            try {
                const res = await fetch('/api/update_admin', {
                    method: 'POST', 
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': token 
                    },
                    body: JSON.stringify({ 
                        user: this.tempUser, 
                        pass: this.tempPass || null, 
                        token: this.tempToken || null 
                    })
                });
                if (res.ok) {
                    alert("✅ 管理凭据更新成功，请重新登录");
                    this.logout();
                }
            } catch (e) {
                alert("修改失败，请检查网络");
            }
        },

        // --- [ 7. 辅助功能 ] ---
        // 兼容 HTTP/HTTPS 的复制逻辑
        copyToClipboard(text) {
            if (!text) return;
            if (!navigator.clipboard || !window.isSecureContext) {
                const textArea = document.createElement("textarea");
                textArea.value = text; 
                textArea.style.position = "fixed"; textArea.style.left = "-9999px";
                document.body.appendChild(textArea);
                textArea.focus(); textArea.select();
                try {
                    document.execCommand('copy');
                    alert("Token已复制(兼容模式)");
                } catch (err) {
                    alert("复制失败");
                }
                document.body.removeChild(textArea);
            } else {
                navigator.clipboard.writeText(text).then(() => alert("Token已复制"));
            }
        },

        logout() { 
            localStorage.removeItem('multiy_token'); 
            window.location.reload(); 
        },

        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([,a], [,b]) => (a.order || 0) - (b.order || 0))
            );
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
            await this.fetchState();
        },

        async addVirtualNode() {
            const res = await fetch('/api/manage_agent', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json', 
                    'Authorization': localStorage.getItem('multiy_token')
                },
                body: JSON.stringify({ action: 'add_demo' })
            });
            if (res.ok) {
                alert("虚拟小鸡部署成功");
                await this.fetchState();
            }
        }
    }
}
