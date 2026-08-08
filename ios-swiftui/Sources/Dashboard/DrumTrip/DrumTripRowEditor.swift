import SwiftUI

struct DrumTripRowEditor: View {
    @Binding var draft: DrumTripDraft
    let cars: [String]
    let drivers: [Employee]
    let onVehicleSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("รถ")
            Menu {
                ForEach(cars, id: \.self) { car in
                    Button(car) { onVehicleSelected(car) }
                }
            } label: {
                pickerLabel(
                    draft.vehicleId.isEmpty ? "เลือกรถ" : draft.vehicleId,
                    empty: draft.vehicleId.isEmpty
                )
            }

            fieldLabel("คนขับ")
            Menu {
                ForEach(drivers) { emp in
                    Button(emp.displayName) { draft.driverId = emp.id }
                }
            } label: {
                let name = drivers.first(where: { $0.id == draft.driverId })?.displayName
                pickerLabel(name ?? (draft.driverId.isEmpty ? "เลือกคนขับ" : draft.driverId), empty: draft.driverId.isEmpty)
            }

            fieldLabel("ประเภทงาน")
            Picker("workType", selection: $draft.workType) {
                ForEach(DrumTripLogic.WorkType.allCases) { wt in
                    Text(wt.label).tag(wt)
                }
            }
            .pickerStyle(.segmented)

            if draft.workType == .hourly {
                stepperRow(title: "ชั่วโมง", value: $draft.hourlyHours, step: 0.5, range: 0...24)
            }

            fieldLabel("คิดเงิน")
            Picker("billing", selection: $draft.billingMode) {
                ForEach(DrumTripLogic.BillingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                stepperRow(title: "เช้า (เที่ยว)", value: $draft.tripMorning, step: 1, range: 0...999)
                stepperRow(title: "บ่าย (เที่ยว)", value: $draft.tripAfternoon, step: 1, range: 0...999)
            }

            if draft.billingMode == .perTrip {
                stepperRow(title: "คิว / เที่ยว", value: $draft.cubicPerTrip, step: 1, range: 0...99)
                let total = (draft.tripMorning + draft.tripAfternoon) * draft.cubicPerTrip
                Text("รวม \(DrumTripLogic.formatMetric(draft.tripMorning + draft.tripAfternoon)) เที่ยว · \(DrumTripLogic.formatMetric(total)) คิว")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                stepperRow(title: "รวมคิว (เหมา)", value: $draft.lumpSumTotalCubic, step: 1, range: 0...9999)
            }

            fieldLabel("รายละเอียดงาน")
            TextField("เช่น ขนทราย / ชัพพอต", text: $draft.workDetails)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.vehicle.opacity(0.28), lineWidth: 1)
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.inkMuted)
    }

    private func pickerLabel(_ text: String, empty: Bool) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(empty ? AppTheme.inkMuted : AppTheme.ink)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }

    private func stepperRow(
        title: String,
        value: Binding<Double>,
        step: Double,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            HStack(spacing: 10) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.vehicle)
                }
                .buttonStyle(.plain)

                Text(DrumTripLogic.formatMetric(value.wrappedValue))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .frame(minWidth: 44)

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.vehicle)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }
}

struct DrumTripSavedCard: View {
    let transaction: Transaction
    let driverName: String
    let onTap: () -> Void
    let onDelete: () -> Void

    private var split: DrumTripLogic.PeriodSplit {
        DrumTripLogic.periodSplit(transaction)
    }

    private var isLump: Bool {
        DrumTripLogic.BillingMode.from(raw: transaction.tripBillingMode) == .lumpSum
            || ((transaction.cubicPerTrip ?? 0) <= 0 && (transaction.perCarCubic ?? transaction.totalCubic ?? 0) > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text((transaction.vehicleId ?? "").isEmpty ? "—" : (transaction.vehicleId ?? ""))
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 0)
                        Text(isLump ? "เหมา" : "คิดเป็นเที่ยว")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AppTheme.vehicle.opacity(0.15)))
                            .foregroundStyle(AppTheme.vehicle)
                    }

                    Text("คนขับ: \(driverName)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkMuted)

                    Text("เช้า \(DrumTripLogic.formatMetric(split.morning)) · บ่าย \(DrumTripLogic.formatMetric(split.afternoon)) เที่ยว")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    let cubicLine: String = {
                        if isLump {
                            let q = transaction.perCarCubic ?? transaction.totalCubic ?? 0
                            return "เหมา \(DrumTripLogic.formatMetric(q)) คิว"
                        }
                        var cpt = transaction.cubicPerTrip ?? 0
                        if cpt <= 0 {
                            cpt = DrumTripLogic.defaultCubicPerTrip(for: transaction.vehicleId ?? "")
                        }
                        let trips = transaction.perCarTrips ?? transaction.tripCount ?? (split.morning + split.afternoon)
                        let cubic = transaction.perCarCubic ?? transaction.totalCubic ?? (trips * cpt)
                        return "\(DrumTripLogic.formatMetric(trips)) เที่ยว × \(DrumTripLogic.formatMetric(cpt)) = \(DrumTripLogic.formatMetric(cubic)) คิว"
                    }()
                    Text(cubicLine)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)

                    Text(DrumTripLogic.WorkType.from(raw: transaction.workType).label)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack {
                Text("แตะการ์ดเพื่อแก้ไข")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer(minLength: 0)
                Button("ลบ", role: .destructive, action: onDelete)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.vehicle.opacity(0.22), lineWidth: 1)
        )
    }
}
