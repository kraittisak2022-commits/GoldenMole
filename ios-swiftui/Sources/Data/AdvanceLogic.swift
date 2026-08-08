import Foundation
import SwiftUI

/// Flutter «เบิกเงิน» helpers (`AdvanceGmMeta` + `_saveLaborAdvanceEntry`).
enum AdvanceLogic {
    static let thaiBankNames: [String] = [
        "ธนาคารกรุงเทพ",
        "ธนาคารกสิกรไทย",
        "ธนาคารไทยพาณิชย์",
        "ธนาคารกรุงไทย",
        "ธนาคารกรุงศรีอยุธยา",
        "ธนาคารทหารไทยธนชาต",
        "ธนาคารไอซีบีซี (ไทย)",
        "ธนาคารยูโอบี",
        "ธนาคารซีไอเอ็มบี ไทย",
        "ธนาคารธนชาต",
        "ธนาคารเกียรตินาคินภัทร",
        "ธนาคารออมสิน",
        "ธนาคารเพื่อการเกษตรและสหกรณ์การเกษตร",
        "ธนาคารอาคารสงเคราะห์",
        "ธนาคารแลนด์ แอนด์ เฮ้าส์",
        "ธนาคารซูมิโตโม มิตซุย ทรัสต์ (ไทย)",
        "ธนาคารฮ่องกงและเซี่ยงไฮ้แบงกิ้งคอร์ปอเรชั่น จำกัด",
    ]

    enum PayoutSlot: String, CaseIterable, Identifiable, Sendable {
        case midday
        case evening

        var id: String { rawValue }

        var label: String {
            switch self {
            case .midday: return "กลางวัน"
            case .evening: return "เย็น"
            }
        }

        var descriptionLabel: String {
            switch self {
            case .midday: return "ช่วงกลางวัน"
            case .evening: return "ช่วงเย็น"
            }
        }

        var systemImage: String {
            switch self {
            case .midday: return "sun.max.fill"
            case .evening: return "moon.fill"
            }
        }

        static func from(raw: String?) -> PayoutSlot {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "evening"
                ? .evening
                : .midday
        }
    }

    enum PaymentMethod: String, CaseIterable, Identifiable, Sendable {
        case cash
        case transfer

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cash: return "เงินสด"
            case .transfer: return "เงินโอน"
            }
        }

        var systemImage: String {
            switch self {
            case .cash: return "banknote.fill"
            case .transfer: return "building.columns.fill"
            }
        }

        static func from(raw: String?) -> PaymentMethod {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "transfer"
                ? .transfer
                : .cash
        }
    }

    struct Meta: Equatable, Sendable {
        var payoutSlot: PayoutSlot = .evening
        var paymentMethod: PaymentMethod = .cash
        var bank: String = ""
        var accountNumber: String = ""

        static func decode(workDetails: String?) -> Meta {
            var meta = Meta()
            let raw = (workDetails ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.hasPrefix("{"), raw.hasSuffix("}"),
                  let data = raw.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let adv = root["gm_advance"] as? [String: Any]
            else { return meta }

            meta.payoutSlot = PayoutSlot.from(raw: adv["payout_slot"] as? String)
            meta.paymentMethod = PaymentMethod.from(raw: adv["payment_method"] as? String)
            meta.bank = ((adv["bank"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            meta.accountNumber = ((adv["account_number"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return meta
        }

        func encodeIntoWorkDetails(existing: String? = nil) -> String {
            var root: [String: Any] = [:]
            let ex = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if ex.hasPrefix("{"), ex.hasSuffix("}"),
               let data = ex.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = decoded
            }
            root["gm_advance"] = [
                "payout_slot": payoutSlot.rawValue,
                "payment_method": paymentMethod.rawValue,
                "bank": bank.trimmingCharacters(in: .whitespacesAndNewlines),
                "account_number": accountNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "schema_version": 1,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8)
            else {
                return "{\"gm_advance\":{\"payout_slot\":\"\(payoutSlot.rawValue)\",\"payment_method\":\"\(paymentMethod.rawValue)\",\"bank\":\"\",\"account_number\":\"\",\"schema_version\":1}}"
            }
            return json
        }
    }

    static func eligibleEmployees(from employees: [Employee]) -> [Employee] {
        employees
            .filter(\.isHomeAttendancePool)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func isAdvanceRecord(_ t: Transaction) -> Bool {
        t.category == "Labor"
            && (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Advance") == .orderedSame
            && (t.laborStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Advance") == .orderedSame
            && !(t.employeeIds ?? []).filter { !$0.isEmpty }.isEmpty
    }

    static func dayAdvances(dayKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { String($0.date.prefix(10)) == dayKey && isAdvanceRecord($0) }
            .sorted { ($0.createdAt ?? $0.date) > ($1.createdAt ?? $1.date) }
    }

    static func amount(of t: Transaction) -> Double {
        if let a = t.advanceAmount, a > 0 { return a }
        return max(0, t.amount)
    }

    static func formatBaht(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.numberStyle = .decimal
        f.maximumFractionDigits = value == value.rounded() ? 0 : 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func employeeName(id: String, employees: [Employee]) -> String {
        employees.first(where: { $0.id == id })?.displayName ?? id
    }

    static func bankOptions(including current: String) -> [String] {
        var list = thaiBankNames
        let cur = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cur.isEmpty, !list.contains(cur) {
            list.append(cur)
        }
        return list
    }
}
