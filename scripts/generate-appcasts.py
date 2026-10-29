#!/usr/bin/env python3
"""使用锁定版本的 Sparkle 工具，为两个架构的最终 DMG 生成并验证更新清单。"""

import argparse
import base64
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--tag", required=True)
parser.add_argument("--repository", required=True)
parser.add_argument("--build-number", required=True)
parser.add_argument("--dist", type=Path, default=Path("dist"))
args = parser.parse_args()
if not re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?", args.tag):
    parser.error("版本标签必须是 vX.Y.Z 或 vX.Y.Z-beta.1 / vX.Y.Z-rc.1")
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository):
    parser.error("仓库名称必须是 owner/repository")
if not args.build_number.isdecimal() or int(args.build_number) <= 0:
    parser.error("构建号必须是递增的正整数")

public_key = os.environ.get("SPARKLE_PUBLIC_ED_KEY", "").strip()
private_key = os.environ.pop("SPARKLE_PRIVATE_ED_KEY", "").strip()
# 在调用官方工具前验证格式；其解析错误可能回显无效输入，不能把私钥写进日志。
for name, value, lengths in (
    ("SPARKLE_PUBLIC_ED_KEY", public_key, (32,)),
    ("SPARKLE_PRIVATE_ED_KEY", private_key, (32, 96)),
):
    if not re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", value) or len(value) % 4:
        parser.error(f"{name} 必须是 Sparkle generate_keys 导出的 base64 密钥")
    if len(base64.b64decode(value)) not in lengths:
        parser.error(f"{name} 长度无效")

root = Path(__file__).resolve().parent.parent
tool_directory = root / ".build/artifacts/sparkle/Sparkle/bin"
dist = args.dist.resolve()
namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
download_prefix = f"https://github.com/{args.repository}/releases/download/{args.tag}/"
release_url = f"https://github.com/{args.repository}/releases/tag/{args.tag}"
version = args.tag[1:].split("-", 1)[0]


def sparkle(command):
    # 私钥只经 stdin 传入，不在参数、子进程环境或日志中出现。
    result = subprocess.run(
        command, input=private_key + "\n", text=True, capture_output=True,
    )
    if result.returncode:
        parser.error(f"Sparkle {Path(command[0]).name} 失败；检查签名密钥、应用包与更新清单配置")


for platform in ("AppleSilicon", "Intel"):
    archive = dist / f"CodexQuota-macOS-{platform}.dmg"
    if not archive.is_file() or archive.stat().st_size == 0:
        parser.error(f"缺少最终发布包：{archive.name}")
    feed = dist / f"appcast-{platform}.xml"
    # 每个目录只包含一个架构，避免同一构建号被合并或选中错误的安装包。
    with tempfile.TemporaryDirectory(prefix=f"appcast-{platform}-", dir=root / ".build") as staging:
        shutil.copy2(archive, Path(staging) / archive.name)
        generated_feed = Path(staging) / feed.name
        command = [
            str(tool_directory / "generate_appcast"), "--ed-key-file", "-",
            "--disable-signing-warning", "--maximum-deltas", "0",
            "--download-url-prefix", download_prefix,
            "--link", release_url, "-o", str(generated_feed),
        ]
        if "-" in args.tag:
            command += ["--channel", "beta"]
        sparkle(command + [staging])
        shutil.copy2(generated_feed, feed)

    items = ET.parse(feed).findall("./channel/item")
    if len(items) != 1:
        parser.error(f"{feed.name} 应仅包含当前版本")
    item = items[0]
    enclosure = item.find("enclosure")
    signature = None if enclosure is None else enclosure.get(f"{{{namespace['sparkle']}}}edSignature")
    # generate_appcast 只有在安装包公钥与提供的私钥匹配时才为 enclosure 签名。
    if not signature:
        parser.error(f"{archive.name} 未获得签名；检查应用内 SUPublicEDKey 与发布私钥是否匹配")
    if enclosure.get("url") != download_prefix + archive.name or enclosure.get("length") != str(archive.stat().st_size):
        parser.error(f"{feed.name} 的下载地址或大小与最终 DMG 不一致")
    if item.findtext("sparkle:version", namespaces=namespace) != args.build_number:
        parser.error(f"{feed.name} 的构建号与发行构建不一致")
    if item.findtext("sparkle:shortVersionString", namespaces=namespace) != version:
        parser.error(f"{feed.name} 的显示版本与标签不一致")
    if item.findtext("sparkle:minimumSystemVersion", namespaces=namespace) not in ("13.0", "13.0.0"):
        parser.error(f"{feed.name} 的最低 macOS 版本应为 13.0")
    if platform == "AppleSilicon" and item.findtext("sparkle:hardwareRequirements", namespaces=namespace) != "arm64":
        parser.error(f"{feed.name} 缺少 Apple Silicon 架构限制")
    sparkle([str(tool_directory / "sign_update"), "--ed-key-file", "-", "--verify", str(archive), signature])
    sparkle([str(tool_directory / "sign_update"), "--ed-key-file", "-", "--verify", str(feed)])
    print(f"已签名并验证 {archive.name} 与 {feed.name}")
