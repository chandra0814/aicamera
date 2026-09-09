import CoreGraphics
import Foundation
import ImageIO
import LensPilotVision
import XCTest

final class CapturedPhotoAnalyzerTests: XCTestCase {
    func testDecodesRealEncodedImageAndRejectsInvalidData() throws {
        let bytes = Data((0..<64).map { UInt8($0 % 2 == 0 ? 80 : 180) })
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let image = try XCTUnwrap(CGImage(width: 8, height: 8, bitsPerComponent: 8,
            bitsPerPixel: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let quality = try XCTUnwrap(CapturedPhotoAnalyzer().quality(of: encoded as Data))
        XCTAssertTrue(quality.isValid)
        XCTAssertGreaterThan(quality.sharpness, 0)
        XCTAssertNil(CapturedPhotoAnalyzer().quality(of: Data("not an image".utf8)))
    }
}
