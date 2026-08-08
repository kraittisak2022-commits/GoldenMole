import SwiftUI

struct AttendanceSandPanel: View {
    @Bindable var session: AttendanceSession
    let employees: [Employee]

    private let poolAccent = Color(red: 0.486, green: 0.302, blue: 1)

    private var pool: [Employee] { session.pool(employees: employees) }
    private var byId: [String: Employee] {
        Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
    }

    private var placedIds: Set<String> {
        var s = Set<String>()
        for b in AttendanceBucket.sandYardBuckets {
            s.formUnion(session.assignments[b] ?? [])
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AttendancePoolCard(
                title: "#รายชื่อพนักงานท่าทราย",
                employees: pool,
                placedIds: placedIds,
                pickedIds: session.pickedIds,
                accent: poolAccent,
                onTap: { session.poolTap($0) },
                onReturnToPool: returnPickedToPool
            )

            ForEach(AttendanceBucket.sandYardBuckets) { bucket in
                AttendanceBucketCard(
                    bucket: bucket,
                    employees: employeesIn(bucket),
                    pickedIds: session.pickedIds,
                    onDropZoneTap: { session.assignToBucket(bucket) },
                    onChipTap: { id in
                        if session.pickedIds.isEmpty {
                            session.togglePick(id)
                        } else {
                            session.assignToBucket(bucket, employeeId: id)
                        }
                    },
                    onRemove: { session.removeFromBuckets($0) }
                )
            }
        }
    }

    private func employeesIn(_ bucket: AttendanceBucket) -> [Employee] {
        let ids = session.assignments[bucket] ?? []
        return ids.compactMap { byId[$0] }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func returnPickedToPool() {
        for id in session.pickedIds {
            session.removeFromBuckets(id)
        }
        session.pickedIds.removeAll()
    }
}

struct AttendanceDriverPanel: View {
    @Bindable var session: AttendanceSession
    let employees: [Employee]

    private let poolAccent = Color(red: 0.937, green: 0.424, blue: 0)

    private var pool: [Employee] { session.pool(employees: employees) }
    private var byId: [String: Employee] {
        Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
    }

    private var placedIds: Set<String> {
        var s = Set<String>()
        for b in AttendanceBucket.driverBuckets {
            s.formUnion(session.assignments[b] ?? [])
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AttendancePoolCard(
                title: "#รายชื่อคนขับรถแม็คโคร",
                employees: pool,
                placedIds: placedIds,
                pickedIds: session.pickedIds,
                accent: poolAccent,
                onTap: { session.poolTap($0) },
                onReturnToPool: returnPickedToPool
            )

            ForEach(AttendanceBucket.driverBuckets) { bucket in
                AttendanceBucketCard(
                    bucket: bucket,
                    employees: employeesIn(bucket),
                    pickedIds: session.pickedIds,
                    onDropZoneTap: { session.assignToBucket(bucket) },
                    onChipTap: { id in
                        if session.pickedIds.isEmpty {
                            session.togglePick(id)
                        } else {
                            session.assignToBucket(bucket, employeeId: id)
                        }
                    },
                    onRemove: { session.removeFromBuckets($0) }
                )
            }
        }
    }

    private func employeesIn(_ bucket: AttendanceBucket) -> [Employee] {
        let ids = session.assignments[bucket] ?? []
        return ids.compactMap { byId[$0] }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func returnPickedToPool() {
        for id in session.pickedIds {
            session.removeFromBuckets(id)
        }
        session.pickedIds.removeAll()
    }
}
