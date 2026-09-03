from __future__ import annotations

import re
import sys
from pathlib import Path


PACKAGE = "com.xiaomi.smarthome.tv.global4"
SOURCE_VERSION = "2.8.0.2"
PATCH_VERSION = "2.8.0.2-cn1"


def read(path: Path) -> str:
    if not path.is_file():
        raise RuntimeError(f"missing expected file: {path}")
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="")


def replace_exact(path: Path, old: str, new: str, count: int = 1) -> None:
    text = read(path)
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(
            f"{path}: expected {count} occurrence(s), found {actual}: {old!r}"
        )
    write(path, text.replace(old, new))


def patch_app(path: Path) -> None:
    text = read(path)
    match = re.search(
        r"(?ms)^\.method private initSmartHomeClient\(\)V$.*?^\.end method$",
        text,
    )
    if not match:
        raise RuntimeError("initSmartHomeClient() was not found")

    method = match.group(0)
    old = '    const-string v0, "DE"\n\n    const-string v1, "CN"'
    new = '    const-string v0, "CN"\n\n    const-string v1, "CN"'
    if method.count(old) != 1:
        raise RuntimeError("unexpected initSmartHomeClient() server-tag layout")

    patched = method.replace(old, new)
    write(path, text[: match.start()] + patched + text[match.end() :])


def patch_server_list(path: Path) -> None:
    text = read(path)
    marker = '    const-string v2, "中国大陆"'
    if marker in text:
        return

    anchor = ".method private initData()V\n    .locals 5\n"
    if text.count(anchor) != 1:
        raise RuntimeError("unexpected SelectServerActivity.initData() layout")

    block = """

    iget-object v0, p0, Lcom/xiaomi/smarthome/tv/ui/SelectServerActivity;->mDatas:Ljava/util/ArrayList;

    new-instance v1, Lcom/xiaomi/smarthome/tv/ui/view/bean/CountryBean;

    const-string v2, "中国大陆"

    const-string v3, "CN"

    invoke-direct {v1, v2, v3, v3}, Lcom/xiaomi/smarthome/tv/ui/view/bean/CountryBean;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V

    invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
"""
    write(path, text.replace(anchor, anchor + block, 1))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch.py <apktool-decoded-directory>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    build_config = root / "smali_classes3/com/xiaomi/smarthome/tv/BuildConfig.smali"
    build_utils = root / "smali_classes3/com/xiaomi/smarthome/tv/utils/BuildConfigUtils.smali"
    app = root / "smali_classes3/com/xiaomi/smarthome/tv/App.smali"
    server_list = root / "smali_classes3/com/xiaomi/smarthome/tv/ui/SelectServerActivity.smali"
    manifest = root / "AndroidManifest.xml"
    apktool_yml = root / "apktool.yml"

    if f'APPLICATION_ID:Ljava/lang/String; = "{PACKAGE}"' not in read(build_config):
        raise RuntimeError(f"unexpected package; expected {PACKAGE}")
    if f'VERSION_NAME:Ljava/lang/String; = "{SOURCE_VERSION}"' not in read(build_config):
        raise RuntimeError(f"unexpected source version; expected {SOURCE_VERSION}")

    patch_app(app)
    replace_exact(
        build_config,
        'SERVER_TAG:Ljava/lang/String; = "DE"',
        'SERVER_TAG:Ljava/lang/String; = "CN"',
    )
    replace_exact(
        build_config,
        f'VERSION_NAME:Ljava/lang/String; = "{SOURCE_VERSION}"',
        f'VERSION_NAME:Ljava/lang/String; = "{PATCH_VERSION}"',
    )
    replace_exact(build_utils, f'const-string v2, "{SOURCE_VERSION}"', f'const-string v2, "{PATCH_VERSION}"')
    replace_exact(build_utils, f'const-string v0, "{SOURCE_VERSION}"', f'const-string v0, "{PATCH_VERSION}"')
    patch_server_list(server_list)

    manifest_text = read(manifest)
    for attribute in ("android:requiredSplitTypes", "android:splitTypes"):
        manifest_text, replaced = re.subn(rf' {attribute}="[^"]*"', "", manifest_text)
        if replaced != 1:
            raise RuntimeError(f"expected one {attribute} manifest attribute")
    write(manifest, manifest_text)

    replace_exact(
        apktool_yml,
        f"  versionName: {SOURCE_VERSION}",
        f"  versionName: {PATCH_VERSION}",
    )

    marker_file = root / "assets/CN_PATCH.txt"
    marker_file.parent.mkdir(parents=True, exist_ok=True)
    write(
        marker_file,
        f"Mi Home TV global4 {PATCH_VERSION}\n"
        "Default server: CN\n"
        "Mainland mode: enabled by existing server-tag comparison\n"
        "Third-party QR login: retained\n",
    )

    print(f"patched {PACKAGE} {SOURCE_VERSION} -> {PATCH_VERSION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
