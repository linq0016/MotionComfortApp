import CoreGraphics

public func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
    min(max(value, minimum), maximum)
}

public func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
    min(max(value, minimum), maximum)
}

public func lerp(_ start: Double, _ end: Double, amount: Double) -> Double {
    start + ((end - start) * amount)
}

public func lerp(_ start: CGFloat, _ end: CGFloat, amount: CGFloat) -> CGFloat {
    start + ((end - start) * amount)
}
