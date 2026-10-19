//
//  Veil8Parameters.swift
//  Veil8
//
//  Created by Ritesh Pakala on 10/19/26.
//  Copyright © 2026 Rao Studios. All rights reserved.
//
//  What rgb-veil8 is made of: how many one-bit measurements a pixel gets, how wide its window is,
//  how coarse the step is, and which sixteen letters its word is written with. `.standard` is
//  rgb-veil8; anything else is an experiment (Veil's `calibrate` sweeps them) and not the format.
//

import Foundation

public struct Veil8Parameters: Sendable, Equatable {
    /// Bits per pixel; a multiple of four, since a word is whole digits of four bits.
    public var measurements: Int
    /// The window is (2·radius + 1)² pixels.
    public var radius: Int
    /// Grey levels per unit of weight norm. Larger is steadier under re-encoding and says more
    /// about the pixels; smaller is the reverse.
    public var step: Int
    /// The sixteen characters a word's digits are written with, lowest value first.
    public var digits: String

    /// What rgb-veil8 writes with: every two-letter word is one token for voyage-4-nano, the
    /// embedder Veil measures with (SPEC.md, to be added later: "Why letters").
    public static let letters = "cdefhiklmnoprstw"
    public static let hexDigits = "0123456789abcdef"

    public init(measurements: Int = 8, radius: Int = 2, step: Int = 32, digits: String = Veil8Parameters.letters) {
        self.measurements = max(4, (measurements + 3) / 4 * 4)
        self.radius = max(0, radius)
        self.step = max(1, step)
        self.digits = Set(digits.utf8).count == 16 && digits.utf8.count == 16 ? digits : Veil8Parameters.letters
    }

    /// What `rgb-veil8` names: 8 measurements, a 5×5 window, step 32, the letters.
    public static let standard = Veil8Parameters()
}
