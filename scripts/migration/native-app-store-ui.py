#!/usr/bin/env python3
"""Scoped native App Store re-downloads; never access account tokens or app data.

Uses the retained standalone ui-input and screen-observe sources, compiled with
the AppStore-only allowed-input variant. Screenshots/OCR stay on this Mac.
Each request requires live identity, unlocked AppStore, exact catalog title,
stable title/button crop, and a positively recognized cloud or free Get button.
No purchases, credentials, whitelist changes, sensitive-app launches, or retries.
"""

import argparse
import datetime
import io
import json
import pathlib
import re
import shlex
import subprocess
import time

from PIL import Image, ImageChops, ImageFilter


def normalized(text):
    return re.sub(r"[\W_]+", "", text).lower()


def blue_mask(image):
    image = image.convert("RGB")
    mask = Image.new("L", image.size)
    mask.putdata([255 if b > 150 and b > r * 1.4 and b > g * 1.06 else 0
                  for r, g, b in image.getdata()])
    return mask


def cloud_point(image, template):
    small = image.resize((430, 932))
    mask = blue_mask(small)
    pixels = mask.filter(ImageFilter.MaxFilter(5)).load()
    seen = set()
    candidates = []
    # Download controls are left of the share control and below the app title.
    for y in range(80, 470):
        for x in range(80, 275):
            if not pixels[x, y] or (x, y) in seen:
                continue
            todo = [(x, y)]
            seen.add((x, y))
            component = []
            while todo:
                a, b = todo.pop()
                component.append((a, b))
                for c, d in [(a-1, b), (a+1, b), (a, b-1), (a, b+1)]:
                    if 80 <= c < 275 and 80 <= d < 470 and (c, d) not in seen and pixels[c, d]:
                        seen.add((c, d))
                        todo.append((c, d))
            left = min(a for a, b in component)
            right = max(a for a, b in component) + 1
            top = min(b for a, b in component)
            bottom = max(b for a, b in component) + 1
            width, height = right-left, bottom-top
            if not (16 <= width <= 42 and 16 <= height <= 42):
                continue
            candidate = mask.crop((left, top, right, bottom))
            candidate = candidate.crop(candidate.getbbox()).resize((32, 32))
            diff = sum(ImageChops.difference(candidate, template).getdata()) / (32*32*255)
            if diff < .14:
                candidates.append(((left+right)/2/430, (top+bottom)/2/932, diff))
    return candidates[0][:2] if len(candidates) == 1 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--catalog", type=pathlib.Path, required=True)
    parser.add_argument("--evidence", type=pathlib.Path, required=True)
    parser.add_argument("--template", type=pathlib.Path, required=True)
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--settle-seconds", type=float, default=1.1)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    ssh = ["ssh", "-S", args.socket, "-o", "BatchMode=yes", "-T", "placeholder"]
    report_path = args.evidence / "requests.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else []
    template = Image.open(args.template).convert("L").resize((32, 32))

    def remote(command):
        return subprocess.run(ssh + [command], capture_output=True, check=True, timeout=20).stdout

    def capture():
        data = remote("/var/mobile/restore-tools/store-screen")
        image = Image.open(io.BytesIO(data)).convert("RGB")
        if image.size != (1290, 2796) or all(high == 0 for low, high in image.getextrema()):
            raise RuntimeError("Unexpected display dimensions or blank screenshot")
        return image

    def read_text(image, path):
        image.save(path)
        result = subprocess.run(["app/safe-domain-probe/build/screen-text", str(path)],
                                capture_output=True, check=True, timeout=20)
        return json.loads(result.stdout)

    def save_record(row, status, **details):
        record = {"bundle_id": row["bundle_id"], "name": row["name"],
                  "observed_at": datetime.datetime.now().astimezone().isoformat(),
                  "status": status, **details}
        report.append(record)
        temporary = report_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        temporary.replace(report_path)
        print(row["name"], status, flush=True)

    identity = remote("sysctl -n hw.machine; sw_vers").decode()
    if not all(s in identity for s in ["iPhone15,3", "16.3", "20D47"]):
        raise RuntimeError("Wrong device")
    rows = json.loads(args.catalog.read_text())
    done = {r["bundle_id"] for r in report}
    priority = {b: i for i, b in enumerate(["com.ss.iphone.ugc.Aweme", "com.taobao.taobao4iphone",
                "com.autonavi.amap", "com.qunar.iphoneclient8", "cn.damai.iphone", "com.taobao.fleamarket"])}
    rows.sort(key=lambda r: priority.get(r["bundle_id"], 100))
    count = 0
    for row in rows:
        bundle = row["bundle_id"]
        if bundle in done or (args.only and bundle not in args.only):
            continue
        if count >= args.limit:
            break
        lock_state = json.loads(remote("/var/mobile/restore-tools/store-screen --state"))
        if lock_state.get("screen_locked") is not False:
            raise RuntimeError("Device locked: user authentication required; no input sent")
        count += 1
        if not row.get("item_id"):
            save_record(row, "skipped_no_public_listing")
            continue
        live = remote("uicache -l").decode()
        if any(line.startswith(bundle + " : ") for line in live.splitlines()):
            save_record(row, "already_registered")
            continue
        remote("uiopen --url " + shlex.quote("itms-apps://itunes.apple.com/cn/app/id" + str(row["item_id"])))
        time.sleep(args.settle_seconds)
        before = capture()
        path = args.evidence / (bundle + ".before.png")
        texts = read_text(before, path)
        title = [t for t in texts if .10 < t["y"] < .36 and .23 < t["x"] < .95]
        names = [normalized(row["name"]), normalized(row.get("store_name", ""))]
        matched_titles = [t for t in title if normalized(t["text"]) and any(n and (normalized(t["text"]) == n or
                      (len(normalized(t["text"])) >= 4 and n.startswith(normalized(t["text"]))))
                      for n in names)]
        matched = bool(matched_titles)
        point = cloud_point(before, template)
        if not point and row.get("price") == 0:
            gets = [t for t in texts if t["text"] == "获取" and .15 < t["x"] < .65 and .12 < t["y"] < .47]
            if len(gets) == 1:
                point = (gets[0]["x"], gets[0]["y"])
        if not matched or not point:
            save_record(row, "skipped_unconfirmed_page_or_download_control", title_matched=matched,
                        screenshot=str(path))
            continue
        current = capture()
        # Compare the exact app title and control, excluding marquee subtitles.
        boxes = [(int(before.width*(point[0]-.04)), int(before.height*(point[1]-.02)),
                  int(before.width*(point[0]+.04)), int(before.height*(point[1]+.02)))]
        for t in matched_titles:
            boxes.append((int(before.width*t["left"]), int(before.height*t["top"]),
                          int(before.width*(t["left"]+t["width"])),
                          int(before.height*(t["top"]+t["height"]))))
        if any(ImageChops.difference(before.crop(box), current.crop(box)).getbbox() for box in boxes):
            save_record(row, "skipped_changed_page_no_input", screenshot=str(path))
            continue
        remote("/var/mobile/restore-tools/store-ui-input tap com.apple.AppStore " + shlex.join([str(point[0]), str(point[1])]))
        time.sleep(.55)
        after = capture()
        after_path = args.evidence / (bundle + ".after.png")
        after_text = read_text(after, after_path)
        modal = " ".join(t["text"] for t in after_text if .32 < t["y"] < .78)
        if any(s in modal for s in ["输入密码", "请输入密码", "登录以完成", "验证身份", "Apple ID", "确认购买", "确认付款"]):
            save_record(row, "authentication_or_purchase_prompt_stop", screenshot=str(after_path))
            raise RuntimeError("Authentication/purchase prompt: human action required")
        save_record(row, "native_download_tap_requested_not_yet_install_verified", screenshot=str(after_path))


if __name__ == "__main__":
    main()
