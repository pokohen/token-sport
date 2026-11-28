#!/bin/bash
# 번역 표에 빠진 화면 문구를 찾는다.
# 사용법: Scripts/check-strings.sh [언어]   (기본 en)
#
# 세 가지를 보여 준다.
#   빠짐  컴파일러가 번역 대상으로 읽은 문구(Text("…"), String(localized: "…") 같은 것) 가운데 표에 없는 것
#   남음  코드에서 사라졌는데 표(Resources/<언어>.lproj/*.strings, *.stringsdict)에 남은 것
#   감싸지 않음  한국어 문구인데 번역 대상이 아닌 것 (String으로 넘기면서 String(localized:)를 빠뜨린 것,
#                번역되는 문구 안에 \(조건 ? "홈" : "원정")처럼 끼운 한국어)
# 지금은 앱 화면(Sources/TokenBaseball)만 본다. Dev 폴더(스냅샷·셀프테스트)와 Headless(터미널 출력)는 번역하지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."
LANG_CODE="${1:-en}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swift build --product TokenBaseball \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null

python3 -I - "$OUT" "Resources/$LANG_CODE.lproj" <<'PY'
import glob, json, os, plistlib, re, subprocess, sys

out, lproj = sys.argv[1], sys.argv[2]
used = {}
lines = {}
for path in glob.glob(os.path.join(out, "*.stringsdata")):
    data = json.load(open(path))
    source = data["source"].split("/Sources/")[-1]
    if not source.startswith("TokenBaseball/") or source.startswith("TokenBaseball/Dev/"):
        continue
    for table, items in data["tables"].items():
        for item in items:
            lines.setdefault(source, set()).add(item["location"]["startingLine"])
            if re.search("[가-힣]", item["key"]):
                used.setdefault((table, item["key"]), f'{source}:{item["location"]["startingLine"]}')

have = {}
for path in glob.glob(os.path.join(lproj, "*.strings")) + glob.glob(os.path.join(lproj, "*.stringsdict")):
    table = os.path.splitext(os.path.basename(path))[0]
    raw = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", path], check=True, capture_output=True).stdout
    for key in plistlib.loads(raw):
        have[(table, key)] = path

missing = sorted(k for k in used if k not in have)

def nested_korean(line):
    """문자열 안의 \\( … ) 속에 한국어 문자열이 String(localized:) 없이 들어 있는지."""
    i, in_str, depth_stack = 0, False, []
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\" and line[i + 1:i + 2] == "(":
                depth_stack.append(0); in_str = False; i += 2; continue
            if c == "\\":
                i += 2; continue
            if c == '"':
                in_str = False
        else:
            if c == '"':
                if depth_stack:
                    end = line.find('"', i + 1)
                    inner = line[i + 1:end if end > 0 else len(line)]
                    if re.search("[가-힣]", inner.split("\\(")[0]) and not re.search(r"localized:\s*$", line[:i]):
                        return True
                in_str = True
            elif c == "(" and depth_stack:
                depth_stack[-1] += 1
            elif c == ")" and depth_stack:
                if depth_stack[-1] == 0:
                    depth_stack.pop(); in_str = True
                else:
                    depth_stack[-1] -= 1
        i += 1
    return False

# 번역하지 않는 한국어: enum의 저장되는 값, 기본 팀 이름 같은 데이터.
KEEP = (re.compile(r'^\s*case [a-z]+ = "'), re.compile(r'defaultName'))
literal = re.compile(r'"(?:[^"\\]|\\.)*[가-힣](?:[^"\\]|\\.)*"')

unwrapped = []
for path in sorted(glob.glob("Sources/TokenBaseball/**/*.swift", recursive=True)):
    source = path.split("Sources/")[-1]
    if "/Dev/" in path or path.endswith("Headless.swift"):
        continue
    for number, text in enumerate(open(path), 1):
        if text.lstrip().startswith("//") or any(k.search(text) for k in KEEP):
            continue
        if number in lines.get(source, set()):
            # 번역되는 문구 안에 끼운 한국어 (\(x ? "홈" : "원정")). 끼운 값은 번역되지 않는다.
            if nested_korean(text):
                unwrapped.append(f"{source}:{number}: {text.strip()[:120]}")
        elif literal.search(text):
            unwrapped.append(f"{source}:{number}: {text.strip()[:120]}")
stale = sorted(k for k in have if k not in used)
for table, key in missing:
    print(f"빠짐  {used[(table, key)]}  [{table}] {key!r}")
for table, key in stale:
    print(f"남음  [{table}] {key!r}")
for row in unwrapped:
    print(f"감싸지 않음  {row}")
print(f"번역 대상 {len(used)}개, 빠짐 {len(missing)}개, 남음 {len(stale)}개, 감싸지 않음 {len(unwrapped)}개")
sys.exit(1 if missing or unwrapped else 0)
PY
