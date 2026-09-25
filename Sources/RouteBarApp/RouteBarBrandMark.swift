import SwiftUI

struct RouteBarBrandMark: View {
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

      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: origin.x + 12 * scale,
            y: origin.y + 12 * scale,
            width: 40 * scale,
            height: 40 * scale
          )),
        with: .color(Color(red: 0.09, green: 0.25, blue: 0.30)),
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
        with: .color(Color(red: 0.47, green: 0.79, blue: 0.26)),
        style: routeStyle
      )

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
        with: .color(Color(red: 0.18, green: 0.42, blue: 1.0)),
        style: routeStyle
      )

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
        with: .color(Color(red: 1.0, green: 0.44, blue: 0.30)),
        style: routeStyle
      )
    }
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

  private func point(_ x: CGFloat, _ y: CGFloat, origin: CGPoint, scale: CGFloat) -> CGPoint {
    CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
  }
}
