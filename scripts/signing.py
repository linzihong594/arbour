"""Prepare a local signed build using user-supplied Apple signing assets."""

from datetime import datetime, timezone
from fnmatch import fnmatchcase
from pathlib import Path
import plistlib
import subprocess


def prepare(identity: str | None, profile: Path | None, bundle_id: str, output: Path) -> dict | None:
    if not identity and not profile:
        return None
    if not identity or identity == "-" or not profile:
        raise ValueError("正式签名需要同时指定 --identity 和 --profile；不能使用 ad-hoc 身份。")
    payload = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(profile)]))
    expires = payload.get("ExpirationDate")
    if not expires or expires.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("Provisioning profile 已过期或缺少有效期。")
    allowed = payload.get("Entitlements", {})
    profile_id = allowed.get("com.apple.application-identifier")
    prefixes = payload.get("ApplicationIdentifierPrefix", [])
    teams = payload.get("TeamIdentifier", [])
    if not profile_id or not prefixes or not teams:
        raise ValueError("请选择包含 macOS App ID 和 TeamIdentifier 的描述文件。")
    app_id = f"{prefixes[0]}.{bundle_id}"
    if not fnmatchcase(app_id, profile_id):
        raise ValueError("描述文件与 Bundle ID 不匹配；可用 --bundle-id 指定已注册的标识。")
    entitlements = {
        "com.apple.application-identifier": app_id,
        "com.apple.developer.team-identifier": teams[0],
        # Required for Location Services when hardened runtime or sandbox is enabled.
        "com.apple.security.personal-information.location": True,
    }
    groups = allowed.get("keychain-access-groups", [])
    if any(fnmatchcase(app_id, group) for group in groups):
        entitlements["keychain-access-groups"] = [app_id]
    # Otherwise the application identifier supplies the default private access group.
    output.mkdir(parents=True, exist_ok=True)
    entitlement_file = output / "MacDiary.entitlements"
    entitlement_file.write_bytes(plistlib.dumps(entitlements))
    return {"identity": identity, "profile": profile.resolve(),
            "entitlements": entitlement_file, "team": teams[0]}


def sign(app: Path, assets: dict | None) -> None:
    if assets:
        (app / "Contents/embedded.provisionprofile").write_bytes(assets["profile"].read_bytes())
        subprocess.run(["codesign", "--force", "--sign", assets["identity"],
                        "--options", "runtime", "--timestamp=none",
                        "--entitlements", str(assets["entitlements"]), str(app)], check=True)
        details = subprocess.run(["codesign", "-dv", str(app)], text=True, capture_output=True, check=True)
        if f"TeamIdentifier={assets['team']}" not in details.stderr.splitlines():
            raise ValueError("签名证书的 TeamIdentifier 与描述文件不同。")
    else:
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
