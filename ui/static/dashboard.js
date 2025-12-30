// 在 dashboard.js 的 multix() 对象中添加/更新
async manageAgent(sid, action, value = null) {
    // 权限校验
    const token = localStorage.getItem('multiy_token');
    
    // 如果是前端隐藏逻辑
    if (action === 'hide') {
        this.agents[sid].hidden = true;
        // 可选：将隐藏状态同步到后端数据库，防止刷新后重现
        await fetch('/api/manage_agent', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': token },
            body: JSON.stringify({ sid, action: 'hide' })
        });
        return;
    }

    // 删除逻辑（彻底断连）
    if (action === 'delete') {
        const res = await fetch('/api/manage_agent', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': token },
            body: JSON.stringify({ sid, action: 'delete' })
        });
        if (res.ok) delete this.agents[sid];
    }
}
