#!/usr/bin/env python3
"""Quickly validate a fresh Mi Fitness userId/passToken against account.xiaomi.com.

Run interactively (input is hidden):
    ./.venv/bin/python check_token.py

Or with env vars (avoid shell history by using the interactive mode when possible):
    MI_USER_ID=... MI_PASS_TOKEN=... ./.venv/bin/python check_token.py
"""
import asyncio
import json
import os
import sys

import getpass
import httpx


def mask(value, keep=4):
    if not value:
        return value
    return value[:keep] + "***"


async def main() -> int:
    uid = os.environ.get("MI_USER_ID")
    ptoken = os.environ.get("MI_PASS_TOKEN")
    if not uid:
        uid = getpass.getpass("Mi Fitness userId: ").strip()
    if not ptoken:
        ptoken = getpass.getpass("Mi Fitness passToken: ").strip()

    if not uid or not ptoken:
        print("❌ 必须提供 userId 和 passToken")
        return 1

    print(f"userId: {mask(uid)} | passToken len: {len(ptoken)}")
    async with httpx.AsyncClient(timeout=20, follow_redirects=False) as client:
        response = await client.get(
            "https://account.xiaomi.com/pass/serviceLogin?_json=true&sid=miothealth",
            headers={"Cookie": f"userId={uid}; passToken={ptoken}"},
        )
        print("HTTP status:", response.status_code)
        if not response.text.startswith("&&&START&&&"):
            print("❌ 响应不是预期的 &&&START&&& 格式，开头如下：")
            print(response.text[:200])
            return 1

        payload = json.loads(response.text[len("&&&START&&&"):])
        if "passToken" in payload and "ssecurity" in payload:
            print("✅ token 有效！已换取新的 passToken + ssecurity。")
            print("   现在可以运行: ./.venv/bin/mi-fitness-mcp setup 重新配置")
            return 0

        code = payload.get("code")
        desc = payload.get("description")
        print(f"❌ 登录被拒绝：code={code} desc={desc}")
        if code == 70016:
            print("   70016 登录验证失败 —— token 通常已过期或无效。")
            print("   请重新登录 account.xiaomi.com，重新复制最新的 passToken / userId。")
        return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
