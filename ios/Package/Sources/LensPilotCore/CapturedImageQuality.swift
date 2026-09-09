import Foundation

public struct CapturedImageQuality: Codable, Equatable, Sendable {
    public let sharpness: Double
    public let exposure: Double

    public init(sharpness: Double, exposure: Double) {
        self.sharpness = sharpness
        self.exposure = exposure
    }

    public var isValid: Bool {
        sharpness.isFinite && exposure.isFinite
            && (0...1).contains(sharpness) && (0...1).contains(exposure)
    }

    // Relative detail/clipping heuristics on equally downsampled grayscale images.
    public static func measure(luminance: [UInt8], width: Int, height: Int) -> Self? {
        guard width >= 3, height >= 3, width <= 512, height <= 512,
              luminance.count == width * height else { return nil }
        var sum = 0.0
        var squared = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let laplacian = (Double(luminance[i-1]) + Double(luminance[i+1])
                    + Double(luminance[i-width]) + Double(luminance[i+width])
                    - 4 * Double(luminance[i])) / 255
                sum += laplacian
                squared += laplacian * laplacian
            }
        }
        let count = Double((width - 2) * (height - 2))
        let variance = max(0, squared / count - pow(sum / count, 2))
        let clipped = luminance.filter { $0 <= 5 || $0 >= 250 }.count
        return Self(sharpness: variance / (variance + 0.0025),
                    exposure: 1 - Double(clipped) / Double(luminance.count))
    }
}
