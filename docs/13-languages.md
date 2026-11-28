# 13. 다른 언어 (영어·일본어)

한국어가 기본이다. 영어와 일본어 표가 있다. ✅는 한 것, 💡는 계획이다.

## 어떻게 동작하나

- 앱 하나에 모든 언어가 들어간다. 언어마다 따로 빌드하지 않는다.
- 코드에 쓴 **한국어 문구가 그대로 열쇠**다. 번역은 `Resources/<언어>.lproj/*.strings`에 둔다.
  - `Localizable.strings`: 대부분의 문구.
  - `Actions.strings`, `Counts.strings`, `Club.strings`: 같은 한국어가 영어로는 둘로 갈리는 몇 개 (버튼 "계약"=Sign / 카드 "계약"=Contract, 버튼 "종료"=Quit / 경기 "종료"=Final, 남은 기간 "N시즌"=N seasons / 몇 번째 "N시즌"=Season N).
  - `*.stringsdict`: 영어의 단수·복수 (1 match / 2 matches). 수를 세는 문구는 여기에 넣는다. 일본어는 단수·복수가 없어서 `.strings`에만 둔다.
- macOS가 맥의 언어(또는 시스템 설정 → 일반 → 언어 및 지역 → 응용 프로그램에서 고른 언어)에 맞는 표를 고른다. 넣은 언어 가운데 없으면 한국어로 나온다.
- `Scripts/make-app.sh`가 `ko.lproj`와 `TB_LANGUAGES`에 적은 언어의 표를 앱에 넣고, Info.plist에 `CFBundleDevelopmentRegion`(ko)과 `CFBundleLocalizations`를 적는다.

## 코드에 문구를 쓸 때

- `Text("…")`, `Button("…")`, `Toggle("…")`처럼 SwiftUI가 받는 문구는 그대로 번역된다.
- 그 밖에 `String`으로 넘기는 문구(카드 제목, `KeyValueRow`, 알림, 오류 메시지)는 `String(localized: "…")`로 쓴다.
- 조사를 따로 붙이지 않는다. `"\(이름)\(받침 ? "을" : "를")"` 대신 문장 둘을 쓴다 (영어에서 조사만 따로 옮길 수 없다).
- 번역되는 문구 안에 한국어를 끼우지 않는다. `Text("\(홈 ? "홈" : "원정") vs \(상대)")`의 "홈"은 번역되지 않는다. `Text(홈 ? "홈 vs \(상대)" : "원정 vs \(상대)")`처럼 문장째 나누거나, 끼울 말을 `String(localized:)`로 감싼다.
- `Double`을 그대로 끼우면 `%lf`가 되어 `1.500000`처럼 나온다. `String(format:)`이나 `String(describing:)`로 먼저 글자로 만든다.
- 새 문구를 넣었으면 `Scripts/check-strings.sh`로 확인한다. 표에 빠진 번역과 `String(localized:)`로 감싸지 않은 한국어 문구를 찾는다.
- `String(localized:)` 안에 끼운 정수는 `12,345`처럼 자리 구분이 붙는다 (SwiftUI `Text`도 같다).
- Core가 만드는 이름(포지션, 리그, 능력치, 전술 …)은 Core에서 번역하지 않는다. Core는 늘 한국어로 같은 글을 내야 한다 (지문 테스트가 소식 문장을 해시하고, 한국어 `rawValue`가 저장 파일에 들어간다). 화면에 보일 이름은 `Support/*+Display.swift`에 있다. case마다 `String(localized: "…")`를 하나씩 쓰는 `switch`로 만들고, 화면에서는 `localizedLabel`·`localizedName`을 쓴다. `String(localized: String.LocalizationValue(x.rawValue))`는 쓰지 않는다 (컴파일러가 문구를 읽지 못해 `check-strings`가 빠진 것을 찾지 못한다).
- 돈과 팬 수는 `DisplayFormat`으로 쓴다. 한국어·일본어는 만·억, 영어는 K·M·B로 끊는다 (`₩3.2억` = `₩320M`). 단위가 달라 번역 표만으로는 바꿀 수 없다.

## 시험해 보기

```sh
TB_LANGUAGES="en ja" Scripts/make-app.sh
open "build/Token Sports.app" --args -AppleLanguages '(en)'   # 일본어는 '(ja)'
Scripts/check-strings.sh ja   # 일본어 표 확인 (기본은 en)
# 화면 그림으로 보기
TOKEN_BASEBALL_SAVE=/tmp/tb-en/save.json TOKEN_BASEBALL_SNAPSHOT=/tmp/tb-en-snap \
  "build/Token Sports.app/Contents/MacOS/TokenBaseball" -AppleLanguages '(en)'
```

## 만드는 순서

1. ✅ **앱 화면 (`Sources/TokenBaseball`)**: 화면 문구 658개를 영어와 일본어로 옮겼다. 배포 앱에는 아직 넣지 않는다 (`TB_LANGUAGES`를 비워 두면 한국어만 들어간다).
2. **Core가 만드는 이름**
   - ✅ 포지션, 리그, 능력치, 훈련 이름, 전술, 시설, 홍보, 역할, 컨디션, 종족, 빌드, 칭호, 대회·컵 라운드 이름, 경기 시각(회·전후반·쿼터), 돈·팬·남은 시간 단위. 앱 쪽(`Support/*+Display.swift`)에서 번역한다.
   - 💡 오류 문구(`GameError`, 85곳)와 "할 수 없는 이유" 문구(승격 신청, 훈련, 활동, 은퇴, 바로 경기 …). Core가 다 만든 문장을 넘기므로, Core에 종류(enum)를 더하고 앱이 문장을 만들게 한다. 한국어 문장은 그대로 둔다.
   - 💡 리그 탭 기록 순위 제목, 경기 중 "내 선수" 기록 줄. Core가 기록 종류를 같이 넘겨야 한다.
3. 💡 **소식과 문자 중계**: 지금은 다 만든 한국어 문장을 저장한다 (`NewsItem.text`, `MatchEvent.text`). 그대로 두면 언어를 바꿔도 예전 소식은 한국어로 남는다. 문장 대신 "무슨 일이었는지"(종류와 값)를 저장하고 화면에서 문장으로 만들도록 바꿔야 한다. 저장 파일 모양이 바뀌고, 지문 테스트(`SportFingerprintTests`, `GoldenTests`)가 소식 문장을 해시하므로 따로 PR로 한다. 테스트는 기계 언어와 상관없이 늘 한국어로 돌아야 한다.
4. 💡 **선수·구단 이름**: 이름 생성기가 한국어 이름만 만든다. 언어에 따라 다른 이름을 만들지는 새 세계부터 적용할지 정해야 한다 (이미 만든 이름은 저장 파일에 남는다).
5. 💡 2~3이 끝나면 배포 앱에 영어를 넣는다 (`Scripts/release.sh`에서 `TB_LANGUAGES="en ja"`).
6. 💡 일본어도 2~3이 끝난 뒤 함께 넣는다. 앱 화면 표(`Resources/ja.lproj`)는 있다. 어순이 한국어와 비슷해서 2~3도 표만 더하면 된다.
