import Foundation
import CoreGraphics

// Icon Composer's material fill overrides SVG strokes. Outline the kit's exact
// centreline with CoreGraphics so its rounded waveform remains an open impulse.
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let expression = try NSRegularExpression(pattern: #"\bd="([^"]+)""#)
let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source))!
let data = String(source[Range(match.range(at: 1), in: source)!])
let lexer = try NSRegularExpression(pattern: #"[A-Za-z]|-?\d+(?:\.\d+)?"#)
let tokens = lexer.matches(in: data, range: NSRange(data.startIndex..., in: data)).map {
    String(data[Range($0.range, in: data)!])
}
var index = 0
func number() -> CGFloat {
    defer { index += 1 }
    return CGFloat(Double(tokens[index])!)
}
let path = CGMutablePath()
while index < tokens.count {
    let command = tokens[index]
    index += 1
    switch command {
    case "M": path.move(to: CGPoint(x: number(), y: number()))
    case "H": path.addLine(to: CGPoint(x: number(), y: path.currentPoint.y))
    case "C":
        let first = CGPoint(x: number(), y: number())
        let second = CGPoint(x: number(), y: number())
        let end = CGPoint(x: number(), y: number())
        path.addCurve(to: end, control1: first, control2: second)
    default: fatalError("Unsupported brand path command: \(command)")
    }
}
let outline = path.copy(strokingWithWidth: 20, lineCap: .round, lineJoin: .round, miterLimit: 10)
func point(_ value: CGPoint) -> String { String(format: "%.5f %.5f", value.x, value.y) }
var commands: [String] = []
outline.applyWithBlock { element in
    let item = element.pointee
    switch item.type {
    case .moveToPoint: commands.append("M" + point(item.points[0]))
    case .addLineToPoint: commands.append("L" + point(item.points[0]))
    case .addQuadCurveToPoint: commands.append("Q" + point(item.points[0]) + " " + point(item.points[1]))
    case .addCurveToPoint: commands.append("C" + point(item.points[0]) + " " + point(item.points[1]) + " " + point(item.points[2]))
    case .closeSubpath: commands.append("Z")
    @unknown default: fatalError("Unknown outline element")
    }
}
print("""
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><g transform="translate(128 272) scale(3)"><path fill="#BCEBD9" d="\(commands.joined(separator: " "))"/></g></svg>
""")
