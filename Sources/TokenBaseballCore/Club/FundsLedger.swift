import Foundation

/// 구단 자금 장부.
///
/// 자금을 매번 로그에서 다시 계산하지 않는다. Claude Code가 오래된 로그를 지우기 때문에
/// 다시 계산하면 자금이 줄어든다. 대신 마지막으로 반영한 시점 이후의 사용량만 더해 간다.
public struct FundsLedger: Codable, Equatable, Sendable {
    /// 시작 자금 (토큰 100K 분량).
    public static let startingFunds = 100_000

    /// 이미 반영한 응답을 기억해 두는 시간. 응답 하나가 이보다 오래 이어지지는 않는다고 본다.
    static let recentWindow: TimeInterval = 60 * 60

    /// 현재 자금(원). 연봉 등으로 0 아래로 내려갈 수 있다.
    public private(set) var balance: Int
    /// 지금까지 토큰으로 번 누적 자금.
    public private(set) var tokenIncome: Int
    /// 구단을 만든 시각. 이보다 앞선 사용량은 소급하지 않는다.
    public let startedAt: Date
    /// 마지막으로 사용량을 반영한 시각.
    public private(set) var checkpoint: Date
    /// 최근에 반영한 응답. 같은 응답을 두 번 세지 않고, 뒤늦게 늘어난 사용량만 더하기 위해 둔다.
    private var recent: [String: Counted]
    /// 이번 시즌 수입·지출 내역 (항목별).
    public private(set) var seasonIncome: [String: Int] = [:]
    public private(set) var seasonExpense: [String: Int] = [:]
    /// 지난 경기 이후 쓴 토큰. 토큰 연동 훈련에 쓰고, 경기가 끝나면 0으로 돌린다.
    public var trainingTokens = 0
    /// 쉬다가 돌아온 시각. 이보다 앞선 사용량은 세지 않는다. 쉰 적이 없으면 nil.
    public private(set) var resumedAt: Date?

    /// 수입·지출 항목.
    public enum Category: String, CaseIterable, Sendable {
        case tokens = "토큰"
        case gate = "관중 수입"
        case sponsor = "스폰서"
        case prize = "상금·지원금"
        case sales = "선수 판매"
        case salary = "선수 연봉"
        case facility = "시설"
        case promotion = "홍보"
        case recruit = "선수 영입"
        case fee = "승강 신청비"
        case training = "훈련"
        case extraMatch = "추가 경기"
        case skipMatch = "결과 바로 보기"
    }

    private struct Counted: Codable, Equatable, Sendable {
        var timestamp: Date
        var total: Int
    }

    public init(startedAt: Date, startingFunds: Int = FundsLedger.startingFunds) {
        self.balance = startingFunds
        self.tokenIncome = 0
        self.startedAt = startedAt
        self.checkpoint = startedAt
        self.recent = [:]
    }

    /// 다음 반영 때 로그를 어디서부터 읽어야 하는지.
    public var collectSince: Date {
        max(startedAt, resumedAt ?? .distantPast, checkpoint.addingTimeInterval(-Self.recentWindow))
    }

    /// 쉬는 동안(다른 종목의 구단을 운영하는 동안) 쓴 토큰은 세지 않는다.
    /// 돌아온 시각 이전의 기록은 다시 읽지 않는다.
    public mutating func skip(to now: Date) {
        resumedAt = max(resumedAt ?? .distantPast, now)
        checkpoint = max(checkpoint, now)
        recent = [:]
    }

    /// 사용량 기록을 자금에 반영하고, 이번에 번 금액을 돌려준다.
    /// 같은 기록을 여러 번 넣어도 한 번만 센다.
    @discardableResult
    public mutating func collect(_ records: [UsageRecord], now: Date) -> Int {
        let since = collectSince
        var earned = 0
        for record in records where record.timestamp >= since {
            let total = record.usage.total
            let counted = recent[record.id]?.total ?? 0
            if total > counted {
                earned += total - counted
            }
            recent[record.id] = Counted(timestamp: record.timestamp, total: max(total, counted))
        }

        balance += earned
        tokenIncome += earned
        trainingTokens += earned
        if earned > 0 { seasonIncome[Category.tokens.rawValue, default: 0] += earned }
        checkpoint = max(checkpoint, now)

        let keepFrom = checkpoint.addingTimeInterval(-Self.recentWindow)
        recent = recent.filter { $0.value.timestamp >= keepFrom }
        return earned
    }

    /// 로그를 읽어 새 사용량을 자금에 반영한다.
    @discardableResult
    public mutating func collect(using reader: ClaudeCodeUsageReader, now: Date = Date()) -> Int {
        collect(reader.records(since: collectSince), now: now)
    }

    // MARK: 토큰 말고 들어오고 나가는 돈

    public mutating func earn(_ amount: Int, _ category: Category) {
        guard amount > 0 else { return }
        balance += amount
        seasonIncome[category.rawValue, default: 0] += amount
    }

    /// 돈을 낸다. 연봉처럼 꼭 나가야 하는 돈은 자금이 모자라도 나가서 0 아래로 내려갈 수 있다.
    public mutating func spend(_ amount: Int, _ category: Category) {
        guard amount > 0 else { return }
        balance -= amount
        seasonExpense[category.rawValue, default: 0] += amount
    }

    /// 새 시즌: 시즌 내역을 비운다.
    public mutating func startNewSeason() {
        seasonIncome = [:]
        seasonExpense = [:]
    }
}
