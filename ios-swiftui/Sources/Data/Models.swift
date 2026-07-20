import Foundation

// MARK: - Core types

enum TransactionType: String, Codable, Sendable {
    case income = "Income"
    case expense = "Expense"
    case leave = "Leave"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransactionType(rawValue: raw) ?? .expense
    }
}

/// Decodes JSON numbers that may arrive as Double, Int, or numeric String (PostgREST / legacy rows).
enum FlexibleNumber {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> Double {
        if let v = try? container.decode(Double.self, forKey: key) { return v }
        if let v = try? container.decode(Int.self, forKey: key) { return Double(v) }
        if let s = try? container.decode(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }
            if let v = Double(trimmed) { return v }
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected numeric value for \(key.stringValue)"
        )
    }

    static func decodeIfPresent<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Double? {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) != true else { return nil }
        return try? decode(container, forKey: key)
    }
}

enum AdminRole: String, Codable, Sendable {
    case superAdmin = "SuperAdmin"
    case admin = "Admin"
    case assistant = "Assistant"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AdminRole(rawValue: raw) ?? .admin
    }
}

struct DateFilter: Equatable, Sendable {
    var start: String
    var end: String
}

enum DashboardTab: String, CaseIterable, Identifiable, Sendable {
    case overviewV1 = "Overview"
    case overviewV5 = "V5"
    case analytics = "Analytics"
    case calendar = "Calendar"
    case realtimeV4 = "V4"
    case labor = "Labor"
    case vehicle = "Vehicle"
    case sand = "Sand"
    case fuel = "Fuel"
    case land = "Land"
    case income = "Income"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overviewV1: return "ภาพรวม (V.1)"
        case .overviewV5: return "ภาพรวม (V.5)"
        case .analytics: return "วิเคราะห์ (V.2)"
        case .calendar: return "ปฏิทิน (V.3)"
        case .realtimeV4: return "Real-time (V.4)"
        case .labor: return "ค่าแรง"
        case .vehicle: return "การใช้รถ"
        case .sand: return "ล้างทราย"
        case .fuel: return "น้ำมัน"
        case .land: return "ที่ดิน"
        case .income: return "รายรับ"
        }
    }

    var group: String {
        switch self {
        case .overviewV1, .overviewV5: return "มุมมองแนะนำ"
        case .analytics, .calendar, .realtimeV4: return "มุมมองขั้นสูง"
        default: return "รายงานตามหมวด"
        }
    }

    static var mainTabs: [DashboardTab] { [.overviewV1, .overviewV5] }
    static var advancedTabs: [DashboardTab] { [.analytics, .calendar, .realtimeV4] }
    static var categoryTabs: [DashboardTab] { [.labor, .vehicle, .sand, .fuel, .land, .income] }
}

enum DateRangePreset: String, CaseIterable, Identifiable, Sendable {
    case days7 = "7"
    case days14 = "14"
    case days30 = "30"
    case custom = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .days7: return "7 วันล่าสุด"
        case .days14: return "14 วันล่าสุด"
        case .days30: return "30 วันล่าสุด"
        case .custom: return "กำหนดเอง"
        }
    }
}

// MARK: - AdminUser

struct AdminUser: Codable, Identifiable, Sendable {
    let id: String
    let username: String
    let password: String
    let displayName: String
    let role: AdminRole
    let createdAt: String?
    let lastLogin: String?
    let avatar: String?
    let mustChangePassword: Bool?
    let sessionActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, password, role, avatar
        case displayName = "display_name"
        case createdAt = "created_at"
        case lastLogin = "last_login"
        case mustChangePassword = "must_change_password"
        case sessionActive = "session_active"
    }
}

extension AdminUser {
    /// Returns a copy with selected fields replaced. Pass `avatar: .some(value)` to change it
    /// (including clearing with `""`); omit it to keep the current value.
    func copy(displayName: String? = nil, avatar: String?? = nil, password: String? = nil) -> AdminUser {
        AdminUser(
            id: id,
            username: username,
            password: password ?? self.password,
            displayName: displayName ?? self.displayName,
            role: role,
            createdAt: createdAt,
            lastLogin: lastLogin,
            avatar: avatar ?? self.avatar,
            mustChangePassword: mustChangePassword,
            sessionActive: sessionActive
        )
    }
}

// MARK: - Employee

struct Employee: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let nickname: String?
    let type: String?
    let baseWage: Double?
    let phone: String?
    let startDate: String?
    let inactive: Bool?
    let position: String?
    let positions: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, type, phone, position, positions, inactive
        case baseWage = "base_wage"
        case startDate = "start_date"
    }

    var displayName: String {
        if let n = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return name
    }
}

// MARK: - Transaction

struct Transaction: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let date: String
    let type: TransactionType
    let category: String
    let subCategory: String?
    let description: String
    let amount: Double
    let createdAt: String?
    let updatedAt: String?
    let employeeId: String?
    let employeeIds: [String]?
    let driverId: String?
    let driverWage: Double?
    let vehicleWage: Double?
    let vehicleId: String?
    let quantity: Double?
    let unit: String?
    let unitPrice: Double?
    let projectId: String?
    let laborStatus: String?
    let workType: String?
    let workTypeByEmployee: [String: String]?
    let workAssignments: [String: [String]]?
    let otAmount: Double?
    let advanceAmount: Double?
    let specialAmount: Double?
    let otHours: Double?
    let leaveReason: String?
    let leaveDays: Double?
    let note: String?
    let workDetails: String?
    let fuelType: String?
    let fuelMovement: String?
    let machineId: String?
    let machineHours: Double?
    let tripCount: Double?
    let tripMorning: Double?
    let tripAfternoon: Double?
    let cubicPerTrip: Double?
    let totalCubic: Double?
    let perCarTrips: Double?
    let perCarCubic: Double?
    let sandMorning: Double?
    let sandAfternoon: Double?
    let sandMachineType: String?
    let sandOperators: [String]?
    let sandTransport: Double?
    let drumsObtained: Double?
    let drumsWashedAtHome: Double?
    let sandBatchId: String?
    let eventType: String?
    let eventPriority: String?
    let eventTime: String?
    let incomePaymentStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, date, type, category, description, amount, quantity, unit, note
        case subCategory = "sub_category"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case employeeId = "employee_id"
        case employeeIds = "employee_ids"
        case driverId = "driver_id"
        case driverWage = "driver_wage"
        case vehicleWage = "vehicle_wage"
        case vehicleId = "vehicle_id"
        case unitPrice = "unit_price"
        case projectId = "project_id"
        case laborStatus = "labor_status"
        case workType = "work_type"
        case workTypeByEmployee = "work_type_by_employee"
        case otAmount = "ot_amount"
        case advanceAmount = "advance_amount"
        case specialAmount = "special_amount"
        case otHours = "ot_hours"
        case leaveReason = "leave_reason"
        case leaveDays = "leave_days"
        case workDetails = "work_details"
        case fuelType = "fuel_type"
        case fuelMovement = "fuel_movement"
        case machineId = "machine_id"
        case machineHours = "machine_hours"
        case tripCount = "trip_count"
        case tripMorning = "trip_morning"
        case tripAfternoon = "trip_afternoon"
        case cubicPerTrip = "cubic_per_trip"
        case totalCubic = "total_cubic"
        case perCarTrips = "per_car_trips"
        case perCarCubic = "per_car_cubic"
        case sandMorning = "sand_morning"
        case sandAfternoon = "sand_afternoon"
        case sandMachineType = "sand_machine_type"
        case sandOperators = "sand_operators"
        case sandTransport = "sand_transport"
        case drumsObtained = "drums_obtained"
        case drumsWashedAtHome = "drums_washed_at_home"
        case sandBatchId = "sand_batch_id"
        case eventType = "event_type"
        case eventPriority = "event_priority"
        case eventTime = "event_time"
        case incomePaymentStatus = "income_payment_status"
        case workAssignments = "work_assignments"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        type = (try? c.decode(TransactionType.self, forKey: .type)) ?? .expense
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        subCategory = try c.decodeIfPresent(String.self, forKey: .subCategory)
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        amount = (try? FlexibleNumber.decode(c, forKey: .amount)) ?? 0
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        employeeId = try c.decodeIfPresent(String.self, forKey: .employeeId)
        employeeIds = try c.decodeIfPresent([String].self, forKey: .employeeIds)
        driverId = try c.decodeIfPresent(String.self, forKey: .driverId)
        driverWage = FlexibleNumber.decodeIfPresent(c, forKey: .driverWage)
        vehicleWage = FlexibleNumber.decodeIfPresent(c, forKey: .vehicleWage)
        vehicleId = try c.decodeIfPresent(String.self, forKey: .vehicleId)
        quantity = FlexibleNumber.decodeIfPresent(c, forKey: .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        unitPrice = FlexibleNumber.decodeIfPresent(c, forKey: .unitPrice)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        laborStatus = try c.decodeIfPresent(String.self, forKey: .laborStatus)
        workType = try c.decodeIfPresent(String.self, forKey: .workType)
        workTypeByEmployee = try c.decodeIfPresent([String: String].self, forKey: .workTypeByEmployee)
        workAssignments = Self.decodeWorkAssignments(from: c)
        otAmount = FlexibleNumber.decodeIfPresent(c, forKey: .otAmount)
        advanceAmount = FlexibleNumber.decodeIfPresent(c, forKey: .advanceAmount)
        specialAmount = FlexibleNumber.decodeIfPresent(c, forKey: .specialAmount)
        otHours = FlexibleNumber.decodeIfPresent(c, forKey: .otHours)
        leaveReason = try c.decodeIfPresent(String.self, forKey: .leaveReason)
        leaveDays = FlexibleNumber.decodeIfPresent(c, forKey: .leaveDays)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        workDetails = try c.decodeIfPresent(String.self, forKey: .workDetails)
        fuelType = try c.decodeIfPresent(String.self, forKey: .fuelType)
        fuelMovement = try c.decodeIfPresent(String.self, forKey: .fuelMovement)
        machineId = try c.decodeIfPresent(String.self, forKey: .machineId)
        machineHours = FlexibleNumber.decodeIfPresent(c, forKey: .machineHours)
        tripCount = FlexibleNumber.decodeIfPresent(c, forKey: .tripCount)
        tripMorning = FlexibleNumber.decodeIfPresent(c, forKey: .tripMorning)
        tripAfternoon = FlexibleNumber.decodeIfPresent(c, forKey: .tripAfternoon)
        cubicPerTrip = FlexibleNumber.decodeIfPresent(c, forKey: .cubicPerTrip)
        totalCubic = FlexibleNumber.decodeIfPresent(c, forKey: .totalCubic)
        perCarTrips = FlexibleNumber.decodeIfPresent(c, forKey: .perCarTrips)
        perCarCubic = FlexibleNumber.decodeIfPresent(c, forKey: .perCarCubic)
        sandMorning = FlexibleNumber.decodeIfPresent(c, forKey: .sandMorning)
        sandAfternoon = FlexibleNumber.decodeIfPresent(c, forKey: .sandAfternoon)
        sandMachineType = try c.decodeIfPresent(String.self, forKey: .sandMachineType)
        sandOperators = try c.decodeIfPresent([String].self, forKey: .sandOperators)
        sandTransport = FlexibleNumber.decodeIfPresent(c, forKey: .sandTransport)
        drumsObtained = FlexibleNumber.decodeIfPresent(c, forKey: .drumsObtained)
        drumsWashedAtHome = FlexibleNumber.decodeIfPresent(c, forKey: .drumsWashedAtHome)
        sandBatchId = try c.decodeIfPresent(String.self, forKey: .sandBatchId)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
        eventPriority = try c.decodeIfPresent(String.self, forKey: .eventPriority)
        eventTime = try c.decodeIfPresent(String.self, forKey: .eventTime)
        incomePaymentStatus = try c.decodeIfPresent(String.self, forKey: .incomePaymentStatus)
    }

    /// Accepts `[String: [String]]` or coerces mixed JSON arrays (numbers → strings) for lapTimes.
    private static func decodeWorkAssignments(
        from c: KeyedDecodingContainer<CodingKeys>
    ) -> [String: [String]]? {
        if let direct = try? c.decodeIfPresent([String: [String]].self, forKey: .workAssignments) {
            return direct
        }
        guard let raw = try? c.decodeIfPresent([String: [FlexibleStringValue]].self, forKey: .workAssignments) else {
            return nil
        }
        var out: [String: [String]] = [:]
        for (key, values) in raw {
            out[key] = values.map(\.value)
        }
        return out.isEmpty ? nil : out
    }
}

/// Wrapper so JSON array elements that are numbers or strings both become String.
private struct FlexibleStringValue: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
        } else if let i = try? c.decode(Int.self) {
            value = String(i)
        } else if let d = try? c.decode(Double.self) {
            value = String(d)
        } else {
            value = ""
        }
    }
}

// MARK: - AppSettings

struct AppSettings: Codable, Sendable, Equatable {
    let appName: String
    let appSubtext: String?
    let appIcon: String?
    let cars: [String]
    let jobDescriptions: [String]
    let incomeTypes: [String]
    let expenseTypes: [String]
    let maintenanceTypes: [String]
    let locations: [String]
    let landGroups: [String]
    let employeePositions: [String]?
    let fuelOpeningStockLiters: FuelStock?

    enum CodingKeys: String, CodingKey {
        case cars, locations
        case appName = "app_name"
        case appSubtext = "app_subtext"
        case appIcon = "app_icon"
        case jobDescriptions = "job_descriptions"
        case incomeTypes = "income_types"
        case expenseTypes = "expense_types"
        case maintenanceTypes = "maintenance_types"
        case landGroups = "land_groups"
        case employeePositions = "employee_positions"
        case fuelOpeningStockLiters = "fuel_opening_stock"
    }

    static let fallback = AppSettings(
        appName: "Goldenmole",
        appSubtext: nil,
        appIcon: nil,
        cars: [],
        jobDescriptions: [],
        incomeTypes: ["รายรับทั่วไป"],
        expenseTypes: [],
        maintenanceTypes: [],
        locations: [],
        landGroups: [],
        employeePositions: [],
        fuelOpeningStockLiters: nil
    )
}

struct FuelStock: Codable, Sendable, Equatable {
    let diesel: Double?
    let benzine: Double?

    enum CodingKeys: String, CodingKey {
        case diesel = "Diesel"
        case benzine = "Benzine"
    }
}

struct AppSettingsRow: Codable, Sendable {
    let id: String
    let appName: String?
    let appSubtext: String?
    let appIcon: String?
    let cars: [String]?
    let jobDescriptions: [String]?
    let incomeTypes: [String]?
    let expenseTypes: [String]?
    let maintenanceTypes: [String]?
    let locations: [String]?
    let landGroups: [String]?
    let employeePositions: [String]?
    let fuelOpeningStock: FuelStock?

    enum CodingKeys: String, CodingKey {
        case id, cars, locations
        case appName = "app_name"
        case appSubtext = "app_subtext"
        case appIcon = "app_icon"
        case jobDescriptions = "job_descriptions"
        case incomeTypes = "income_types"
        case expenseTypes = "expense_types"
        case maintenanceTypes = "maintenance_types"
        case landGroups = "land_groups"
        case employeePositions = "employee_positions"
        case fuelOpeningStock = "fuel_opening_stock"
    }

    func toAppSettings() -> AppSettings {
        AppSettings(
            appName: appName ?? "Goldenmole",
            appSubtext: appSubtext,
            appIcon: appIcon,
            cars: cars ?? [],
            jobDescriptions: jobDescriptions ?? [],
            incomeTypes: IncomeTypes.visible(incomeTypes ?? []),
            expenseTypes: expenseTypes ?? [],
            maintenanceTypes: maintenanceTypes ?? [],
            locations: locations ?? [],
            landGroups: landGroups ?? [],
            employeePositions: employeePositions,
            fuelOpeningStockLiters: fuelOpeningStock
        )
    }
}

enum IncomeTypes {
    private static let hidden: Set<String> = ["ขายแร่"]

    static func visible(_ types: [String]) -> [String] {
        types.filter { !hidden.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    }
}

// MARK: - Chart helpers

struct ChartSlice: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let value: Double
    let colorHex: String
}

struct DailyPoint: Identifiable, Sendable {
    let id: String
    let date: String
    let label: String
    let value: Double
}

struct FinancialSummary: Sendable {
    let income: Double
    let expense: Double
    var profit: Double { income - expense }
}

struct CompositeScoreResult: Sendable {
    let score: Int
    let breakdown: [ScoreBreakdownItem]
}

struct ScoreBreakdownItem: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let weight: String
    let scorePart: Int
    let changeLabel: String
    let trend: ScoreTrend
}

enum ScoreTrend: Sendable {
    case up, down, flat, neutral
}

struct CountRecordTripUnit: Identifiable, Sendable {
    let id: String
    let vehicleId: String
    let driverId: String
    let driverLabel: String
    let rounds: Int
    let morning: Int
    let afternoon: Int
    /// Laps from 17:00 onward (subset of afternoon)
    let ot: Int
    let lapTimes: [String]
    let broken: Bool
}

struct CountRecordSandUnit: Identifiable, Sendable {
    let id: String
    let rounds: Int
    let morning: Int
    let afternoon: Int
    let ot: Int
    let lapTimes: [String]
}

struct CountRecordWorkSpan: Sendable {
    let startStamp: String?
    let endStamp: String?
    let startClock: String?
    let endClock: String?
}

struct VehicleEfficiency: Sendable {
    let perVehToday: Double
    let countToday: Int
    let deltaPct: Double?
    let priorLabel: String
    let isCalendarYesterday: Bool
}

// MARK: - Overview hub aggregations

struct DailyExpenseBreakdown: Sendable, Identifiable {
    var id: String { date }
    let date: String
    let label: String
    let labor: Double
    let fuel: Double
    let vehicle: Double
    let maintenance: Double
    let land: Double
    let total: Double
}

struct WeeklyExpenseBucket: Sendable, Identifiable {
    var id: String { label }
    let label: String
    let total: Double
    let labor: Double
    let fuel: Double
    let vehicle: Double
    let land: Double
}

struct VehicleCostRow: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let fuel: Double
    let maintenance: Double
    var total: Double { fuel + maintenance }
}

struct SandDrumsSeries: Sendable {
    let obtained: [Double]
    let home: [Double]
    let remainingCumulative: [Double]
    let labels: [String]
    let dates: [String]
    let totalObtained: Double
    let totalHome: Double
    /// Final cumulative remaining (ได้ − ล้างบ้าน)
    var drumsRemaining: Double { remainingCumulative.last ?? 0 }
}

struct SandOverviewKPIs: Sendable {
    let washed: Double
    let transported: Double
    let remaining: Double
    let forecastLabel: String
    let avgWashedPerDay: Double
    let avgTransportedPerDay: Double
    let drumsObtained: Double
    let drumsHome: Double
    let drumsRemaining: Double
}

struct DataQualitySummary: Sendable {
    let totalDays: Int
    let daysWithRecords: Int
    let coveragePct: Double
    let daysWithSand: Int
    let sandCoveragePct: Double

    var statusLabel: String {
        if coveragePct >= 80 { return "ดี" }
        if coveragePct >= 50 { return "ปานกลาง" }
        return "ต้องระวัง"
    }
}

struct OverviewAlert: Sendable, Identifiable {
    let id: String
    let label: String
    let severity: Severity
    enum Severity: Sendable { case red, amber, green }
}

struct BreakEvenPoint: Sendable {
    let label: String
    let income: Double
    let expense: Double
}
