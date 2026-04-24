import ConductorCore
import SwiftUI

struct CirclePlotView: View {
    let title: String
    let subtitle: String
    let labels: [String]
    let point: PlotPosition
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let drawingSize = CGSize(width: size, height: size)

                ZStack {
                    Canvas { context, size in
                        drawGrid(in: &context, size: size)
                        drawMarker(in: &context, size: size)
                    }

                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .position(labelPosition(index: index, size: drawingSize))
                    }
                }
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 330)
        }
        .conductorCardStyle()
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 28, dy: 28)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2

        for scale in [1.0, 0.66, 0.33] {
            var circle = Path()
            let circleRadius = radius * scale
            circle.addEllipse(in: CGRect(
                x: center.x - circleRadius,
                y: center.y - circleRadius,
                width: circleRadius * 2,
                height: circleRadius * 2
            ))
            context.stroke(circle, with: .color(Color.secondary.opacity(0.25)), lineWidth: 1.2)
        }

        let sectorSize = (2.0 * Double.pi) / Double(labels.count)
        for index in labels.indices {
            let angle = Double(index) * sectorSize
            let edgePoint = CGPoint(
                x: center.x + CGFloat(sin(angle)) * radius,
                y: center.y - CGFloat(cos(angle)) * radius
            )

            var line = Path()
            line.move(to: center)
            line.addLine(to: edgePoint)
            context.stroke(line, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1.0)
        }
    }

    private func drawMarker(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 28, dy: 28)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2
        let markerCenter = CGPoint(
            x: center.x + CGFloat(point.normalized.x) * radius,
            y: center.y + CGFloat(point.normalized.y) * radius
        )

        var orbitPath = Path()
        orbitPath.move(to: center)
        orbitPath.addLine(to: markerCenter)
        context.stroke(orbitPath, with: .color(accent.opacity(0.35)), lineWidth: 2.0)

        let haloRect = CGRect(
            x: markerCenter.x - 18,
            y: markerCenter.y - 18,
            width: 36,
            height: 36
        )
        context.fill(Path(ellipseIn: haloRect), with: .color(accent.opacity(0.25)))

        let markerRect = CGRect(
            x: markerCenter.x - 9,
            y: markerCenter.y - 9,
            width: 18,
            height: 18
        )
        context.fill(Path(ellipseIn: markerRect), with: .color(accent))
    }

    private func labelPosition(index: Int, size: CGSize) -> CGPoint {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 28, dy: 28)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2 + 18
        let sectorSize = (2.0 * Double.pi) / Double(labels.count)
        let angle = (Double(index) + 0.5) * sectorSize

        return CGPoint(
            x: center.x + CGFloat(sin(angle)) * radius,
            y: center.y - CGFloat(cos(angle)) * radius
        )
    }
}
