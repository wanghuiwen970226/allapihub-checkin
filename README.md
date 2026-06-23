# All API Hub 每日自动签到

基于 GitHub Actions 的每日自动签到，兼容 New API 兼容站点的签到系统。

## 使用方式

### 1. 生成站点配置

从本地 All API Hub 扩展导出配置：

```bash
python3 generate_config.py
```

这会生成你的站点配置 JSON。

### 2. 配置 GitHub Secrets

1. 进入 GitHub 仓库 → **Settings** → **Secrets and variables** → **Actions**
2. 点击 **New repository secret**
3. Name: `SITES_JSON`
4. Value: 粘贴 `sites_config.json` 的内容（或直接复制下面生成的配置）

### 3. 手动触发测试

在 GitHub 仓库 → **Actions** → **All API Hub 每日签到** → **Run workflow**

### 4. 自动运行

每天北京时间 **10:00** 自动执行签到。

## 站点配置格式

```json
[
  {
    "name": "站点名称",
    "url": "https://example.com",
    "token": "your-access-token",
    "type": "new-api"
  }
]
```

### type 支持的类型

| type | 签到端点 | 说明 |
|------|---------|------|
| `new-api` | `POST /api/user/checkin` | 标准 New API 兼容站点 |
| `sub2api` | `POST /api/user/checkin` | Sub2API 兼容站点 |
| `anyrouter` | `POST /api/user/sign_in` | AnyRouter（Cookie 认证） |
| `veloera` | `POST /api/user/check_in` | Veloera 站点 |
| `wong` | `POST /api/user/checkin` | Wong/Gongyi 站点 |

## Token 过期处理

部分站点的 Token（JWT）有时效性，过期后需要手动更新 Secrets 中的 `SITES_JSON`。
