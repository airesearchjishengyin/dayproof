import AppKit

/// A pet pack backed by a spritesheet (pet.json + image), e.g. the Codex/petdex
/// pet format. Sliced at load time into clips (one per sheet row); each clip is
/// a separate animation the user can bind to a state.
struct ImagePetPack: Identifiable {
    let id: String
    let displayName: String
    let description: String?
    let clips: [[NSImage]]
    let directory: URL

    var clipCount: Int { clips.count }

    func clip(_ index: Int) -> [NSImage] {
        guard !clips.isEmpty else { return [] }
        return clips[min(max(index, 0), clips.count - 1)]
    }
}

private struct PetManifest: Decodable {
    let id: String
    let displayName: String
    let description: String?
    let spritesheetPath: String
}

/// Loads a spritesheet pet pack and slices its frames by detecting the
/// transparent gutters between cells, so no grid metadata is required.
enum SpriteSlicer {
    /// Reads only the pack id from a directory's manifest, without slicing the
    /// spritesheet. Lets the store pick the prioritised pack to load first.
    static func manifestID(directory: URL) -> String? {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PetManifest.self, from: data)
        else { return nil }
        return manifest.id
    }

    static func loadPack(directory: URL) -> ImagePetPack? {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PetManifest.self, from: data)
        else { return nil }

        let sheetURL = directory.appendingPathComponent(manifest.spritesheetPath)
        guard let nsImage = NSImage(contentsOf: sheetURL) else { return nil }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }

        let clips = slice(cg).map { row in
            row.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        guard !clips.isEmpty else { return nil }
        return ImagePetPack(id: manifest.id, displayName: manifest.displayName,
                            description: manifest.description, clips: clips, directory: directory)
    }

    /// Slices a spritesheet into clips (one per sheet row) using alpha gutter
    /// detection, so no grid metadata is required. Columns are detected within
    /// each row, so ragged sheets (rows with different frame counts or unaligned
    /// columns, e.g. AI-generated sheets) slice correctly. Uniform grids are
    /// unaffected: every row finds the same columns.
    static func slice(_ image: CGImage, alphaThreshold: UInt8 = 16) -> [[CGImage]] {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let data = pixelData(image, width: w, height: h) else { return [] }

        var rowHas = [Bool](repeating: false, count: h)
        data.withUnsafeBufferPointer { buf in
            for y in 0..<h {
                let rowStart = y * w * 4
                for x in 0..<w where buf[rowStart + x * 4 + 3] > alphaThreshold {
                    rowHas[y] = true
                    break
                }
            }
        }
        let rowBands = segments(rowHas)
        guard !rowBands.isEmpty else { return [] }

        var clips: [[CGImage]] = []
        data.withUnsafeBufferPointer { buf in
            for row in rowBands {
                var colHas = [Bool](repeating: false, count: w)
                for y in row.lower..<row.upper {
                    let rowStart = y * w * 4
                    for x in 0..<w where buf[rowStart + x * 4 + 3] > alphaThreshold {
                        colHas[x] = true
                    }
                }
                var clip: [CGImage] = []
                for col in segments(colHas) {
                    let rect = CGRect(x: col.lower, y: row.lower,
                                      width: col.upper - col.lower, height: row.upper - row.lower)
                    guard let cropped = image.cropping(to: rect) else { continue }
                    let fw = Int(rect.width), fh = Int(rect.height)
                    let space = CGColorSpaceCreateDeviceRGB()
                    let info = CGImageAlphaInfo.premultipliedLast.rawValue
                    guard let ctx = CGContext(data: nil, width: fw, height: fh,
                                             bitsPerComponent: 8, bytesPerRow: fw * 4,
                                             space: space, bitmapInfo: info) else { continue }
                    ctx.draw(cropped, in: CGRect(origin: .zero, size: CGSize(width: fw, height: fh)))
                    guard let frame = ctx.makeImage() else { continue }
                    clip.append(frame)
                }
                if !clip.isEmpty { clips.append(clip) }
            }
        }
        return clips
    }

    private static func pixelData(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = data.withUnsafeMutableBytes({ ptr -> CGContext? in
            CGContext(data: ptr.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: space, bitmapInfo: info)
        }) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private static func segments(_ occupancy: [Bool]) -> [(lower: Int, upper: Int)] {
        var result: [(Int, Int)] = []
        var start: Int?
        for (i, filled) in occupancy.enumerated() {
            if filled, start == nil { start = i }
            else if !filled, let s = start { result.append((s, i)); start = nil }
        }
        if let s = start { result.append((s, occupancy.count)) }
        return result
    }
}
