import Foundation

/// Work mode before opening count-record panels (Flutter parity).
enum CountRecordWorkMode: String, CaseIterable, Identifiable, Sendable {
    case trip
    case sand
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trip: return "ขนอย่างเดียว"
        case .sand: return "ร่อนทรายอย่างเดียว"
        case .both: return "ทั้งขนและร่อน"
        }
    }

    var subtitle: String {
        switch self {
        case .trip: return "บันทึกจำนวนเที่ยวรถ"
        case .sand: return "บันทึกการร่อนทราย"
        case .both: return "เปิดทั้งสองแผงพร้อมกัน"
        }
    }

    var systemImage: String {
        switch self {
        case .trip: return "truck.box.fill"
        case .sand: return "drop.fill"
        case .both: return "square.split.2x1.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .trip: return "#1565C0"
        case .sand: return "#AD1457"
        case .both: return "#0D98A5"
        }
    }
}
