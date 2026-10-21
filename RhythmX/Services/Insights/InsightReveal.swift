//  InsightReveal.swift
//  The timeline of the daily insight pull-up, in seconds from the moment the sheet appears: the sheet settles,
//  the text reveals line by line under a soft shimmer, then the hormone curve draws itself, the suggested
//  tags rise in, and the marker glows twice and stays lit. Pure, so every stage is tested, and so screenshots
//  can render any moment (`elapsed(forProgress:)`). With Reduce Motion the view jumps to the end.

import Foundation

struct InsightReveal: Equatable {
    static let settle = 0.35
    static let lineDuration = 0.55
    static let lineStagger = 0.32
    static let curveDuration = 1.3
    static let glowDuration = 1.2
    static let chipsDuration = 0.45

    let lineCount: Int
    /// When the text is fully shown. Streamed text ends when the stream ends.
    let textEnd: Double

    init(lineCount: Int, textEnd: Double? = nil) {
        self.lineCount = max(lineCount, 1)
        self.textEnd = textEnd ?? Self.settle + Double(self.lineCount - 1) * Self.lineStagger + Self.lineDuration
    }

    var curveEnd: Double { textEnd + Self.curveDuration }
    var total: Double { curveEnd + Self.glowDuration }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 0 to 1 for line `index` (0 is the first line).
    func lineProgress(_ index: Int, at t: Double) -> Double {
        if t >= textEnd { return 1 }
        let start = Self.settle + Double(index) * Self.lineStagger
        return Self.clamp((t - start) / Self.lineDuration)
    }

    /// 0 to 1: how much of the curve, left to right, is drawn. Eased out.
    func curveProgress(at t: Double) -> Double {
        if t >= curveEnd { return 1 }
        let x = Self.clamp((t - textEnd) / Self.curveDuration)
        return 1 - pow(1 - x, 2.2)
    }

    /// 0 until the curve is drawn; then two pulses; then 1 (lit) for good.
    func glow(at t: Double) -> Double {
        guard t >= curveEnd else { return 0 }
        guard t < total else { return 1 }
        let x = (t - curveEnd) / Self.glowDuration
        guard x < 1 else { return 1 }
        return max(x * x, pow(sin(2 * .pi * x), 2))
    }

    /// 0 to 1: the suggested tag chips rise in while the curve draws.
    func chipsProgress(at t: Double) -> Double {
        Self.clamp((t - textEnd - Self.curveDuration * 0.3) / Self.chipsDuration)
    }

    /// The moment a fixed animation progress (0 rest, 1 complete) stands for.
    func elapsed(forProgress progress: Double) -> Double { Self.clamp(progress) * total }

    /// How many lines `text` takes, wrapping on words at `charactersPerLine`; the reveal uses the real layout,
    /// this only paces the timeline.
    static func estimatedLines(_ text: String, charactersPerLine: Int) -> Int {
        var lines = 1
        var current = 0
        for word in text.split(separator: " ") {
            let length = word.count
            if current == 0 {
                current = length
            } else if current + 1 + length <= charactersPerLine {
                current += 1 + length
            } else {
                lines += 1
                current = length
            }
        }
        return lines
    }

    /// Where the shimmer sits on a line that is being revealed (0 leading edge, 1 trailing); nil when the line
    /// has not started or is done.
    static func shimmerCenter(lineProgress: Double) -> Double? {
        lineProgress > 0 && lineProgress < 1 ? lineProgress : nil
    }
}
