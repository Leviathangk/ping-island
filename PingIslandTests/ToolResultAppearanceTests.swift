import AppKit
import SwiftUI
import XCTest
@testable import Ping_Island

@MainActor
final class ToolResultAppearanceTests: XCTestCase {
    func testExpandedToolResultsHaveVisibleNeutralTextInBothAppearances() throws {
        let results: [(String, ToolResultData)] = [
            ("read", .read(ReadResult(
                filePath: "/synthetic/workspace/example.swift", content: "let answer = 42\nprint(answer)",
                numLines: 2, startLine: 1, totalLines: 2
            ))),
            ("bash", .bash(BashResult(
                stdout: "Build completed successfully\nAll checks passed", stderr: "",
                interrupted: false, isImage: false, returnCodeInterpretation: "Exit code 0",
                backgroundTaskId: nil
            ))),
            ("glob", .glob(GlobResult(
                filenames: ["Sources/example.swift", "Tests/exampleTests.swift"],
                durationMs: 1, numFiles: 2, truncated: false
            ))),
            ("todo", .todoWrite(TodoWriteResult(
                oldTodos: [], newTodos: [TodoItem(
                    content: "Review the generated tool output", status: "pending", activeForm: nil
                )]
            ))),
            ("edit-header", .edit(EditResult(
                filePath: "/synthetic/workspace/example.swift", oldString: "unchanged",
                newString: "unchanged", replaceAll: false, userModified: false, structuredPatch: nil
            ))),
            ("write", .write(WriteResult(
                type: .create, filePath: "/synthetic/workspace/example.swift",
                content: "let answer = 42", structuredPatch: nil
            ))),
            ("generic", .generic(GenericResult(rawContent: "The tool returned a readable result", rawData: nil)))
        ]
        let themes = [
            ExperienceThemeRegistry.theme(for: .standard),
            ExperienceThemeRegistry.theme(for: .macOS),
            ExperienceThemeRegistry.theme(for: .pixel, pixelPalette: .arcadeNeon),
            ExperienceThemeRegistry.theme(for: .pixel, pixelPalette: .gameBoyOlive)
        ]

        for theme in themes {
            for scheme in [ColorScheme.light, .dark] {
                for (name, result) in results {
                    let tool = ToolCallItem(
                        name: name, input: [:], status: .success, result: nil,
                        structuredResult: result, subagentTools: []
                    )
                    try assertVisibleNeutralText(
                        ToolResultContent(tool: tool), name: name, theme: theme, scheme: scheme
                    )
                }
                try assertVisibleNeutralText(
                    DiffLineView(line: " unchanged patch context"), name: "patch-context",
                    theme: theme, scheme: scheme
                )
                for (name, line) in [("added-patch", "+added code line"), ("removed-patch", "-removed code line")] {
                    try assertVisibleNeutralText(
                        DiffLineView(line: line), name: name, theme: theme, scheme: scheme
                    )
                }
            }
        }
    }

    private func assertVisibleNeutralText<Content: View>(
        _ content: Content, name: String, theme: IslandExperienceTheme, scheme: ColorScheme
    ) throws {
        let renderer = ImageRenderer(content:
            content
                .padding(12)
                .frame(width: 360, height: 110, alignment: .topLeading)
                .background(theme.visual.detachedSurface)
                .environment(\.islandExperienceTheme, theme)
                .environment(\.colorScheme, scheme)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "tool-result-\(name)-\(theme.id.rawValue)-\(String(describing: theme.pixelPaletteID))-\(scheme)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let surface = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        let surfaceLuminance = luminance(surface)
        var visibleTextPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let pixelLuminance = luminance(pixel)
                let contrast = (max(surfaceLuminance, pixelLuminance) + 0.05)
                    / (min(surfaceLuminance, pixelLuminance) + 0.05)
                if contrast >= 3 {
                    visibleTextPixels += 1
                }
            }
        }
        // Empty renders and faint container fills cannot pass by themselves,
        // unlike a layout-only assertion.
        XCTAssertGreaterThan(visibleTextPixels, 50, "Unreadable \(name) / \(theme.id) / \(scheme)")
    }

    private func luminance(_ color: NSColor) -> Double {
        let channels = [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
        let linear = channels.map { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
