import AppShowcaseCore
import CoreGraphics
import SwiftUI
import Testing

@testable import AppShowcaseUI

@MainActor
@Suite("Row style")
struct RowStyleTests {
    private static let app = ShowcaseApp(
        id: 1, artistID: 2, name: "Name", bundleID: "com.example.name", genre: "Utilities",
        formattedPrice: nil, platform: .iOS, minimumOSVersion: "18.0",
        iconURL: URL(fileURLWithPath: "/dev/null"),
        storeURL: URL(string: "https://apps.apple.com/app/id1")!,
        tagline: "A tagline long enough to measure")

    private static func pixels(of view: some View) throws -> [(r: UInt8, g: UInt8, b: UInt8)] {
        let renderer = ImageRenderer(
            content: view.frame(width: 360).background(Color.white)
                .environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: bytes.count, by: 4).map {
            (bytes[$0], bytes[$0 + 1], bytes[$0 + 2])
        }
    }

    @Test("the tagline draws in the host's second hierarchical level")
    func taglineTakesHostSecondaryLevel() throws {
        let row = ShowcaseRow(
            app: Self.app, tapStyle: .storeLink, attribution: .none, onSelect: { _ in }
        )
        .foregroundStyle(
            Color(red: 1, green: 0, blue: 0),
            Color(red: 0, green: 0, blue: 1),
            Color(red: 0, green: 0.8, blue: 0))

        let secondaryLevel = try Self.pixels(of: row).filter {
            Int($0.b) > Int($0.r) + 60 && Int($0.b) > Int($0.g) + 60
        }
        #expect(secondaryLevel.count > 100)
    }
}
