#!/usr/bin/env python3
"""探测小米运动健康云端是否暴露「睡眠呼吸暂停/呼吸质量」数据。

复用 probe_mifitness.py 的登录与签名请求逻辑。

用法（任选其一提供凭据）：
  python3 probe_apnea.py --user-id <userId> --pass-token <passToken>
  python3 probe_apnea.py --username <手机/邮箱> --password <密码>
  python3 probe_apnea.py --token <userId:passToken>
可选：
  --days N     探测最近 N 天（默认 14）
  --region R   数据区域，默认 cn
"""
import argparse
import getpass
import json
import subprocess
from datetime import datetime, timedelta

from probe_mifitness import MiFitnessProbe, region_base

# `mi-fitness-mcp setup` 存到 macOS 钥匙串的服务名与账号
KEYCHAIN_SERVICE = "mi-fitness-mcp"
KEYCHAIN_USER_ID = "mi_fitness_auth_user_id"
KEYCHAIN_PASS_TOKEN = "mi_fitness_auth_pass_token"


def load_credentials_from_keychain() -> tuple[str, str]:
    """读取 `mi-fitness-mcp setup` 存入 macOS 钥匙串的 userId/passToken。"""

    def read(account: str) -> str:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
            capture_output=True, text=True,
        )
        return result.stdout.strip() if result.returncode == 0 else ""

    return read(KEYCHAIN_USER_ID), read(KEYCHAIN_PASS_TOKEN)

# 基线 key：确认账号/会话正常、能取到真实数据
BASELINE_KEYS = [
    "steps",
    "heart_rate",
    "sleep",
    "spo2",
    "stress",
    "abnormal_heart_beat",
]

# 呼吸暂停/呼吸质量相关的候选 key（探测哪些能返回数据）
APNEA_CANDIDATE_KEYS = [
    "sleep_apnea",
    "sleep_apnea_index",
    "apnea",
    "apnea_index",
    "apnea_event",
    "sleep_breathing_quality",
    "sleep_breath",
    "breathing_quality",
    "breathing",
    "breath_quality",
    "snore",
    "snoring",
    "sleep_detail",
    "sleep_score",
    "sleep_stage",
]

# 需要在 sleep 记录的 value 里重点查找的字段路径（呼吸暂停可能内嵌在睡眠详情里）
APNEA_FIELD_HINTS = ["apnea", "breath", "breathing", "snore", "disturb", "oxygen", "resp"]


def find_key_paths(obj, path="", hints=None) -> list[str]:
    """递归找出 dict/list 中所有命中 hint 的字段路径。"""
    hits: list[str] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{path}.{k}" if path else k
            if hints and any(h in k.lower() for h in hints):
                hits.append(p)
            hits.extend(find_key_paths(v, p, hints))
    elif isinstance(obj, list):
        for i, v in enumerate(obj[:3]):
            hits.extend(find_key_paths(v, f"{path}[{i}]", hints))
    return hits


def main() -> None:
    parser = argparse.ArgumentParser(prog="probe_apnea")
    parser.add_argument("--username")
    parser.add_argument("--password")
    parser.add_argument("--token")
    parser.add_argument("--user-id")
    parser.add_argument("--pass-token")
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--region", default="cn")
    args = parser.parse_args()

    probe = MiFitnessProbe()
    if args.token or (args.user_id and args.pass_token):
        probe.login_with_token(token=args.token, user_id=args.user_id, pass_token=args.pass_token)
    else:
        # 未显式给凭据时，优先读 `mi-fitness-mcp setup` 存入的钥匙串凭据
        keychain_user_id, keychain_pass_token = load_credentials_from_keychain()
        if keychain_user_id and keychain_pass_token:
            probe.login_with_token(user_id=keychain_user_id, pass_token=keychain_pass_token)
            print(f"credentials: 从钥匙串加载（userId={keychain_user_id[:4]}****）")
        else:
            username = args.username or input("Xiaomi login (email/phone): ").strip()
            password = args.password or getpass.getpass("Xiaomi password: ")
            probe.login(username, password)
    print(f"login ok: user_id={probe.user_id}")

    base = region_base(args.region)
    end = datetime.now()
    start = end - timedelta(days=args.days)
    start_time = int(start.timestamp())
    end_time = int(end.timestamp())
    print(f"range: {start.date()} ~ {end.date()}（最近 {args.days} 天）\n")

    print("=== 一、基线 key（确认账号能取到数据） ===")
    for key in BASELINE_KEYS:
        try:
            result = probe.request(
                base, "/app/v1/data/get_fitness_data_by_time",
                {"start_time": start_time, "end_time": end_time, "key": key},
            )
            items = result.get("data_list", [])
            print(f"key={key!r:24} count={len(items)}")
        except Exception as exc:
            print(f"key={key!r:24} error={exc}")

    print("\n=== 二、呼吸暂停/呼吸质量候选 key 探测 ===")
    for key in APNEA_CANDIDATE_KEYS:
        try:
            result = probe.request(
                base, "/app/v1/data/get_fitness_data_by_time",
                {"start_time": start_time, "end_time": end_time, "key": key},
            )
            items = result.get("data_list", [])
            print(f"key={key!r:30} count={len(items)}")
            for item in items[:2]:
                print("  " + json.dumps(item, ensure_ascii=False))
        except Exception as exc:
            print(f"key={key!r:30} error={exc}")

    print("\n=== 三、sleep 记录全字段（重点：内嵌的呼吸/呼吸暂停字段） ===")
    try:
        result = probe.request(
            base, "/app/v1/data/get_fitness_data_by_time",
            {"start_time": start_time, "end_time": end_time, "key": "sleep"},
        )
        items = result.get("data_list", [])
        print(f"sleep count={len(items)}")
        for i, item in enumerate(items[:5]):
            print(f"--- sleep record #{i + 1} ---")
            print(json.dumps(item, ensure_ascii=False, indent=2))
        hits = find_key_paths(items, hints=APNEA_FIELD_HINTS)
        print("\n字段里命中（apnea/breath/snore/disturb/oxygen/resp）的路径:")
        print(hits if hits else "（无命中——云端 sleep 记录里没有呼吸相关字段）")
    except Exception as exc:
        print(f"sleep error={exc}")


if __name__ == "__main__":
    main()
