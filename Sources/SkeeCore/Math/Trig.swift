#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Thin wrappers so the rest of the core reads cleanly and only this file
// knows where libm comes from.
@inline(__always) func _sin(_ x: Double) -> Double { sin(x) }
@inline(__always) func _cos(_ x: Double) -> Double { cos(x) }
@inline(__always) func _atan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) }
@inline(__always) func _log(_ x: Double) -> Double { log(x) }

public func degrees(_ d: Double) -> Double { d * .pi / 180 }
public func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { min(max(x, lo), hi) }
