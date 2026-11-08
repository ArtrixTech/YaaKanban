# Release signing team mismatch: cause and repair

## Summary
YaaKanban 0.2.1 went out signed by the wrong Apple team, so every 0.1.x/0.2.0 install refused the update ("下载的更新不是同一开发者签名的，未安装。"). This records how to spot it and how to repair a published release without changing its version.

## Content

**Rule.** The updater (`Updater.verify`) installs an update only if its `TeamIdentifier` equals the running app's. The release team is 5KZD8GBF7G; see AGENTS.md › Release signing.

**Why it slipped.** The keychain holds two Apple Development identities from different teams:

| Cert | Team (OU) | Org (O) | Use |
|---|---|---|---|
| `Apple Development: artrix@artrix.tech (7XZ34D8PVC)` | 5KZD8GBF7G | 楚越 龚 (personal) | releases |
| `Apple Development: 楚越 龚 (4D5TXM7349)` | 5JF32B7C33 | DAYOU INC | local `make install` |

`scripts/bundle.sh` used to sign with the first identity `security find-identity` lists; that was the cause. Since 2026-11-06 it reads each identity's certificate `OU` and picks the one whose team is `YAAK_RELEASE_TEAM` (default 5KZD8GBF7G), signing by SHA-1 so a renewed cert cannot be confused with its predecessor; `YAAK_SIGN_IDENTITY` still overrides. The suffix in the cert name (4D5TXM7349, 7XZ34D8PVC) is the person's ID, not the team. The 0.2.1 devlog note assumed 0.2.0 used team 5JF3; it used 5KZD.

**Check a published release.**

```sh
gh release download vX.Y.Z --repo ArtrixTech/YaaKanban -p '*.zip'
ditto -x -k YaaKanban-X.Y.Z.zip . && codesign -dv YaaKanban.app 2>&1 | grep TeamIdentifier
```

Team of a keychain cert: `security find-certificate -a -Z -p | awk -v h=<SHA1> '/SHA-1 hash:/{p=($3==h)} p && /BEGIN/,/END/' | openssl x509 -noout -subject` (the `OU=` field).

**Repair in place (done for 0.2.1 on 2026-11-04).** Re-signing keeps the build's bytes, including the Aptabase key injected into Info.plist at build time.

1. Download the release zip, unpack it, copy `YaaKanban.app`.
2. `codesign --force --sign <release SHA-1>` on `Contents/Helpers/yaak`, then on the app (the order `bundle.sh` uses).
3. `codesign --verify --deep --strict`, confirm `TeamIdentifier`, and confirm every non-binary file is unchanged.
4. `ditto -c -k --keepParent` the app to `YaaKanban-X.Y.Z.zip`; `scripts/dmg.sh <app> YaaKanban-X.Y.Z.dmg`.
5. `gh release upload vX.Y.Z <zip> <dmg> --clobber`, then download again and `cmp` against the local files.

Pitfalls:
- `--clobber` deletes each asset before uploading it. A GitHub 5xx in between leaves the release without that asset; list the assets (`gh api repos/ArtrixTech/YaaKanban/releases/tags/vX.Y.Z`) and upload again.
- Clients need no action: a cached copy that fails verification is downloaded again on the next check ("立即检查" or the 6 h timer).
- Anyone who installed the wrongly signed DMG now runs the other team's build and rejects later releases. They must install the DMG manually once.
