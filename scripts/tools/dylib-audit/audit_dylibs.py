#!/usr/bin/env python3
"""Static inspection only: never execute, inject, or rewrite a Mach-O."""

import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import html
import json
from pathlib import Path
import re
import struct
import subprocess


RUNTIME_NAMES = {
    "cydiasubstrate", "libsubstrate.dylib", "libsubstitute.dylib",
    "libellekit.dylib", "ellekit",
}
LOAD_COMMANDS = {0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20}
LABELS = {
    "system_linked_candidate": "仅系统依赖候选，未实测",
    "bundled_runtime_candidate": "需工具内置Hook库，静态候选",
    "needs_dependency_review": "存在额外依赖/符号，需复核",
    "needs_architecture_review": "CPU架构或最低系统版本需复核",
    "needs_binary_review": "二进制结构异常/混淆，需复核",
    "system_process_target": "目标是系统进程，不是普通App插件",
    "needs_functional_review": "未见明确生效注册，需功能复核",
}
GATES = {
    "sensitive_target_no_injection": "高敏目标：不注入",
    "non_ad_or_detection_review": "非广告/检测相关线索：先复核",
    "settings_resources_review": "设置/资源/动态加载线索：先复核",
    "no_target_mapping": "目标映射缺失：先复核",
    "no_additional_static_flag": "未见额外静态标记，不代表安全认证",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args):
    result = subprocess.run(args, capture_output=True, timeout=45)
    return {"returncode": result.returncode,
            "stdout": result.stdout.decode("utf-8", "replace"),
            "stderr": result.stderr.decode("utf-8", "replace")}


def zstring(data, start, end):
    assert 0 <= start <= end <= len(data), "String outside file"
    return data[start:end].split(b"\0", 1)[0].decode("utf-8", "replace")


def parse_macho(data):
    magic = data[:4]
    if magic in {b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}:
        wide = magic[-1] == 0xBF
        count = struct.unpack_from(">I", data, 4)[0]
        slices = []
        for index in range(count):
            pos = 8 + index * (32 if wide else 20)
            if wide:
                cpu, sub, offset, size, _, _ = struct.unpack_from(">IIQQII", data, pos)
            else:
                cpu, sub, offset, size, _ = struct.unpack_from(">IIIII", data, pos)
            assert offset + size <= len(data), "Fat slice outside file"
            slices.extend(parse_macho(data[offset:offset + size]))
        return slices
    endian = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">",
              b"\xce\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xce": ">"}[magic]
    wide = magic in {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"}
    cpu, subtype, kind, count, cmdbytes, flags = struct.unpack_from(endian + "6I", data, 4)
    subtype_base = subtype & 0xFFFFFF
    arch = ("arm64e" if subtype_base == 2 else "arm64") if cpu == 0x100000C else {
        12: "armv7s" if subtype_base == 11 else "armv7", 0x1000007: "x86_64",
    }.get(cpu, hex(cpu))
    pos = 32 if wide else 28
    cmdend = pos + cmdbytes
    assert cmdend <= len(data), "Load commands outside file"
    dependencies, ids, rpaths, sections, os_versions = [], [], [], [], []
    symtab = None
    encrypted = False
    for _ in range(count):
        cmd, size = struct.unpack_from(endian + "II", data, pos)
        assert size >= 8 and pos + size <= cmdend, "Invalid load command size"
        if cmd in LOAD_COMMANDS or cmd == 0xD:
            stringoff = struct.unpack_from(endian + "I", data, pos + 8)[0]
            value = zstring(data, pos + stringoff, pos + size)
            if cmd == 0xD:
                ids.append(value)
            else:
                dependencies.append({"name": value, "weak": cmd == 0x80000018})
        elif cmd == 0x8000001C:
            stringoff = struct.unpack_from(endian + "I", data, pos + 8)[0]
            rpaths.append(zstring(data, pos + stringoff, pos + size))
        elif cmd == 0x2:
            symtab = struct.unpack_from(endian + "IIII", data, pos + 8)
        elif cmd in {0x25, 0x32}:
            number = struct.unpack_from(endian + "I", data, pos + (12 if cmd == 0x32 else 8))[0]
            os_versions.append([number >> 16, (number >> 8) & 255, number & 255])
        elif cmd in {0x21, 0x2C}:
            encrypted = bool(struct.unpack_from(endian + "I", data, pos + 16)[0])
        elif cmd in {0x19, 0x1}:
            nsects = struct.unpack_from(endian + "I", data, pos + (64 if wide else 48))[0]
            sectionpos = pos + (72 if wide else 56)
            for index in range(nsects):
                start = sectionpos + index * (80 if wide else 68)
                assert start + (80 if wide else 68) <= pos + size
                namebytes = data[start:start + 16].split(b"\0", 1)[0]
                segbytes = data[start + 16:start + 32].split(b"\0", 1)[0]
                addr, length = struct.unpack_from(endian + ("QQ" if wide else "II"), data, start + 32)
                offset = struct.unpack_from(endian + "I", data, start + (48 if wide else 40))[0]
                sectionflags = struct.unpack_from(endian + "I", data, start + (64 if wide else 56))[0]
                sections.append({"name": namebytes.decode("ascii", "replace"),
                                 "segment": segbytes.decode("ascii", "replace"),
                                 "address": addr, "length": length, "offset": offset,
                                 "flags": sectionflags})
        pos += size
    imports, exports = [], []
    if symtab:
        symoff, nsyms, stroff, strsize = symtab
        entrysize = 16 if wide else 12
        assert symoff + nsyms * entrysize <= len(data) and stroff + strsize <= len(data)
        for index in range(nsyms):
            start = symoff + index * entrysize
            strindex, symtype, sect, desc = struct.unpack_from(endian + "IBBH", data, start)
            if not strindex or strindex >= strsize or symtype & 0xE0:
                continue
            symbol = zstring(data, stroff + strindex, stroff + strsize)
            if not symtype & 1:
                continue
            if symtype & 0x0E == 0:
                ordinal = desc >> 8
                library = dependencies[ordinal - 1]["name"] if 1 <= ordinal <= len(dependencies) else {
                    0: "SELF_OR_FLAT", 254: "DYNAMIC_LOOKUP", 255: "MAIN_EXECUTABLE",
                }.get(ordinal, "UNKNOWN_ORDINAL_" + str(ordinal))
                imports.append({"symbol": symbol, "library": library,
                                "weak": bool(desc & 0x40), "ordinal": ordinal})
            else:
                exports.append(symbol)
    literals = []
    for section in sections:
        offset, length = section["offset"], section["length"]
        if section["flags"] & 255 == 2 and offset + length <= len(data):
            for token in data[offset:offset + length].split(b"\0"):
                if token:
                    literals.append(token.decode("utf-8", "replace"))
        if section["name"] == "__cfstring" and wide and offset + length <= len(data):
            for start in range(offset, offset + length - 31, 32):
                pointer = struct.unpack_from(endian + "Q", data, start + 16)[0]
                for target in sections:
                    if target["address"] <= pointer < target["address"] + target["length"]:
                        location = target["offset"] + pointer - target["address"]
                        if location < len(data):
                            literals.append(zstring(data, location, min(len(data), location + 16384)))
                        break
    return [{"architecture": arch, "cpu_subtype_raw": subtype, "filetype": kind,
             "flags": flags, "dependencies": dependencies, "dylib_ids": ids,
             "rpaths": rpaths, "minimum_ios": os_versions, "encrypted": encrypted,
             "sections": sections, "imports": imports, "exports": exports,
             "literals": sorted(set(literals)),
             "initializer_slots": sum(s["length"] // (8 if wide else 4) for s in sections
                                      if s["flags"] & 255 == 9)}]


def sensitive(name, bundles):
    marks = []
    if re.search(r"淘宝|闲鱼|支付宝|高德|饿了么|飞猪|菜鸟|淘票票|京东|银行|建行|雪球|拍拍贷|平安|口袋记账|随手记", name):
        marks.append("模块名命中高敏/金融家族，保守禁止注入")
    for bundle in bundles:
        if re.search(r"(?i)^(com\.(taobao|alipay|alimama|autonavi|ucweb|youku|cainiao|360buy|jdcar|pingan|citicbank|boc|cebbank|ppdai|cmb|ccb|icbc|bank|xueqiu)|cn\.damai|me\.ele\.)", bundle):
            marks.append("目标Bundle ID命中高敏家族：" + bundle)
    return marks


def inspect_module(spec, args, runtime):
    path = args.input / "dylibs" / (spec["module"] + ".dylib")
    output = args.output / "modules" / spec["module"]
    output.mkdir(parents=True, exist_ok=True)
    raw = path.read_bytes()
    current_hash = hashlib.sha256(raw).hexdigest()
    assert current_hash == spec["sha256"], "Original file changed: " + path.name
    slices = parse_macho(raw)
    selected_arch = "arm64" if any(sl["architecture"] == "arm64" for sl in slices) else "arm64e"
    applicable_slices = [sl for sl in slices if sl["architecture"] == selected_arch]
    tools = {
        "otool-loads": run("otool", "-arch", "all", "-l", str(path)),
        "undefined-symbols": run("nm", "-arch", "all", "-u", str(path)),
        "strings": run("strings", "-a", str(path)),
        "signature-display": run("codesign", "-dvv", str(path)),
        "objc-metadata": run("xcrun", "llvm-objdump", "--macho", "--objc-meta-data", "--arch=" + selected_arch, str(path)),
        "disassembly": run("otool", "-arch", selected_arch, "-tvV", str(path)),
    }
    for name, result in tools.items():
        (output / (name + ".txt")).write_text(result["stdout"] + "\nSTDERR:\n" + result["stderr"])
    all_symbols = {item["symbol"] for sl in slices for item in sl["imports"]}
    literals = sorted({text for sl in slices for text in sl["literals"]})
    load_names = {d["name"] for sl in slices for d in sl["dependencies"]}
    paths = [x for x in literals if re.search(r"/var/jb|\.jbroot|/var/mobile/|/Library/(?:Preferences|Application Support|PreferenceBundles|MobileSubstrate)|/usr/lib/.*(?:substrate|ellekit)", x)]
    resources = [x for x in literals if re.search(r"(?i)(?:[\w.-]+\.(?:bundle|plist|json|png|jpg|db|sqlite)\b)", x)
                 and not x.startswith(("/System/Library/", "http://", "https://"))]
    system_resource_literals = [x for x in literals if x.startswith("/System/Library/")]
    detection = [x for x in literals if re.search(r"(?i)jailbreak|jailbroken|isDebugged|isPirated|rootHide|越狱|反调试", x)]
    entitlement = [x for x in literals if re.search(r"(?i)isVip|isPro\b|isPremium|isSubscribed|subscriptionStatus|unlockPro|会员|破解", x)]
    dynamic = sorted(all_symbols & {"_dlopen", "_dlsym", "_NSClassFromString"})
    disassembly = tools["disassembly"]["stdout"]
    class_literals = sorted(set(re.findall(r'literal pool for: "([^"\n]+)"', disassembly)))
    selector_refs = sorted(set(re.findall(r'Objc selector ref: (\S+)', disassembly)))
    assembly_calls = sorted(set(re.findall(r'symbol stub for: (\S+)', disassembly)))
    registration_symbols = sorted(all_symbols & {
        "_MSHookMessageEx", "_MSHookFunction", "_MSHookClassPair", "_EKHookFunction",
        "_LHHookFunctions", "_method_setImplementation", "_method_exchangeImplementations",
        "_class_addMethod", "_rebind_symbols", "_objc_setHook_getClass",
    })
    prefs = sorted(x for x in all_symbols if x.startswith("_CFPreferences") or x == "_OBJC_CLASS_$_NSUserDefaults")
    process_symbols = sorted(all_symbols & {"_system", "_posix_spawn", "_execve", "_fork", "_popen"})
    network = sorted(all_symbols & {"_OBJC_CLASS_$_NSURLSession", "_OBJC_CLASS_$_NSURLConnection", "_connect", "_send", "_recv"})
    urls = [x for x in literals if re.search(r"https?://", x)]
    extra_deps, missing_runtime_symbols, runtime_imports = [], [], []
    for sl in slices:
        for dep in sl["dependencies"]:
            name = dep["name"]
            if Path(name).name.lower() in RUNTIME_NAMES:
                continue
            if not name.startswith(("/usr/lib/", "/System/Library/")):
                if sl in applicable_slices:
                    extra_deps.append({"architecture": sl["architecture"], **dep})
        for imported in sl["imports"]:
            if Path(imported["library"]).name.lower() in RUNTIME_NAMES:
                record = {"architecture": sl["architecture"], **imported}
                runtime_imports.append(record)
                if sl in applicable_slices and "\ufffd" not in imported["symbol"] and imported["symbol"] not in runtime.get(sl["architecture"], set()) and not imported["weak"]:
                    missing_runtime_symbols.append(record)
    hooks = sorted(x for x in all_symbols if re.match(r"_(?:MSHook|MSFind|MSGet|LHHook|EKHook|Dobby|rebind_symbols)", x))
    invalid_sections = [s["name"] for sl in slices for s in sl["sections"] if "\ufffd" in s["name"]]
    no_arm64 = not any(sl["architecture"] == "arm64" for sl in slices)
    minos_too_high = any(tuple(v) > (16, 3, 1) for sl in applicable_slices for v in sl["minimum_ios"])
    flags = []
    if extra_deps:
        flags.append("存在TrollFools默认Substrate重定向之外的依赖")
    if missing_runtime_symbols:
        flags.append("导入符号未在相同CPU slice的内置Hook库导出表中找到")
    if no_arm64:
        flags.append("没有arm64 slice，目标进程arm64e ABI兼容性未确认")
    if minos_too_high:
        flags.append("声明最低系统版本高于本机iOS 16.3.1")
    if invalid_sections:
        flags.append("存在非ASCII/不可解码段名，疑似混淆，静态透明度不足")
    if any(sl["encrypted"] or sl["filetype"] != 6 for sl in slices):
        flags.append("加密标记或非MH_DYLIB slice需复核")
    if invalid_sections or any(sl["encrypted"] or sl["filetype"] != 6 for sl in slices):
        verdict = "needs_binary_review"
    elif extra_deps or missing_runtime_symbols:
        verdict = "needs_dependency_review"
    elif no_arm64 or minos_too_high:
        verdict = "needs_architecture_review"
    elif runtime_imports or any(Path(x).name.lower() in RUNTIME_NAMES for x in load_names):
        verdict = "bundled_runtime_candidate"
    else:
        verdict = "system_linked_candidate"
    bundles = spec["filter"].get("Bundles", [])
    executables = spec["filter"].get("Executables", [])
    if any(b in {"com.apple.springboard", "com.apple.backboardd"} for b in bundles):
        verdict = "system_process_target"
        flags.append("Filter目标为系统进程，普通App注入不等价")
    sensitive_marks = sensitive(spec["module"], bundles)
    if any("Fliggy" in x for x in class_literals):
        sensitive_marks.append("代码类名包含Fliggy（飞猪）线索，保守不注入")
    functional_notes = []
    if bundles == ["com.apple.springboard"] and any("Fliggy" in x for x in class_literals):
        functional_notes.append("Filter声明SpringBoard，但反汇编向FliggyCacheSplashScreenPageController注册Hook；目标信息不一致")
    if spec["module"] == "微信广告" and not registration_symbols:
        verdict = "needs_functional_review"
        flags.append("导入表及可见初始化代码未见Hook/方法替换注册；不能认定去广告代码会被调用")
        functional_notes.append("可见构造函数包含NSLog、NSDateFormatter和compare:，未见注册调用；需原作者源码或运行证据确认")
    name_nonad = bool(re.search(r"(?i)crack|破解|屏蔽越狱|VIP", spec["module"]))
    if sensitive_marks:
        gate = "sensitive_target_no_injection"
    elif detection or name_nonad or entitlement:
        gate = "non_ad_or_detection_review"
    elif paths or resources or prefs or process_symbols or "_dlopen" in dynamic:
        gate = "settings_resources_review"
    elif not bundles and not executables:
        gate = "no_target_mapping"
    else:
        gate = "no_additional_static_flag"
    overlap = [x for x in args.apps if x.get("CFBundleIdentifier") in bundles or x.get("CFBundleExecutable") in executables]
    result = {
        "module": spec["module"], "sha256": current_hash,
        "hash_unchanged": current_hash == spec["sha256"],
        "filter": spec["filter"], "plist_present": spec["plist_present"],
        "architectures": [sl["architecture"] for sl in slices],
        "slice_details": [{k: v for k, v in sl.items() if k not in {"literals", "exports"}} for sl in slices],
        "technical_verdict": verdict, "technical_label": LABELS[verdict],
        "usage_gate": gate, "usage_label": GATES[gate], "technical_flags": flags,
        "runtime_imports": runtime_imports, "missing_runtime_exports": missing_runtime_symbols,
        "additional_dependencies": extra_deps, "hook_symbols": hooks,
        "runtime_path_literals": paths, "resource_literals": resources,
        "system_resource_literals": system_resource_literals,
        "preferences_symbols": prefs, "dynamic_lookup_symbols": dynamic,
        "detection_literals": detection, "entitlement_literals": entitlement,
        "non_ad_name_flag": name_nonad, "sensitive_target_evidence": sensitive_marks,
        "process_execution_symbols": process_symbols, "network_symbols": network,
        "url_literals": urls, "installed_target_apps": overlap,
        "initializer_slots": sum(sl["initializer_slots"] for sl in slices),
        "registration_symbols": registration_symbols,
        "referenced_class_literals": class_literals,
        "referenced_selectors": selector_refs,
        "referenced_calls": assembly_calls,
        "functional_review_notes": functional_notes,
        "selected_architecture_for_target": selected_arch,
        "legacy_slices_not_targeted": [sl["architecture"] for sl in slices if sl["architecture"] not in {"arm64", "arm64e"}],
        "objc_metadata_lines": tools["objc-metadata"]["stdout"].count("\n"),
        "disassembly_lines": tools["disassembly"]["stdout"].count("\n"),
        "plus_load_literal": "load" in literals,
        "tools": {name: {"returncode": r["returncode"], "stderr": r["stderr"]} for name, r in tools.items()},
        "runtime_verified": False, "source_code_available": False,
        "evidence_level": "静态事实与字符串线索；字符串不证明已执行行为",
    }
    (output / "audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--apps", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.apps = json.loads(args.apps.read_text())
    specs = json.loads((args.input / "manifest.json").read_text())["modules"]
    actual = {x.stem for x in (args.input / "dylibs").glob("*.dylib")}
    assert len(specs) == 209 and actual == {x["module"] for x in specs}
    runtime_slices = parse_macho(args.runtime.read_bytes())
    runtime = {sl["architecture"]: set(sl["exports"]) for sl in runtime_slices}
    (args.output / "runtime-audit.json").write_text(json.dumps({
        "sha256": sha(args.runtime), "slices": runtime_slices,
        "source_reference": "公开v4.3-240；本机4.3/242无完全一致公开tag，不假定二者代码完全相同",
    }, ensure_ascii=False, indent=2) + "\n")
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda s: inspect_module(s, args, runtime), specs))
    # Confirm every original again after all inspection tools have finished.
    assert all(sha(args.input / "dylibs" / (x["module"] + ".dylib")) == x["sha256"] for x in results)
    bundle_modules = defaultdict(list)
    for record in results:
        for bundle in record["filter"].get("Bundles", []):
            bundle_modules[bundle].append(record["module"])
    summary = {
        "files": len(results), "hashes_unchanged": len(results),
        "technical_counts": dict(Counter(x["technical_verdict"] for x in results)),
        "usage_gate_counts": dict(Counter(x["usage_gate"] for x in results)),
        "runtime_verified": 0,
        "matching_installed_targets": sum(bool(x["installed_target_apps"]) for x in results),
        "architecture_slices_checked": sum(len(x["slice_details"]) for x in results),
        "low_extra_risk_static_candidates": sum(x["technical_verdict"] in {"system_linked_candidate", "bundled_runtime_candidate"} and x["usage_gate"] == "no_additional_static_flag" for x in results),
        "multiple_module_bundle_ids": {k: v for k, v in bundle_modules.items() if len(v) > 1},
    }
    (args.output / "audit.json").write_text(json.dumps({"summary": summary, "modules": results}, ensure_ascii=False, indent=2) + "\n")
    with (args.output / "audit.csv").open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(["模块", "技术结论", "使用边界", "目标Bundle ID/进程", "CPU", "本机目标版本", "问题", "证据"])
        for x in results:
            targets = x["filter"].get("Bundles", []) + x["filter"].get("Executables", [])
            versions = [str(a.get("CFBundleIdentifier")) + " " + str(a.get("CFBundleShortVersionString")) for a in x["installed_target_apps"]]
            writer.writerow([x["module"], x["technical_label"], x["usage_label"], "; ".join(targets), ",".join(x["architectures"]), "; ".join(versions) or "未匹配", "; ".join(x["technical_flags"]), "modules/" + x["module"] + "/audit.json"])
    lines = ["# 209个dylib的TrollFools逐项静态审计", "",
             "## 结论边界", "",
             "- 全部209个原文件完成逐CPU slice检查；检查前后SHA-256一致，未修改。",
             "- 本机iPhone13,1，iOS 16.3.1，TrollFools 4.3/242；只读获取78个App的元数据。",
             "- 没有安装、注入、启动App、改隐根开关或执行插件代码；实机验证数为0。",
             "- 没有原作者源码；没有对所有机器码逐函数反编译。此报告不是源码审计、安全认证或效果保证。",
             "- 内置Substrate同架构导出表与插件导入表逐项比对。导出匹配只证明符号存在，不保证Hook行为兼容。",
             "- 每个文件保留反汇编和Objective-C元数据，提取可见类名、selector及调用线索；不能据此宣称逐函数完整还原。",
             "- 技术结论以本机64位目标为前提，存在arm64时按arm64评估，否则arm64e待复核；旧32位slice单列，不把本机不会加载的32位依赖当作阻塞。",
             "- 公开v4.3-240源码显示工具会按库名后缀重定向Substrate依赖；本机242的同名字符串和内置库支持此能力存在，但未实际执行工具路径。",
             "- /var/jb或.jbroot仅作为额外RPATH时不自动判定失败；在运行时字符串或非Substrate依赖中出现则单独提示。",
             "- isJailbroken、会员、网络、路径等字符串/符号只作为线索，不证明插件绕过检测、破解或外发数据。",
             "- 技术结论与使用边界分开；高敏App不注入，存在非广告线索的候选不直接推荐使用。", "",
             "## 技术结论统计", ""]
    for key, count in summary["technical_counts"].items():
        lines.append("- " + LABELS[key] + "：" + str(count))
    lines += ["", "## 使用边界统计", ""]
    for key, count in summary["usage_gate_counts"].items():
        lines.append("- " + GATES[key] + "：" + str(count))
    lines += ["", "## 全部模块", "", "| 模块 | 技术结论 | 使用边界 | 目标/版本 |", "|---|---|---|---|"]
    for x in results:
        versions = "; ".join(str(a.get("CFBundleIdentifier")) + " " + str(a.get("CFBundleShortVersionString")) for a in x["installed_target_apps"]) or "本机未匹配"
        lines.append("| " + x["module"] + " | " + x["technical_label"] + " | " + x["usage_label"] + " | " + versions + " |")
    lines += ["", "## 逐模块证据与说明", ""]
    for x in results:
        lines += ["### " + x["module"], "", "- 技术结论：" + x["technical_label"], "- 使用边界：" + x["usage_label"], "- 架构：" + ", ".join(x["architectures"]), "- 目标Filter：" + json.dumps(x["filter"], ensure_ascii=False), "- 问题：" + ("；".join(x["technical_flags"]) or "未见额外静态加载阻塞；运行未验证")]
        for label, field in [("额外依赖", "additional_dependencies"), ("未匹配运行库符号", "missing_runtime_exports"), ("越狱/外部路径线索", "runtime_path_literals"), ("资源线索", "resource_literals"), ("设置符号", "preferences_symbols"), ("动态查找符号", "dynamic_lookup_symbols"), ("检测相关字符串", "detection_literals"), ("会员相关字符串", "entitlement_literals"), ("高敏依据", "sensitive_target_evidence"), ("功能复核", "functional_review_notes"), ("可见类名字面量", "referenced_class_literals"), ("注册/替换导入符号", "registration_symbols")]:
            if x[field]:
                lines.append("- " + label + "：" + json.dumps(x[field], ensure_ascii=False))
        lines += ["- 初始化函数槽数：" + str(x["initializer_slots"]) + "；不等于已测启动耗时。", "- 证据：modules/" + x["module"] + "/audit.json 及同目录工具输出。", ""]
    (args.output / "report.md").write_text("\n".join(lines) + "\n")
    table = []
    for x in results:
        details = json.dumps({k: v for k, v in x.items() if k not in {"slice_details", "tools"}}, ensure_ascii=False, indent=2)
        table.append("<tr><td>" + html.escape(x["module"]) + "</td><td>" + html.escape(x["technical_label"]) + "</td><td>" + html.escape(x["usage_label"]) + "</td><td><details><summary>逐项证据</summary><pre>" + html.escape(details) + "</pre></details></td></tr>")
    document = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>209个dylib静态审计</title><style>body{font:15px system-ui;margin:32px;background:#fafafa}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ddd;padding:10px;text-align:left}pre{white-space:pre-wrap;max-width:800px}input{padding:10px;width:400px}</style><h1>209个dylib：TrollFools静态检查</h1><p>原文件209/209未修改；实机运行验证0/209。不是源码审计、安全认证或去广告效果保证。</p><p>技术候选与使用边界分别判断；高敏App不注入。</p><input id="q" placeholder="搜索模块、结论或目标"><table><thead><tr><th>模块</th><th>技术结论</th><th>使用边界</th><th>证据</th></tr></thead><tbody>' + ''.join(table) + '</tbody></table><script>document.getElementById("q").addEventListener("input",function(){const q=this.value.toLowerCase();document.querySelectorAll("tbody tr").forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q));});</script></html>'
    (args.output / "report.html").write_text(document)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
