#!/usr/bin/env python3
"""
从本地 All API Hub 扩展数据导出站点配置，用于 GitHub Actions 签到。

用法:
    python3 generate_config.py

输出:
    - 打印 JSON 配置，可直接用于 SITES_JSON
    - 可选: 保存到文件
"""

import re
import json
import os
import sys

# Chrome 扩展 Local Extension Settings 路径
EXTENSION_ID = "lapnciffpekdengooeolaienkeoilfeo"
CHROME_PROFILE = os.path.expanduser(
    "~/Library/Application Support/Google/Chrome/Default"
)
STORAGE_DIR = os.path.join(CHROME_PROFILE, "Local Extension Settings", EXTENSION_ID)


def extract_config():
    """从 LevelDB 日志文件中提取站点配置"""
    if not os.path.isdir(STORAGE_DIR):
        print(f"错误: 未找到扩展存储目录: {STORAGE_DIR}", file=sys.stderr)
        print("请确保 All API Hub 扩展已安装并配置了站点。", file=sys.stderr)
        sys.exit(1)

    # 读取最新的 log 文件
    log_files = sorted(
        [f for f in os.listdir(STORAGE_DIR) if f.endswith(".log")],
        reverse=True,
    )

    if not log_files:
        print("错误: 未找到 LevelDB 日志文件", file=sys.stderr)
        sys.exit(1)

    data = b""
    for lf in log_files[:2]:  # 读最新的两个 log 文件
        path = os.path.join(STORAGE_DIR, lf)
        with open(path, "rb") as f:
            data += f.read()

    text = data.decode("utf-8", errors="replace")

    # 提取所有站点
    sites = []
    seen_urls = set()

    # 逐跳查找 site_name
    offset = 0
    while True:
        idx = text.find('\\"site_name\\":\\"', offset)
        if idx < 0:
            break

        # Find site name value
        val_start = idx + len('\\"site_name\\":\\"')
        val_end = text.find('\\"', val_start)
        if val_end < 0:
            break
        site_name = text[val_start:val_end]

        # Look in surrounding context for other fields
        chunk_end = min(val_end + 2000, len(text))
        chunk = text[idx:chunk_end]

        def extract(field):
            pat = '\\"' + field + '\\":\\"'
            p = chunk.find(pat)
            if p >= 0:
                vs = p + len(pat)
                ve = chunk.find('\\"', vs)
                if ve > 0:
                    return chunk[vs:ve]
            return None

        def extract_bool(field):
            pat = '\\"' + field + '\\":'
            p = chunk.find(pat)
            if p >= 0:
                vs = p + len(pat)
                if chunk[vs : vs + 4] == "true":
                    return True
                elif chunk[vs : vs + 5] == "false":
                    return False
            return None

        site_url = extract("site_url")
        site_type = extract("site_type")
        token = extract("access_token")
        username = extract("username")
        user_id = extract("id")
        disabled = extract_bool("disabled")
        detect = extract_bool("enableDetection")
        auto = extract_bool("autoCheckInEnabled")

        if site_url and site_url not in seen_urls:
            seen_urls.add(site_url)

            # 确定站点类型映射
            type_map = {
                "new-api": "new-api",
                "sub2api": "sub2api",
                "anyrouter": "anyrouter",
                "veloera": "veloera",
            }
            mapped_type = type_map.get(site_type or "", "new-api")

            site_info = {
                "name": site_name,
                "url": site_url.rstrip("/"),
                "token": token or "",
                "user_id": user_id or "",
                "type": mapped_type,
                "username": username or "",
                "detection_enabled": detect if detect is not None else False,
                "auto_checkin_enabled": auto if auto is not None else False,
                "disabled": disabled if disabled is not None else True,
            }
            sites.append(site_info)

        offset = val_end + 1

    return sites


def main():
    sites = extract_config()

    print("=" * 60)
    print(f"找到 {len(sites)} 个站点配置")
    print("=" * 60)
    print()

    # 过滤出已启用的站点（未禁用 + 签到检测或自动签到开启）
    enabled = [s for s in sites if not s["disabled"] and s["detection_enabled"]]
    auto_enabled = [s for s in sites if not s["disabled"] and s["auto_checkin_enabled"]]

    print(f"签到检测开启: {len(enabled)} 个")
    print(f"自动签到开启: {len(auto_enabled)} 个")
    print()

    for s in enabled + [s for s in auto_enabled if s not in enabled]:
        tags = []
        if s["detection_enabled"]:
            tags.append("检测")
        if s["auto_checkin_enabled"]:
            tags.append("自动")
        print(f"  [{', '.join(tags)}] {s['name']:20s} {s['url']}")

    print()
    print("=" * 60)
    print("生成 SITES_JSON 配置（仅已启用 + 签到开启的站点）:")
    print("=" * 60)

    # Generate config for checkin-enabled sites
    checkin_config = []
    seen = set()
    for s in enabled + auto_enabled:
        if s["url"] not in seen and s["token"]:
            seen.add(s["url"])
            entry = {
                "name": s["name"],
                "url": s["url"],
                "token": s["token"],
                "type": s["type"],
            }
            # 只有 new-api 类型需要 user_id (New-API-User header)
            if s["user_id"] and s["type"] in ("new-api", "sub2api"):
                entry["user_id"] = s["user_id"]
            checkin_config.append(entry)

    config_json = json.dumps(checkin_config, ensure_ascii=False, indent=2)
    print()
    print(config_json)
    print()

    # 同时保存到文件
    output_path = os.path.join(os.path.dirname(__file__) or ".", "sites_config.json")
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(checkin_config, f, ensure_ascii=False, indent=2)
    print(f"已保存到: {output_path}")
    print()
    print("将此 JSON 添加到 GitHub Secrets 的 SITES_JSON 中。")


if __name__ == "__main__":
    main()
