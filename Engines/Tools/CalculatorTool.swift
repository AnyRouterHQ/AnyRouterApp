import Foundation

/// Arithmetic the model should not do in its head. A small hand-written parser: no `NSExpression`, which can trap on bad input.
struct CalculatorTool: BuiltInTool {
    let name = "calculator"
    let title = "Calculator"
    let summary = "Exact arithmetic"
    let description = "Evaluate an arithmetic expression. Supports + - * / % ^, parentheses, sqrt, abs, round, floor, ceil, ln, exp, and the constants pi and e."
    let schema: JSONSchema = #"{"type":"object","properties":{"expression":{"type":"string","description":"For example (12.5 + 7) * 3 / 2"}},"required":["expression"]}"#

    func run(_ arguments: JSONValue) async throws -> String {
        guard let expression = arguments["expression"]?.string, !expression.isEmpty else {
            throw BuiltInToolError("Missing the \"expression\" argument.")
        }
        return Calculator.format(try Calculator.evaluate(expression))
    }
}

enum Calculator {
    static let maxLength = 500
    static let maxDepth = 64

    static func evaluate(_ text: String) throws -> Double {
        guard text.count <= maxLength else { throw BuiltInToolError("The expression is too long.") }
        var parser = Parser(Array(text))
        let value = try parser.expression(depth: 0)
        parser.skipSpaces()
        guard parser.atEnd else { throw BuiltInToolError("Unexpected \"\(parser.current)\" in the expression.") }
        guard value.isFinite else { throw BuiltInToolError("The result is not a finite number.") }
        return value
    }

    /// Whole numbers print without a decimal point; others keep up to 12 significant digits.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(format: "%.12g", value)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool { index >= chars.count }
        var current: Character { chars[index] }

        mutating func skipSpaces() {
            while !atEnd, current == " " || current == "\t" || current == "\n" { index += 1 }
        }

        mutating func accept(_ char: Character) -> Bool {
            skipSpaces()
            guard !atEnd, current == char else { return false }
            index += 1
            return true
        }

        mutating func expression(depth: Int) throws -> Double {
            guard depth < Calculator.maxDepth else { throw BuiltInToolError("The expression is nested too deeply.") }
            var value = try term(depth: depth)
            while true {
                if accept("+") { value += try term(depth: depth) } else if accept("-") { value -= try term(depth: depth) } else { return value }
            }
        }

        mutating func term(depth: Int) throws -> Double {
            var value = try unary(depth: depth)
            while true {
                if accept("*") {
                    value *= try unary(depth: depth)
                } else if accept("/") {
                    let divisor = try unary(depth: depth)
                    guard divisor != 0 else { throw BuiltInToolError("Division by zero.") }
                    value /= divisor
                } else if accept("%") {
                    let divisor = try unary(depth: depth)
                    guard divisor != 0 else { throw BuiltInToolError("Division by zero.") }
                    value = value.truncatingRemainder(dividingBy: divisor)
                } else {
                    return value
                }
            }
        }

        mutating func unary(depth: Int) throws -> Double {
            if accept("-") { return -(try unary(depth: depth + 1)) }
            if accept("+") { return try unary(depth: depth + 1) }
            return try power(depth: depth)
        }

        mutating func power(depth: Int) throws -> Double {
            let base = try primary(depth: depth)
            if accept("^") {
                let exponent = try unary(depth: depth + 1)
                return pow(base, exponent)
            }
            return base
        }

        mutating func primary(depth: Int) throws -> Double {
            skipSpaces()
            guard !atEnd else { throw BuiltInToolError("The expression ends too early.") }
            if accept("(") {
                let value = try expression(depth: depth + 1)
                guard accept(")") else { throw BuiltInToolError("Missing a closing parenthesis.") }
                return value
            }
            if current.isNumber || current == "." { return try number() }
            if current.isLetter { return try named(depth: depth) }
            throw BuiltInToolError("Unexpected \"\(current)\" in the expression.")
        }

        mutating func number() throws -> Double {
            let start = index
            while !atEnd, current.isNumber || current == "." { index += 1 }
            guard let value = Double(String(chars[start..<index])) else { throw BuiltInToolError("Not a number: \(String(chars[start..<index])).") }
            return value
        }

        mutating func named(depth: Int) throws -> Double {
            let start = index
            while !atEnd, current.isLetter || current.isNumber { index += 1 }
            let name = String(chars[start..<index]).lowercased()
            switch name {
            case "pi": return Double.pi
            case "e": return M_E
            default: break
            }
            guard accept("(") else { throw BuiltInToolError("Unknown name: \(name).") }
            let argument = try expression(depth: depth + 1)
            guard accept(")") else { throw BuiltInToolError("Missing a closing parenthesis.") }
            switch name {
            case "sqrt":
                guard argument >= 0 else { throw BuiltInToolError("The square root of a negative number is not real.") }
                return argument.squareRoot()
            case "abs": return abs(argument)
            case "round": return argument.rounded()
            case "floor": return argument.rounded(.down)
            case "ceil": return argument.rounded(.up)
            case "ln":
                guard argument > 0 else { throw BuiltInToolError("The logarithm needs a positive number.") }
                return log(argument)
            case "exp": return exp(argument)
            default: throw BuiltInToolError("Unknown function: \(name).")
            }
        }
    }
}
