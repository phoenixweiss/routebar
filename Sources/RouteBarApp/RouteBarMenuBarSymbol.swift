import SwiftUI

struct RouteBarMenuBarSymbol: View {
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 64
      let origin = CGPoint(
        x: (size.width - 64 * scale) / 2,
        y: (size.height - 64 * scale) / 2
      )
      let routeStyle = StrokeStyle(
        lineWidth: 4.5 * scale,
        lineCap: .round,
        lineJoin: .round
      )
      let knockoutStyle = StrokeStyle(
        lineWidth: 6 * scale,
        lineCap: .round,
        lineJoin: .round
      )

      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: origin.x + 12 * scale,
            y: origin.y + 12 * scale,
            width: 40 * scale,
            height: 40 * scale
          )),
        with: .color(.primary),
        lineWidth: 3.333 * scale
      )

      context.stroke(
        routePath(
          origin: origin,
          scale: scale,
          startY: 42,
          firstEndX: 32,
          firstControl: CGPoint(x: 35.5, y: 42),
          secondControl: CGPoint(x: 36.5, y: 32),
          curveEnd: CGPoint(x: 40, y: 32),
          endY: 32
        ),
        with: .color(.primary),
        style: routeStyle
      )

      context.blendMode = .destinationOut
      context.stroke(
        curvePath(
          origin: origin,
          scale: scale,
          start: CGPoint(x: 32, y: 32),
          firstControl: CGPoint(x: 35, y: 37),
          secondControl: CGPoint(x: 37, y: 42),
          end: CGPoint(x: 40, y: 42)
        ),
        with: .color(.black),
        style: knockoutStyle
      )
      context.blendMode = .normal

      context.stroke(
        routePath(
          origin: origin,
          scale: scale,
          startY: 22,
          firstEndX: 24,
          firstControl: CGPoint(x: 29, y: 22),
          secondControl: CGPoint(x: 35, y: 42),
          curveEnd: CGPoint(x: 40, y: 42),
          endY: 42
        ),
        with: .color(.primary),
        style: routeStyle
      )

      context.blendMode = .destinationOut
      context.stroke(
        curvePath(
          origin: origin,
          scale: scale,
          start: CGPoint(x: 24, y: 32),
          firstControl: CGPoint(x: 27.5, y: 32),
          secondControl: CGPoint(x: 28.5, y: 22),
          end: CGPoint(x: 32, y: 22)
        ),
        with: .color(.black),
        style: knockoutStyle
      )
      context.blendMode = .normal

      context.stroke(
        routePath(
          origin: origin,
          scale: scale,
          startY: 32,
          firstEndX: 24,
          firstControl: CGPoint(x: 27.5, y: 32),
          secondControl: CGPoint(x: 28.5, y: 22),
          curveEnd: CGPoint(x: 32, y: 22),
          endY: 22
        ),
        with: .color(.primary),
        style: routeStyle
      )
    }
    .frame(width: 18, height: 18)
    .accessibilityLabel("RouteBar")
  }

  private func routePath(
    origin: CGPoint,
    scale: CGFloat,
    startY: CGFloat,
    firstEndX: CGFloat,
    firstControl: CGPoint,
    secondControl: CGPoint,
    curveEnd: CGPoint,
    endY: CGFloat
  ) -> Path {
    var path = Path()
    path.move(to: point(7, startY, origin: origin, scale: scale))
    path.addLine(to: point(firstEndX, startY, origin: origin, scale: scale))
    path.addCurve(
      to: point(curveEnd.x, curveEnd.y, origin: origin, scale: scale),
      control1: point(firstControl.x, firstControl.y, origin: origin, scale: scale),
      control2: point(secondControl.x, secondControl.y, origin: origin, scale: scale)
    )
    path.addLine(to: point(57, endY, origin: origin, scale: scale))
    return path
  }

  private func curvePath(
    origin: CGPoint,
    scale: CGFloat,
    start: CGPoint,
    firstControl: CGPoint,
    secondControl: CGPoint,
    end: CGPoint
  ) -> Path {
    var path = Path()
    path.move(to: point(start.x, start.y, origin: origin, scale: scale))
    path.addCurve(
      to: point(end.x, end.y, origin: origin, scale: scale),
      control1: point(firstControl.x, firstControl.y, origin: origin, scale: scale),
      control2: point(secondControl.x, secondControl.y, origin: origin, scale: scale)
    )
    return path
  }

  private func point(_ x: CGFloat, _ y: CGFloat, origin: CGPoint, scale: CGFloat) -> CGPoint {
    CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
  }
}
