import SwiftUI

/// Original vector cat shared by the desktop pet and the app icon.
struct CatDrawing: View {
    let blink: Bool
    let happy: Bool
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 140
            ctx.scaleBy(x: s, y: s)
            func ellipse(_ rect: CGRect, _ color: Color) { ctx.fill(Path(ellipseIn: rect), with: .color(color)) }
            let fur = Color(red: 0.97, green: 0.86, blue: 0.67)
            let line = Color(red: 0.37, green: 0.29, blue: 0.22)
            ellipse(CGRect(x: 23, y: 123, width: 100, height: 10), .black.opacity(0.10))
            var tail = Path(); tail.move(to: CGPoint(x: 110, y: 109)); tail.addCurve(to: CGPoint(x: 124, y: 85), control1: CGPoint(x: 137, y: 120), control2: CGPoint(x: 140, y: 85))
            ctx.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 13, lineCap: .round))
            ellipse(CGRect(x: 30, y: 68, width: 80, height: 60), fur)
            var ears = Path()
            ears.move(to: CGPoint(x: 29, y: 43)); ears.addLine(to: CGPoint(x: 29, y: 13)); ears.addQuadCurve(to: CGPoint(x: 57, y: 34), control: CGPoint(x: 36, y: 10)); ears.closeSubpath()
            ears.move(to: CGPoint(x: 84, y: 34)); ears.addQuadCurve(to: CGPoint(x: 112, y: 13), control: CGPoint(x: 107, y: 7)); ears.addLine(to: CGPoint(x: 113, y: 47)); ears.closeSubpath()
            ctx.fill(ears, with: .color(fur))
            var inner = Path(); inner.move(to: CGPoint(x: 34, y: 34)); inner.addLine(to: CGPoint(x: 34, y: 21)); inner.addLine(to: CGPoint(x: 48, y: 34)); inner.closeSubpath()
            inner.move(to: CGPoint(x: 94, y: 34)); inner.addLine(to: CGPoint(x: 107, y: 21)); inner.addLine(to: CGPoint(x: 107, y: 38)); inner.closeSubpath()
            ctx.fill(inner, with: .color(Color(red: 0.88, green: 0.62, blue: 0.57)))
            ellipse(CGRect(x: 22, y: 28, width: 98, height: 76), fur)
            ellipse(CGRect(x: 44, y: 82, width: 54, height: 43), .white.opacity(0.35))
            ellipse(CGRect(x: 31, y: 113, width: 31, height: 17), fur)
            ellipse(CGRect(x: 78, y: 113, width: 31, height: 17), fur)
            for x in [48.0, 90.0] {
                if blink || happy {
                    var eye = Path(); eye.move(to: CGPoint(x: x - 5, y: 62)); eye.addQuadCurve(to: CGPoint(x: x + 5, y: 62), control: CGPoint(x: x, y: 56))
                    ctx.stroke(eye, with: .color(line), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                } else {
                    ellipse(CGRect(x: x - 3, y: 55, width: 7, height: 10), line)
                    ellipse(CGRect(x: x - 1, y: 56, width: 2, height: 3), .white)
                }
            }
            ellipse(CGRect(x: 32, y: 69, width: 17, height: 8), .pink.opacity(0.30))
            ellipse(CGRect(x: 94, y: 69, width: 17, height: 8), .pink.opacity(0.30))
            var nose = Path(); nose.move(to: CGPoint(x: 66, y: 67)); nose.addLine(to: CGPoint(x: 75, y: 67)); nose.addLine(to: CGPoint(x: 70.5, y: 72)); nose.closeSubpath()
            ctx.fill(nose, with: .color(line))
            var smile = Path(); smile.move(to: CGPoint(x: 60, y: 74)); smile.addQuadCurve(to: CGPoint(x: 70.5, y: 75), control: CGPoint(x: 65, y: 83)); smile.addQuadCurve(to: CGPoint(x: 81, y: 74), control: CGPoint(x: 76, y: 83))
            ctx.stroke(smile, with: .color(line), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for y in [67.0, 75.0] {
                var whisker = Path(); whisker.move(to: CGPoint(x: 18, y: y - 2)); whisker.addLine(to: CGPoint(x: 32, y: y)); whisker.move(to: CGPoint(x: 109, y: y)); whisker.addLine(to: CGPoint(x: 125, y: y - 2))
                ctx.stroke(whisker, with: .color(line.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            if happy { ctx.draw(Text("✦").font(.system(size: 18)).foregroundColor(.orange), at: CGPoint(x: 125, y: 35)) }
        }
    }
}
