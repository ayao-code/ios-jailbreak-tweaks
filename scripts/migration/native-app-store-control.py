#!/usr/bin/env python3
"""Human-reviewed App Store input; no credentials, app data or automatic retries."""

import argparse
import datetime
import hashlib
import io
import json
import math
import os
import pathlib
import re
import shlex
import subprocess
import time
import urllib.request

from PIL import Image, ImageChops


def positive(value):
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("Expected a finite positive value")
    return value


def box(value):
    try:
        values = tuple(float(part) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("Expected left,top,right,bottom") from error
    if (len(values) != 4 or not all(math.isfinite(v) and 0 <= v <= 1 for v in values)
            or values[0] >= values[2] or values[1] >= values[3]):
        raise argparse.ArgumentTypeError("Expected a nonempty normalized box")
    return values


def catalog(item, bundle):
    if not re.fullmatch(r"[0-9]+", item):
        raise ValueError("Item ID must be numeric")
    url = "https://itunes.apple.com/lookup?country=cn&id=" + item
    with urllib.request.urlopen(url, timeout=20) as response:
        rows = json.load(response).get("results", [])
    if len(rows) != 1:
        raise ValueError("Expected one exact CN App Store listing")
    row = rows[0]
    if (row.get("bundleId") != bundle or row.get("price") != 0
            or str(row.get("trackId")) != item or not row.get("trackName")):
        raise ValueError("Item/bundle mismatch, non-free or incomplete listing")
    return {"item_id": item, "bundle_id": bundle, "name": row["trackName"],
            "minimum_os": row.get("minimumOsVersion", ""), "price": 0}


def version(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value):
        raise ValueError("Invalid OS version")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * max(0, 4 - len(parts))


class Controller:
    def __init__(self, args):
        self.args = args
        self.root = args.evidence.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        if args.host.startswith("-") or not args.socket.is_socket():
            raise ValueError("Provide an existing authorized SSH control socket")
        if not re.fullmatch(r"/[A-Za-z0-9_./-]+", args.helper_dir):
            raise ValueError("Invalid remote helper directory")
        self.ssh = ["ssh", "-S", str(args.socket.resolve()), "-o", "BatchMode=yes",
                    "-o", "ControlMaster=no", "-o", "ConnectTimeout=8", args.host]
        machine = self.remote("sysctl -n hw.machine").decode().strip()
        os_version = self.remote("sw_vers -productVersion").decode().strip()
        if machine != args.machine or os_version != args.os_version:
            raise ValueError("Live device does not match expected model/OS")

    def remote(self, command):
        result = subprocess.run(self.ssh + [command], capture_output=True,
                                timeout=self.args.timeout)
        if result.returncode:
            # Do not echo command output, host, credentials or process details.
            raise RuntimeError("Remote operation failed (exit %d)" % result.returncode)
        return result.stdout

    def helper(self, name, arguments=""):
        return shlex.quote(self.args.helper_dir + "/" + name) + " " + arguments

    def ready(self):
        state = json.loads(self.remote(self.helper("store-screen", "--state")))
        if state.get("screen_locked") is not False:
            raise RuntimeError("Device locked or unknown; no input sent")
        state = json.loads(self.remote(self.helper(
            "store-ui-input", "--check com.apple.AppStore")))
        if (state.get("unlocked_confirmed") is not True
                or state.get("expected_frontmost_confirmed") is not True):
            raise RuntimeError("Unlocked App Store not confirmed; no input sent")

    def capture(self, destination):
        data = self.remote(self.helper("store-screen"))
        with Image.open(io.BytesIO(data)) as source:
            image = source.convert("RGB")
        expected = tuple(int(v) for v in self.args.screen_size.split("x"))
        if image.size != expected or all(high == 0 for low, high in image.getextrema()):
            raise RuntimeError("Unexpected screen dimensions or blank screenshot")
        image.save(destination)
        return image

    def event(self, **fields):
        record = {"time": datetime.datetime.now().astimezone().isoformat(), **fields}
        with (self.root / "actions.jsonl").open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(record, ensure_ascii=True) + "\n")
            stream.flush()
            os.fsync(stream.fileno())

    def screenshot_path(self, filename):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+\.png", filename):
            raise ValueError("Use a simple PNG filename within the evidence directory")
        destination = self.root / filename
        if destination.exists():
            raise ValueError("Evidence already exists; choose a fresh filename")
        return destination

    def run(self):
        args = self.args
        if args.command == "capture":
            self.ready()
            self.capture(self.screenshot_path(args.filename))
            return
        if args.command == "open":
            row = catalog(args.item, args.bundle)
            if not row["minimum_os"] or version(args.os_version) < version(row["minimum_os"]):
                raise ValueError("Listing OS requirement unsupported or unknown")
            screenshot = self.screenshot_path(args.filename)
            self.ready()
            url = "itms-apps://apps.apple.com/cn/app/id" + args.item
            self.remote("uiopen --url " + shlex.quote(url))
            time.sleep(args.settle)
            self.ready()
            self.capture(screenshot)
            metadata = {"catalog": row, "screenshot_sha256": hashlib.sha256(
                screenshot.read_bytes()).hexdigest()}
            screenshot.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n")
            self.event(action="listing_opened", catalog=row, url=url,
                       screenshot=screenshot.name)
            print(row["name"] + ": inspect the screenshot before any tap")
            return
        if not args.reviewed:
            raise ValueError("Human review of title, free control and no prompt required")
        reference = self.root / args.reference
        if reference.parent.resolve() != self.root or reference.suffix != ".png":
            raise ValueError("Reference must be a PNG in the evidence directory")
        metadata = json.loads(reference.with_suffix(".json").read_text())
        digest = hashlib.sha256(reference.read_bytes()).hexdigest()
        if digest != metadata["screenshot_sha256"]:
            raise ValueError("Reviewed screenshot changed")
        row = metadata["catalog"]
        if catalog(row["item_id"], row["bundle_id"]) != row:
            raise ValueError("Catalog changed; reopen and review listing")
        log = self.root / "actions.jsonl"
        if log.exists():
            for line in log.read_text().splitlines():
                event = json.loads(line)
                if (event.get("action") == "tap_attempt"
                        and event.get("item_id") == row["item_id"]):
                    raise ValueError("Item already attempted; inspect state, never blindly repeat")
        x, y = args.x, args.y
        left, top, right, bottom = args.button_box
        if not (left < x < right and top < y < bottom):
            raise ValueError("Tap must lie inside the reviewed button box")
        self.ready()
        with Image.open(reference) as source:
            before = source.convert("RGB")
        after_path = self.screenshot_path(args.after)
        current = self.capture(self.root / "last-before.png")
        if current.size != before.size:
            raise ValueError("Reference size mismatch")
        for bounds in [args.title_box, args.button_box]:
            pixels = tuple(int(v * (before.width if i % 2 == 0 else before.height))
                           for i, v in enumerate(bounds))
            if pixels[0] >= pixels[2] or pixels[1] >= pixels[3]:
                raise ValueError("Reviewed crop is empty at native resolution")
            if ImageChops.difference(before.crop(pixels), current.crop(pixels)).getbbox():
                raise ValueError("Title/control changed; no input sent")
        self.ready()
        self.event(action="tap_attempt", item_id=row["item_id"], label=args.label,
                   reference=reference.name, title_box=args.title_box,
                   button_box=args.button_box, x=x, y=y)
        try:
            self.remote(self.helper("store-ui-input",
                        "tap com.apple.AppStore %.8f %.8f" % (x, y)))
            time.sleep(args.settle)
            self.capture(after_path)
        except Exception:
            self.event(action="tap_result_unknown", item_id=row["item_id"])
            raise RuntimeError("Tap may have succeeded; inspect current state, do not retry") from None
        self.event(action="tap_dispatched_review_required", item_id=row["item_id"],
                   screenshot=after_path.name)
        print("Inspect post-tap screenshot; no installation wait or automatic next tap")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", type=pathlib.Path, required=True)
    parser.add_argument("--host", required=True, help="Authorized SSH user@host; never logged")
    parser.add_argument("--evidence", type=pathlib.Path, required=True)
    parser.add_argument("--machine", required=True)
    parser.add_argument("--os-version", required=True)
    parser.add_argument("--screen-size", required=True, help="Live native WIDTHxHEIGHT")
    parser.add_argument("--helper-dir", default="/var/tmp")
    parser.add_argument("--timeout", type=positive, default=60)
    parser.add_argument("--settle", type=positive, default=1)
    commands = parser.add_subparsers(dest="command", required=True)
    opening = commands.add_parser("open")
    opening.add_argument("--item", required=True)
    opening.add_argument("--bundle", required=True)
    opening.add_argument("--filename", required=True)
    capture = commands.add_parser("capture")
    capture.add_argument("--filename", required=True)
    tap = commands.add_parser("tap")
    tap.add_argument("--reference", required=True)
    tap.add_argument("--after", required=True)
    tap.add_argument("--title-box", type=box, required=True)
    tap.add_argument("--button-box", type=box, required=True)
    tap.add_argument("--x", type=float, required=True)
    tap.add_argument("--y", type=float, required=True)
    tap.add_argument("--label", choices=["cloud", "get"], required=True)
    tap.add_argument("--reviewed", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[1-9][0-9]{1,3}x[1-9][0-9]{1,3}", args.screen_size):
        parser.error("Expected native WIDTHxHEIGHT")
    try:
        Controller(args).run()
    except Exception as error:
        # Exceptions from SSH/HTTP can contain private endpoints. Keep them local.
        print("Stopped safely (%s). Inspect private evidence before continuing."
              % type(error).__name__)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
