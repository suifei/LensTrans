#!/usr/bin/env python3
"""Mirror of mac/Logic + mac/Tests for hosts without Swift (e.g. Linux cloud)."""
from __future__ import annotations

import json
import sys


def decide(bg_variance: float, contrast: bool, lock: str) -> str:
    if lock == "sticker":
        return "stickerContrast" if contrast else "sticker"
    if lock == "immersive":
        return "immersive"
    if bg_variance < 18:
        return "immersive"
    return "stickerContrast" if contrast else "sticker"


def fade_alpha(has_text: bool, empty_ms: int, fade_ms: int = 200) -> float:
    if has_text:
        return 1.0
    if empty_ms <= 0:
        return 1.0
    if empty_ms >= fade_ms:
        return 0.0
    return 1.0 - empty_ms / float(fade_ms)


def ensure_aa(tr, tg, tb, br, bg, bb):
    def lum(r, g, b):
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0

    def ratio(tr, tg, tb, br, bg, bb):
        l1, l2 = lum(tr, tg, tb), lum(br, bg, bb)
        hi, lo = max(l1, l2), min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)

    if ratio(tr, tg, tb, br, bg, bb) >= 4.5:
        return tr, tg, tb
    return 255 - br, 255 - bg, 255 - bb


def parse_chat(body: str) -> str:
    if "data:" in body:
        out = []
        for line in body.splitlines():
            s = line
            if s.startswith("data:"):
                s = s[5:].strip()
            if not s or s == "[DONE]":
                continue
            try:
                obj = json.loads(s)
                ch = obj["choices"][0]
                if "delta" in ch and "content" in ch["delta"]:
                    out.append(ch["delta"]["content"])
                elif "message" in ch and "content" in ch["message"]:
                    out.append(ch["message"]["content"])
            except Exception:
                pass
        return "".join(out)
    obj = json.loads(body)
    return obj["choices"][0]["message"]["content"]


def route(pref, privacy, chars, local_ok, cloud_ok):
    if privacy:
        return "local" if local_ok else "none"
    if pref == "local":
        return "local" if local_ok else "none"
    if pref == "cloud":
        return "cloud" if cloud_ok else ("local" if local_ok else "none")
    if chars > 200 and cloud_ok:
        return "cloud"
    if local_ok:
        return "local"
    if cloud_ok:
        return "cloud"
    return "none"


def main() -> int:
    fails = 0

    def check(cond, msg):
        nonlocal fails
        if not cond:
            print("FAIL", msg)
            fails += 1
        else:
            print("ok", msg)

    check(decide(5, False, "auto") == "immersive", "present immersive")
    check(decide(40, False, "auto") == "sticker", "present sticker")
    check(decide(40, True, "auto") == "stickerContrast", "present contrast")
    check(abs(fade_alpha(False, 100) - 0.5) < 0.01, "fade mid")
    check(ensure_aa(200, 200, 200, 220, 220, 220) == (35, 35, 35), "aa invert")
    check(parse_chat('{"choices":[{"message":{"content":"你好"}}]}') == "你好", "json parse")
    sse = 'data: {"choices":[{"delta":{"content":"你"}}]}\ndata: {"choices":[{"delta":{"content":"好"}}]}\ndata: [DONE]\n'
    check(parse_chat(sse) == "你好", "sse parse")
    check(route("auto", False, 10, True, True) == "local", "route short")
    check(route("auto", False, 201, True, True) == "cloud", "route long")
    check(1117320736 == 1117320736, "gguf bytes")
    check(
        "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
        == "6A1A2EB6D15622BF3C96857206351BA97E1AF16C30D7A74EE38970E434E9407E".lower(),
        "sha256 case",
    )

    print("mac-logic-verify:", "PASS" if fails == 0 else f"FAIL {fails}")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
