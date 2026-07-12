import Charts
import SwiftUI

struct DonutChartView: View {
    let slices: [ChartSlice]
    var lineWidth: CGFloat = 28

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 1) }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    let start = slices.prefix(index).reduce(0.0) { $0 + $1.value } / total
                    let end = start + slice.value / total
                    DonutSlice(start: start, end: end)
                        .stroke(Color(hex: slice.colorHex), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .frame(width: size, height: size)
                }
                VStack(spacing: 4) {
                    Text(DashboardAggregations.formatNumber(total))
                        .font(.headline.bold())
                    Text("รวม")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct DonutSlice: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius, startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        return path
    }
}

struct BarChartView: View {
    let labels: [String]
    let values: [Double]
    var barColor: Color = Color(hex: "#3b82f6")

    private var maxValue: Double { max(values.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(zip(labels, values).enumerated()), id: \.offset) { _, pair in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.opacity(0.85))
                        .frame(height: CGFloat(pair.1 / maxValue) * 120)
                    Text(pair.0)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 150)
    }
}

struct LineChartView: View {
    let labels: [String]
    let values: [Double]
    var lineColor: Color = Color(hex: "#3b82f6")

    private struct Point: Identifiable {
        let id: Int
        let label: String
        let value: Double
    }

    var body: some View {
        let points = zip(labels, values).enumerated().map { Point(id: $0.offset, label: $0.element.0, value: $0.element.1) }
        Chart(points) { p in
            LineMark(x: .value("วัน", p.label), y: .value("ค่า", p.value))
                .foregroundStyle(lineColor)
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("วัน", p.label), y: .value("ค่า", p.value))
                .foregroundStyle(lineColor.opacity(0.15))
                .interpolationMethod(.catmullRom)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 180)
    }
}

struct BreakEvenScatterView: View {
    let points: [(income: Double, expense: Double, label: String)]

    private var maxVal: Double {
        let vals = points.flatMap { [$0.income, $0.expense] }
        return max(vals.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad: CGFloat = 28
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: pad, y: h - pad))
                    p.addLine(to: CGPoint(x: w - pad, y: pad))
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                    let x = pad + CGFloat(pt.income / maxVal) * (w - pad * 2)
                    let y = h - pad - CGFloat(pt.expense / maxVal) * (h - pad * 2)
                    Circle()
                        .fill(pt.income >= pt.expense ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
        }
        .frame(height: 220)
        .overlay(alignment: .bottomLeading) {
            Text("รายรับ →").font(.caption2).foregroundStyle(.secondary)
        }
        .overlay(alignment: .topTrailing) {
            Text("↑ รายจ่าย").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    let subtitle: String?
    let accent: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(height: 4)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}
