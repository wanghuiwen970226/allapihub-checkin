#!/bin/bash
# ============================================================
# All API Hub 多站点自动签到脚本
# 兼容 New API / Sub2API / AnyRouter 等站点
#
# 使用方法:
#   1. 设置环境变量 SITES_JSON (JSON 格式的站点列表)
#   2. 运行: ./checkin.sh
#
# SITES_JSON 格式:
#   [
#     {"name":"站点名","url":"https://example.com","token":"sk-xxx","user_id":"12345","type":"new-api"},
#     {"name":"站点2","url":"https://site2.com","token":"sk-yyy","user_id":"67890","type":"new-api"}
#   ]
# ============================================================

set -euo pipefail

# 当前时间
NOW=$(date "+%Y-%m-%d %H:%M:%S")
MONTH=$(date "+%Y-%m")

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 结果统计
TOTAL=0
SUCCESS=0
FAILED=0
SKIPPED=0
ALREADY=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  All API Hub 自动签到${NC}"
echo -e "${BLUE}  时间: $NOW${NC}"
echo -e "${BLUE}========================================${NC}"

# 检查 SITES_JSON 是否设置
if [ -z "${SITES_JSON:-}" ]; then
    echo -e "${RED}错误: 未设置 SITES_JSON 环境变量${NC}"
    echo "请设置环境变量 SITES_JSON 为 JSON 格式的站点配置"
    echo ""
    echo "格式: [{\"name\":\"站点\",\"url\":\"https://...\",\"token\":\"...\",\"type\":\"new-api\"}, ...]"
    exit 1
fi

# 解析站点数量
SITE_COUNT=$(echo "$SITES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo -e "共 ${SITE_COUNT} 个站点配置\n"

# 遍历每个站点执行签到
echo "$SITES_JSON" | python3 -c "
import sys, json, urllib.request, urllib.error, ssl, os

sites = json.load(sys.stdin)
ssl_ctx = ssl.create_default_context()

month = __import__('datetime').datetime.now().strftime('%Y-%m')
results = {'total': len(sites), 'success': 0, 'failed': 0, 'skipped': 0, 'already': 0}

for site in sites:
    name = site.get('name', 'Unknown')
    url = site.get('url', '').rstrip('/')
    token = site.get('token', '')
    user_id = site.get('user_id', '')
    stype = site.get('type', 'new-api')

    print(f'--- {name} ({url}) ---')

    if not url or not token:
        print(f'  [SKIP] 配置不完整')
        results['skipped'] += 1
        continue

    # 根据站点类型选择签到端点
    if stype == 'anyrouter':
        endpoint = '/api/user/sign_in'
        headers = {
            'Content-Type': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'Cookie': f'access_token={token}'
        }
    elif stype == 'veloera':
        endpoint = '/api/user/check_in'
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {token}'
        }
    elif stype == 'wong':
        endpoint = '/api/user/checkin'
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {token}'
        }
    else:
        # new-api / sub2api / 默认
        endpoint = '/api/user/checkin'
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {token}'
        }
        # New API 站点需要 user_id 作为 New-API-User 头
        if user_id:
            headers['New-API-User'] = user_id

    checkin_url = f'{url}{endpoint}'

    try:
        # 先检查今日是否已签到（仅 new-api 类型支持状态查询）
        if stype in ('new-api', 'sub2api', 'wong'):
            status_url = f'{url}/api/user/checkin?month={month}'
            status_headers = {
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {token}'
            }
            if user_id and stype != 'wong':
                status_headers['New-API-User'] = user_id
            try:
                status_req = urllib.request.Request(status_url, headers=status_headers, method='GET')
                with urllib.request.urlopen(status_req, context=ssl_ctx, timeout=15) as resp:
                    status_data = json.loads(resp.read().decode())
                    if status_data.get('stats', {}).get('checked_in_today', False):
                        print(f'  [SKIP] 今日已签到，跳过')
                        results['already'] += 1
                        continue
            except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError, KeyError) as e:
                # 状态检查失败，继续尝试签到
                pass

        # 执行签到
        req_body = b'{}'
        if stype == 'anyrouter':
            req_body = b'{}'

        req = urllib.request.Request(
            checkin_url,
            data=req_body,
            headers=headers,
            method='POST'
        )

        with urllib.request.urlopen(req, context=ssl_ctx, timeout=30) as resp:
            body = resp.read().decode()
            result = json.loads(body)

        msg = result.get('message', '')
        msg_lower = msg.lower()

        if result.get('success') and ('success' in msg_lower or '签到成功' in msg):
            print(f'  [OK] 签到成功!')
            results['success'] += 1
        elif result.get('success') and ('checked' in msg_lower or '已签到' in msg):
            print(f'  [OK] 今日已签到')
            results['already'] += 1
        elif 'already' in msg_lower or 'checked' in msg_lower or '已签到' in msg:
            print(f'  [OK] 今日已签到')
            results['already'] += 1
        elif result.get('data', {}).get('checked_in') == True:
            print(f'  [OK] 今日已签到')
            results['already'] += 1
        elif result.get('data', {}).get('enabled') == False:
            print(f'  [WARN] 站点已关闭签到功能')
            results['skipped'] += 1
        else:
            print(f'  [FAIL] {msg[:80]}')
            results['failed'] += 1

    except urllib.error.HTTPError as e:
        if e.code == 400:
            body = e.read().decode()
            if 'already' in body.lower() or 'checked' in body.lower():
                print(f'  [OK] 今日已签到 (400 + already)')
                results['already'] += 1
            else:
                print(f'  [FAIL] HTTP {e.code}: {body[:80]}')
                results['failed'] += 1
        elif e.code == 429:
            print(f'  [FAIL] 请求过于频繁 (429)')
            results['failed'] += 1
        else:
            print(f'  [FAIL] HTTP {e.code}')
            results['failed'] += 1
    except urllib.error.URLError as e:
        print(f'  [FAIL] 网络错误: {e.reason}')
        results['failed'] += 1
    except json.JSONDecodeError:
        print(f'  [FAIL] 响应解析失败')
        results['failed'] += 1
    except Exception as e:
        print(f'  [FAIL] {str(e)[:80]}')
        results['failed'] += 1

    print()

# 输出汇总
print('========================================')
print(f'  总计: {results[\"total\"]} | 成功: {results[\"success\"]} | 已签到: {results[\"already\"]} | 失败: {results[\"failed\"]} | 跳过: {results[\"skipped\"]}')
print('========================================')

# 设置 GitHub Actions 输出
if 'GITHUB_OUTPUT' in os.environ:
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write(f'total={results[\"total\"]}\\n')
        f.write(f'success={results[\"success\"]}\\n')
        f.write(f'already={results[\"already\"]}\\n')
        f.write(f'failed={results[\"failed\"]}\\n')
        f.write(f'skipped={results[\"skipped\"]}\\n')

# 如果有失败，非零退出
if results['failed'] > 0:
    sys.exit(1)
"
