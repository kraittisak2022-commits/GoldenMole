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
    case yesterday = "yesterday"
    case today = "1"
    case days7 = "7"
    case days14 = "14"
    case days30 = "30"
    case custom = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yesterday: return "เมื่อวานนี้"
        case .today: return "วันนี้"
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

    /// Active when `inactive` is missing or explicitly false.
    var isActive: Bool { inactive != true }

    /// Position labels from both the multi-position array and the legacy single field.
    var positionTokens: [String] {
        var tokens: [String] = []
        for p in positions ?? [] {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { tokens.append(t) }
        }
        if let single = position?.trimmingCharacters(in: .whitespacesAndNewlines), !single.isEmpty {
            tokens.append(single)
        }
        return tokens
    }

    private var compactPositionTokens: Set<String> {
        Set(positionTokens.map { $0.replacingOccurrences(of: " ", with: "") })
    }

    /// Matches Flutter sand-yard attendance pool titles.
    var isSandYardStaff: Bool {
        let titles: Set<String> = ["พนักงานท่าทราย", "พนักงานทำทราย", "ท่าทราย"]
        return !compactPositionTokens.isDisjoint(with: titles)
    }

    /// Matches Flutter macro excavator driver titles (ทั้งสะกด แม็ค / แมค).
    var isMacroDriver: Bool {
        let titles: Set<String> = ["คนขับรถแม็คโคร", "คนขับรถแมคโคร"]
        return !compactPositionTokens.isDisjoint(with: titles)
    }

    /// Home-tab attendance roster: active sand-yard staff + macro drivers only.
    var isHomeAttendancePool: Bool {
        isActive && (isSandYardStaff || isMacroDriver)
    }
}

// MARK: - Transaction

struct Transaction: Codable, Identifiable, Sendable, Equatable {
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
    let vehicleName: String?
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
    let fuelTank: String?
    let machineId: String?
    let machineHours: Double?
    let tripCount: Double?
    let tripMorning: Double?
    let tripAfternoon: Double?
    let tripBillingMode: String?
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
        case vehicleName = "vehicle_name"
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
        case fuelTank = "fuel_tank"
        case machineId = "machine_id"
        case machineHours = "machine_hours"
        case tripCount = "trip_count"
        case tripMorning = "trip_morning"
        case tripAfternoon = "trip_afternoon"
        case tripBillingMode = "trip_billing_mode"
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
        vehicleName = try c.decodeIfPresent(String.self, forKey: .vehicleName)
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
        fuelTank = try c.decodeIfPresent(String.self, forKey: .fuelTank)
        machineId = try c.decodeIfPresent(String.self, forKey: .machineId)
        machineHours = FlexibleNumber.decodeIfPresent(c, forKey: .machineHours)
        tripCount = FlexibleNumber.decodeIfPresent(c, forKey: .tripCount)
        tripMorning = FlexibleNumber.decodeIfPresent(c, forKey: .tripMorning)
        tripAfternoon = FlexibleNumber.decodeIfPresent(c, forKey: .tripAfternoon)
        tripBillingMode = try c.decodeIfPresent(String.self, forKey: .tripBillingMode)
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(type, forKey: .type)
        try c.encode(category, forKey: .category)
        try c.encode(description, forKey: .description)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(subCategory, forKey: .subCategory)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(employeeId, forKey: .employeeId)
        try c.encodeIfPresent(employeeIds, forKey: .employeeIds)
        try c.encodeIfPresent(driverId, forKey: .driverId)
        try c.encodeIfPresent(driverWage, forKey: .driverWage)
        try c.encodeIfPresent(vehicleWage, forKey: .vehicleWage)
        try c.encodeIfPresent(vehicleId, forKey: .vehicleId)
        try c.encodeIfPresent(vehicleName, forKey: .vehicleName)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(unitPrice, forKey: .unitPrice)
        try c.encodeIfPresent(projectId, forKey: .projectId)
        try c.encodeIfPresent(laborStatus, forKey: .laborStatus)
        try c.encodeIfPresent(workType, forKey: .workType)
        try c.encodeIfPresent(workTypeByEmployee, forKey: .workTypeByEmployee)
        try c.encodeIfPresent(workAssignments, forKey: .workAssignments)
        try c.encodeIfPresent(otAmount, forKey: .otAmount)
        try c.encodeIfPresent(advanceAmount, forKey: .advanceAmount)
        try c.encodeIfPresent(specialAmount, forKey: .specialAmount)
        try c.encodeIfPresent(otHours, forKey: .otHours)
        try c.encodeIfPresent(leaveReason, forKey: .leaveReason)
        try c.encodeIfPresent(leaveDays, forKey: .leaveDays)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(workDetails, forKey: .workDetails)
        try c.encodeIfPresent(fuelType, forKey: .fuelType)
        try c.encodeIfPresent(fuelMovement, forKey: .fuelMovement)
        try c.encodeIfPresent(fuelTank, forKey: .fuelTank)
        try c.encodeIfPresent(machineId, forKey: .machineId)
        try c.encodeIfPresent(machineHours, forKey: .machineHours)
        try c.encodeIfPresent(tripCount, forKey: .tripCount)
        try c.encodeIfPresent(tripMorning, forKey: .tripMorning)
        try c.encodeIfPresent(tripAfternoon, forKey: .tripAfternoon)
        try c.encodeIfPresent(tripBillingMode, forKey: .tripBillingMode)
        try c.encodeIfPresent(cubicPerTrip, forKey: .cubicPerTrip)
        try c.encodeIfPresent(totalCubic, forKey: .totalCubic)
        try c.encodeIfPresent(perCarTrips, forKey: .perCarTrips)
        try c.encodeIfPresent(perCarCubic, forKey: .perCarCubic)
        try c.encodeIfPresent(sandMorning, forKey: .sandMorning)
        try c.encodeIfPresent(sandAfternoon, forKey: .sandAfternoon)
        try c.encodeIfPresent(sandMachineType, forKey: .sandMachineType)
        try c.encodeIfPresent(sandOperators, forKey: .sandOperators)
        try c.encodeIfPresent(sandTransport, forKey: .sandTransport)
        try c.encodeIfPresent(drumsObtained, forKey: .drumsObtained)
        try c.encodeIfPresent(drumsWashedAtHome, forKey: .drumsWashedAtHome)
        try c.encodeIfPresent(sandBatchId, forKey: .sandBatchId)
        try c.encodeIfPresent(eventType, forKey: .eventType)
        try c.encodeIfPresent(eventPriority, forKey: .eventPriority)
        try c.encodeIfPresent(eventTime, forKey: .eventTime)
        try c.encodeIfPresent(incomePaymentStatus, forKey: .incomePaymentStatus)
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
    /// From `app_settings.app_defaults.vehicleDefaultDrivers` (Flutter parity).
    let vehicleDefaultDrivers: [String: String]
    /// From `vehicles` table — resolves `v_…` ids to display names.
    let vehicleCatalog: [VehicleCatalogRow]
    /// Soft update channel (copied from `app_defaults` when present).
    let iosLatestVersion: String?
    let iosLatestBuild: String?
    let iosTestFlightURL: String?
    let iosUpdateMessage: String?

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
        case vehicleDefaultDrivers = "vehicle_default_drivers"
        case vehicleCatalog = "vehicle_catalog"
        case iosLatestVersion = "ios_latest_version"
        case iosLatestBuild = "ios_latest_build"
        case iosTestFlightURL = "ios_testflight_url"
        case iosUpdateMessage = "ios_update_message"
    }

    init(
        appName: String,
        appSubtext: String?,
        appIcon: String?,
        cars: [String],
        jobDescriptions: [String],
        incomeTypes: [String],
        expenseTypes: [String],
        maintenanceTypes: [String],
        locations: [String],
        landGroups: [String],
        employeePositions: [String]?,
        fuelOpeningStockLiters: FuelStock?,
        vehicleDefaultDrivers: [String: String],
        vehicleCatalog: [VehicleCatalogRow] = [],
        iosLatestVersion: String? = nil,
        iosLatestBuild: String? = nil,
        iosTestFlightURL: String? = nil,
        iosUpdateMessage: String? = nil
    ) {
        self.appName = appName
        self.appSubtext = appSubtext
        self.appIcon = appIcon
        self.cars = cars
        self.jobDescriptions = jobDescriptions
        self.incomeTypes = incomeTypes
        self.expenseTypes = expenseTypes
        self.maintenanceTypes = maintenanceTypes
        self.locations = locations
        self.landGroups = landGroups
        self.employeePositions = employeePositions
        self.fuelOpeningStockLiters = fuelOpeningStockLiters
        self.vehicleDefaultDrivers = vehicleDefaultDrivers
        self.vehicleCatalog = vehicleCatalog
        self.iosLatestVersion = iosLatestVersion
        self.iosLatestBuild = iosLatestBuild
        self.iosTestFlightURL = iosTestFlightURL
        self.iosUpdateMessage = iosUpdateMessage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appName = (try c.decodeIfPresent(String.self, forKey: .appName)) ?? "Goldenmole"
        appSubtext = try c.decodeIfPresent(String.self, forKey: .appSubtext)
        appIcon = try c.decodeIfPresent(String.self, forKey: .appIcon)
        cars = (try c.decodeIfPresent([String].self, forKey: .cars)) ?? []
        jobDescriptions = (try c.decodeIfPresent([String].self, forKey: .jobDescriptions)) ?? []
        incomeTypes = IncomeTypes.visible((try c.decodeIfPresent([String].self, forKey: .incomeTypes)) ?? [])
        expenseTypes = (try c.decodeIfPresent([String].self, forKey: .expenseTypes)) ?? []
        maintenanceTypes = (try c.decodeIfPresent([String].self, forKey: .maintenanceTypes)) ?? []
        locations = (try c.decodeIfPresent([String].self, forKey: .locations)) ?? []
        landGroups = (try c.decodeIfPresent([String].self, forKey: .landGroups)) ?? []
        employeePositions = try c.decodeIfPresent([String].self, forKey: .employeePositions)
        fuelOpeningStockLiters = try c.decodeIfPresent(FuelStock.self, forKey: .fuelOpeningStockLiters)
        vehicleDefaultDrivers = (try c.decodeIfPresent([String: String].self, forKey: .vehicleDefaultDrivers)) ?? [:]
        vehicleCatalog = (try c.decodeIfPresent([VehicleCatalogRow].self, forKey: .vehicleCatalog)) ?? []
        iosLatestVersion = try c.decodeIfPresent(String.self, forKey: .iosLatestVersion)
        iosLatestBuild = try c.decodeIfPresent(String.self, forKey: .iosLatestBuild)
        iosTestFlightURL = try c.decodeIfPresent(String.self, forKey: .iosTestFlightURL)
        iosUpdateMessage = try c.decodeIfPresent(String.self, forKey: .iosUpdateMessage)
    }

    var updateRemoteHint: AppUpdateChecker.RemoteHint? {
        AppUpdateChecker.remoteHint(
            from: AppDefaultsBlob(
                vehicleDefaultDrivers: vehicleDefaultDrivers,
                iosLatestVersion: iosLatestVersion,
                iosLatestBuild: iosLatestBuild,
                iosTestFlightURL: iosTestFlightURL,
                iosUpdateMessage: iosUpdateMessage
            )
        )
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
        fuelOpeningStockLiters: nil,
        vehicleDefaultDrivers: [:],
        vehicleCatalog: []
    )
}

struct VehicleCatalogRow: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let defaultDriverId: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case defaultDriverId = "default_driver_id"
        case sortOrder = "sort_order"
    }

    init(id: String, name: String, defaultDriverId: String?, sortOrder: Int) {
        self.id = id
        self.name = name
        self.defaultDriverId = defaultDriverId
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        defaultDriverId = try c.decodeIfPresent(String.self, forKey: .defaultDriverId)
        if let i = try c.decodeIfPresent(Int.self, forKey: .sortOrder) {
            sortOrder = i
        } else if let d = try c.decodeIfPresent(Double.self, forKey: .sortOrder) {
            sortOrder = Int(d)
        } else {
            sortOrder = 0
        }
    }
}

/// Nested JSON in `app_settings.app_defaults`.
struct AppDefaultsBlob: Decodable, Sendable, Equatable {
    let vehicleDefaultDrivers: [String: String]?
    /// Soft update channel for iOS TestFlight (optional).
    let iosLatestVersion: String?
    let iosLatestBuild: String?
    let iosTestFlightURL: String?
    let iosUpdateMessage: String?

    enum CodingKeys: String, CodingKey {
        case vehicleDefaultDrivers
        case iosLatestVersion
        case iosLatestBuild
        case iosTestFlightURL
        case iosUpdateMessage
    }

    init(
        vehicleDefaultDrivers: [String: String]? = nil,
        iosLatestVersion: String? = nil,
        iosLatestBuild: String? = nil,
        iosTestFlightURL: String? = nil,
        iosUpdateMessage: String? = nil
    ) {
        self.vehicleDefaultDrivers = vehicleDefaultDrivers
        self.iosLatestVersion = iosLatestVersion
        self.iosLatestBuild = iosLatestBuild
        self.iosTestFlightURL = iosTestFlightURL
        self.iosUpdateMessage = iosUpdateMessage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let direct = try? c.decodeIfPresent([String: String].self, forKey: .vehicleDefaultDrivers) {
            vehicleDefaultDrivers = direct
        } else if let raw = try? c.decodeIfPresent([String: FlexibleStringValue].self, forKey: .vehicleDefaultDrivers) {
            vehicleDefaultDrivers = raw.mapValues(\.value)
        } else {
            vehicleDefaultDrivers = nil
        }
        iosLatestVersion = Self.flexString(c, key: .iosLatestVersion)
        iosLatestBuild = Self.flexString(c, key: .iosLatestBuild)
        iosTestFlightURL = Self.flexString(c, key: .iosTestFlightURL)
        iosUpdateMessage = Self.flexString(c, key: .iosUpdateMessage)
    }

    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) {
            return String(n)
        }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) {
            return String(Int(d))
        }
        return nil
    }
}

struct FuelStock: Codable, Sendable, Equatable {
    let diesel: Double?
    let benzine: Double?
    let dieselReserve: Double?
    let benzineReserve: Double?

    enum CodingKeys: String, CodingKey {
        case diesel = "Diesel"
        case benzine = "Benzine"
        case dieselReserve = "DieselReserve"
        case benzineReserve = "BenzineReserve"
    }
}

struct AppSettingsRow: Decodable, Sendable {
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
    let appDefaults: AppDefaultsBlob?

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
        case appDefaults = "app_defaults"
    }

    func toAppSettings(vehicleCatalog: [VehicleCatalogRow] = []) -> AppSettings {
        let catalogCars = vehicleCatalog
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let carsList = catalogCars.isEmpty ? (cars ?? []) : catalogCars
        var drivers = appDefaults?.vehicleDefaultDrivers ?? [:]
        if !vehicleCatalog.isEmpty {
            var fromCatalog: [String: String] = [:]
            for row in vehicleCatalog {
                let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let driver = row.defaultDriverId?.trimmingCharacters(in: .whitespacesAndNewlines), !driver.isEmpty else { continue }
                fromCatalog[name] = driver
            }
            if !fromCatalog.isEmpty { drivers = fromCatalog }
        }
        return AppSettings(
            appName: appName ?? "Goldenmole",
            appSubtext: appSubtext,
            appIcon: appIcon,
            cars: carsList,
            jobDescriptions: jobDescriptions ?? [],
            incomeTypes: IncomeTypes.visible(incomeTypes ?? []),
            expenseTypes: expenseTypes ?? [],
            maintenanceTypes: maintenanceTypes ?? [],
            locations: locations ?? [],
            landGroups: landGroups ?? [],
            employeePositions: employeePositions,
            fuelOpeningStockLiters: fuelOpeningStock,
            vehicleDefaultDrivers: drivers,
            vehicleCatalog: vehicleCatalog,
            iosLatestVersion: appDefaults?.iosLatestVersion,
            iosLatestBuild: appDefaults?.iosLatestBuild,
            iosTestFlightURL: appDefaults?.iosTestFlightURL,
            iosUpdateMessage: appDefaults?.iosUpdateMessage
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
