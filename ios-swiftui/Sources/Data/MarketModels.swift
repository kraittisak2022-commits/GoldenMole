import Foundation

// MARK: - Enums

enum MarketAssetKey: String, Codable, Sendable, CaseIterable {
    case thaiGold = "thai_gold_965"
    case globalGold = "global_gold"
    case thaiFuel = "thai_fuel"
    case globalOil = "global_oil"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MarketAssetKey(rawValue: raw) ?? .globalGold
    }

    var isGold: Bool { self == .thaiGold || self == .globalGold }
    var isThai: Bool { self == .thaiGold || self == .thaiFuel }
}

enum MarketDirection: String, Codable, Sendable {
    case up, down, flat

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "flat").lowercased()
        self = MarketDirection(rawValue: raw) ?? .flat
    }
}

enum MarketDataQuality: String, Codable, Sendable {
    case high, medium, low

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "medium").lowercased()
        self = MarketDataQuality(rawValue: raw) ?? .medium
    }
}

enum MarketSentiment: String, Codable, Sendable {
    case positive, negative, neutral

    init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "neutral").lowercased()
        self = MarketSentiment(rawValue: raw) ?? .neutral
    }
}

// MARK: - Leaf models

struct MarketForecast: Sendable, Equatable {
    let direction: MarketDirection
    let expectedChangePct: Double
    let expectedLow: Double
    let expectedHigh: Double
    let horizon: String
    let confidence: Double
}

extension MarketForecast: Decodable {
    enum CodingKeys: String, CodingKey {
        case direction, expectedChangePct, expectedLow, expectedHigh, horizon, confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        direction = (try? c.decode(MarketDirection.self, forKey: .direction)) ?? .flat
        expectedChangePct = FlexibleNumber.decodeIfPresent(c, forKey: .expectedChangePct) ?? 0
        expectedLow = FlexibleNumber.decodeIfPresent(c, forKey: .expectedLow) ?? 0
        expectedHigh = FlexibleNumber.decodeIfPresent(c, forKey: .expectedHigh) ?? 0
        horizon = (try? c.decode(String.self, forKey: .horizon)) ?? "รายวัน"
        confidence = FlexibleNumber.decodeIfPresent(c, forKey: .confidence) ?? 0
    }
}

struct MarketMetric: Sendable, Equatable, Identifiable, Decodable {
    let label: String
    let value: String
    let hint: String?

    var id: String { label + value }

    enum CodingKeys: String, CodingKey { case label, value, hint }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        // value may be number or string from the model
        if let s = try? c.decode(String.self, forKey: .value) {
            value = s
        } else if let n = FlexibleNumber.decodeIfPresent(c, forKey: .value) {
            value = String(n)
        } else {
            value = ""
        }
        hint = try? c.decodeIfPresent(String.self, forKey: .hint)
    }
}

struct MarketHistoryPoint: Sendable, Equatable, Identifiable, Decodable {
    let date: String
    let price: Double

    var id: String { date }

    enum CodingKeys: String, CodingKey { case date, price }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        price = FlexibleNumber.decodeIfPresent(c, forKey: .price) ?? 0
    }
}

struct MarketNewsItem: Sendable, Equatable, Identifiable, Decodable {
    let title: String
    let source: String
    let url: String
    let publishedAt: String
    let sentiment: MarketSentiment
    let summary: String

    var id: String { title + url }

    enum CodingKeys: String, CodingKey { case title, source, url, publishedAt, sentiment, summary }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        publishedAt = (try? c.decode(String.self, forKey: .publishedAt)) ?? ""
        sentiment = (try? c.decode(MarketSentiment.self, forKey: .sentiment)) ?? .neutral
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
    }
}

// MARK: - Asset

struct MarketAsset: Sendable, Equatable, Identifiable, Decodable {
    let key: MarketAssetKey
    let label: String
    let unit: String
    let currency: String
    let currentPrice: Double
    let prevClose: Double
    let changeAbs: Double
    let changePct: Double
    let direction: MarketDirection
    let probabilityUp: Double
    let probabilityDown: Double
    let forecast: MarketForecast?
    let metrics: [MarketMetric]
    let history: [MarketHistoryPoint]
    let drivers: [String]
    let news: [MarketNewsItem]
    let aiSummary: String
    let dataQuality: MarketDataQuality

    var id: String { key.rawValue }

    enum CodingKeys: String, CodingKey {
        case key, label, unit, currency, currentPrice, prevClose, changeAbs, changePct
        case direction, probabilityUp, probabilityDown, forecast, metrics, history
        case drivers, news, aiSummary, dataQuality
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decode(MarketAssetKey.self, forKey: .key)) ?? .globalGold
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
        currency = (try? c.decode(String.self, forKey: .currency)) ?? ""
        currentPrice = FlexibleNumber.decodeIfPresent(c, forKey: .currentPrice) ?? 0
        prevClose = FlexibleNumber.decodeIfPresent(c, forKey: .prevClose) ?? 0
        changeAbs = FlexibleNumber.decodeIfPresent(c, forKey: .changeAbs) ?? 0
        changePct = FlexibleNumber.decodeIfPresent(c, forKey: .changePct) ?? 0
        direction = (try? c.decode(MarketDirection.self, forKey: .direction)) ?? .flat
        probabilityUp = FlexibleNumber.decodeIfPresent(c, forKey: .probabilityUp) ?? 0
        probabilityDown = FlexibleNumber.decodeIfPresent(c, forKey: .probabilityDown) ?? 0
        forecast = try? c.decodeIfPresent(MarketForecast.self, forKey: .forecast)
        metrics = (try? c.decodeIfPresent([MarketMetric].self, forKey: .metrics)) ?? []
        history = (try? c.decodeIfPresent([MarketHistoryPoint].self, forKey: .history)) ?? []
        drivers = (try? c.decodeIfPresent([String].self, forKey: .drivers)) ?? []
        news = (try? c.decodeIfPresent([MarketNewsItem].self, forKey: .news)) ?? []
        aiSummary = (try? c.decode(String.self, forKey: .aiSummary)) ?? ""
        dataQuality = (try? c.decode(MarketDataQuality.self, forKey: .dataQuality)) ?? .medium
    }
}

// MARK: - Payload + row

struct MarketInsightPayload: Sendable, Equatable, Decodable {
    let asOfDate: String
    let status: String
    let assets: [MarketAsset]
    let disclaimer: String

    enum CodingKeys: String, CodingKey {
        case asOfDate = "as_of_date"
        case status, assets, disclaimer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOfDate = (try? c.decode(String.self, forKey: .asOfDate)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? "ok"
        assets = (try? c.decodeIfPresent([MarketAsset].self, forKey: .assets)) ?? []
        disclaimer = (try? c.decode(String.self, forKey: .disclaimer))
            ?? "ข้อมูลนี้เป็นการวิเคราะห์เชิงสถิติ/AI ไม่ใช่คำแนะนำการลงทุน"
    }

    func asset(_ key: MarketAssetKey) -> MarketAsset? {
        assets.first { $0.key == key }
    }
}

/// One row from the `market_insights` table (latest is what the app shows).
struct MarketInsightSnapshot: Sendable, Equatable, Decodable {
    let generatedAt: String
    let status: String
    let payload: MarketInsightPayload

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case status, payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = (try? c.decode(String.self, forKey: .generatedAt)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? "ok"
        payload = try c.decode(MarketInsightPayload.self, forKey: .payload)
    }
}
