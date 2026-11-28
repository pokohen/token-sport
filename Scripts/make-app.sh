#!/bin/bash
# Token Sports.app 번들을 만든다. 번들로 실행해야 알림이 나온다.
# 사용법: Scripts/make-app.sh  →  build/Token Sports.app
# (실행 파일 이름과 번들 식별자는 예전 그대로 TokenBaseball이다. 바꾸면 알림 권한과 저장 폴더가 끊긴다.)
set -euo pipefail
cd "$(dirname "$0")/.."

# 배포용으로 만들 때 쓰는 값 (Scripts/release.sh가 넘긴다). 평소에는 비어 있다.
#   TB_ARCHS     "arm64 x86_64"처럼 주면 두 종류의 맥에서 모두 도는 앱을 만든다
#   TB_VERSION   앱 버전 (예: 0.2.0)
#   TB_SIGN      서명할 인증서 이름 (Developer ID Application: …). 없으면 내 맥에서만 쓰는 임시 서명
#   TB_LANGUAGES 한국어 말고 넣을 화면 언어 (예: "en ja"). 번역이 끝나기 전에는 비워 둔다 (배포 앱은 한국어만)
ARCH_FLAGS=()
for arch in ${TB_ARCHS:-}; do ARCH_FLAGS+=(--arch "$arch"); done
VERSION="${TB_VERSION:-0.1.0}"

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/TokenBaseball"
APP="build/Token Sports.app"
# 이름을 바꾸기 전에 만든 번들이 남아 있으면 지운다.
rm -rf "build/Token Baseball.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TokenBaseball"
# 앱 아이콘 (Scripts/make-icon.sh로 만들어 저장소에 넣어 둔 파일).
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 화면 문구 번역. 한국어가 기본이고 (코드에 쓴 한국어 문구가 그대로 열쇠다), 다른 언어는 Resources/<언어>.lproj에 둔다.
# 맥의 언어가 넣은 언어 가운데 없으면 한국어로 나온다.
mkdir -p "$APP/Contents/Resources/ko.lproj"
LOCALIZATIONS="<string>ko</string>"
for lang in ${TB_LANGUAGES:-}; do
    cp -R "Resources/$lang.lproj" "$APP/Contents/Resources/"
    LOCALIZATIONS="$LOCALIZATIONS<string>$lang</string>"
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Token Sports</string>
    <key>CFBundleDisplayName</key><string>Token Sports</string>
    <key>CFBundleIdentifier</key><string>app.tokenbaseball.TokenBaseball</string>
    <key>CFBundleExecutable</key><string>TokenBaseball</string>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>CFBundleLocalizations</key><array>LOCALIZATIONS</array>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>KBO 및 각 구단과 무관한 비공식 팬 프로젝트</string>
</dict>
</plist>
PLIST
sed -i '' "s#LOCALIZATIONS#$LOCALIZATIONS#" "$APP/Contents/Info.plist"
# 새 버전 확인에 쓰는 정보: 빌드한 커밋과 저장소 (소유자/이름).
# 직접 고친 파일이 있으면 커밋을 적지 않는다 (그런 빌드는 새 버전 확인을 하지 않는다).
COMMIT=""
if [ -z "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
fi
REPO="$(git remote get-url origin 2>/dev/null | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' || true)"
/usr/libexec/PlistBuddy -c "Add :TBCommit string $COMMIT" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :TBRepository string $REPO" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
# 배포 파일로 나가는 빌드인지. 새 버전 확인을 "최신 커밋"이 아니라 "최신 배포 버전" 기준으로 하게 된다.
if [ -n "${TB_VERSION:-}" ]; then IS_RELEASE=true; else IS_RELEASE=false; fi
/usr/libexec/PlistBuddy -c "Add :TBRelease bool $IS_RELEASE" "$APP/Contents/Info.plist"

if [ -n "${TB_SIGN:-}" ]; then
    # 배포용: Developer ID로 서명한다. 공증을 받으려면 hardened runtime과 타임스탬프가 필요하다.
    codesign --force --options runtime --timestamp --sign "$TB_SIGN" "$APP"
else
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "$APP"
