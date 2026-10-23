import SwiftUI
import ARKit
import CoreGraphics

// Live LiDAR depth for the scanner home: proof that the sensor works before a family walks through a scan.
// - Only ARKit's sceneDepth is read; no RGB frame, depth frame or world map is stored or leaves the phone.
// - The session runs only while the preview is visible and is paused before RoomPlan takes the camera.

@MainActor
final class LiDARDepthPreview: NSObject, ObservableObject {
    struct Sample: @unchecked Sendable {
        let image: CGImage
        let centerMeters: Double?
        let points: Int
        let confidentShare: Double
    }

    @Published private(set) var sample: Sample?
    @Published private(set) var running = false
    @Published private(set) var interrupted = false

    static var isSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    private var session: ARSession?
    private var processor: DepthFrameProcessor?
    /// A frame rendered after stop() must not reappear; each run has its own generation.
    private var generation = 0

    func start() {
        guard Self.isSupported, !running else { return }
        generation += 1
        let session = ARSession()
        let processor = DepthFrameProcessor(generation: generation, owner: self)
        session.delegate = processor
        session.delegateQueue = DispatchQueue(label: "dryrun.lidar-depth", qos: .userInitiated)
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        self.session = session
        self.processor = processor
        interrupted = false
        running = true
    }

    func stop() {
        generation += 1
        session?.pause()
        session = nil
        processor = nil
        running = false
        sample = nil
    }

    fileprivate func publish(_ sample: Sample, generation: Int) {
        guard generation == self.generation, running else { return }
        self.sample = sample
    }

    fileprivate func failed(generation: Int) {
        guard generation == self.generation else { return }
        stop()
        interrupted = true
    }
}

private final class DepthFrameProcessor: NSObject, ARSessionDelegate, @unchecked Sendable {
    let generation: Int
    weak var owner: LiDARDepthPreview?
    /// Touched only on the session's delegate queue.
    private var lastRender: TimeInterval = 0

    init(generation: Int, owner: LiDARDepthPreview) { self.generation = generation; self.owner = owner }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // ~8 renders a second is plenty for a preview and keeps ARKit from holding on to frames.
        guard frame.timestamp - lastRender > 0.12, let depth = frame.sceneDepth else { return }
        lastRender = frame.timestamp
        guard let sample = Self.render(depth) else { return }
        let origin = generation
        Task { @MainActor [weak owner] in owner?.publish(sample, generation: origin) }
    }

    func session(_ session: ARSession, didFailWithError error: Error) { fail() }
    func sessionWasInterrupted(_ session: ARSession) { fail() }

    private func fail() {
        let origin = generation
        Task { @MainActor [weak owner] in owner?.failed(generation: origin) }
    }

    /// False-colors the depth map (near = warm, far = cool) and reads the distance at its center.
    static func render(_ depth: ARDepthData) -> LiDARDepthPreview.Sample? {
        let map = depth.depthMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32,
              let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        var confident = 0
        if let confidence = depth.confidenceMap {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            if let cBase = CVPixelBufferGetBaseAddress(confidence) {
                let cRow = CVPixelBufferGetBytesPerRow(confidence)
                for y in 0..<height {
                    let row = cBase.advanced(by: y * cRow).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width where row[x] == UInt8(ARConfidenceLevel.high.rawValue) { confident += 1 }
                }
            }
            CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
        }

        let near: Float = 0.3, far: Float = 5
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let meters = row[x]
                let t = meters.isFinite ? min(max((meters - near) / (far - near), 0), 1) : 1
                let (r, g, b) = color(Double(t))
                let i = (y * width + x) * 4
                pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b
            }
        }
        let center = base.advanced(by: (height / 2) * rowBytes).assumingMemoryBound(to: Float32.self)[width / 2]

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return .init(image: image, centerMeters: center.isFinite && center > 0 ? Double(center) : nil,
                     points: width * height, confidentShare: Double(confident) / Double(max(width * height, 1)))
    }

    /// Red → orange → yellow → green → blue as distance grows.
    static func color(_ t: Double) -> (UInt8, UInt8, UInt8) {
        let stops: [(Double, Double, Double)] = [(0.93, 0.22, 0.18), (0.98, 0.58, 0.16), (0.96, 0.87, 0.25),
                                                 (0.30, 0.75, 0.45), (0.20, 0.45, 0.85), (0.15, 0.20, 0.55)]
        let scaled = t * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2), f = scaled - Double(i)
        let a = stops[i], b = stops[i + 1]
        func mix(_ x: Double, _ y: Double) -> UInt8 { UInt8(max(0, min(255, (x + (y - x) * f) * 255))) }
        return (mix(a.0, b.0), mix(a.1, b.1), mix(a.2, b.2))
    }
}

/// The depth image in portrait (ARKit's buffers are landscape-right) with a center dot.
struct LiDARDepthImage: View {
    let sample: LiDARDepthPreview.Sample

    var body: some View {
        Image(decorative: sample.image, scale: 1, orientation: .right)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 18, height: 18)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

/// The near → far color key shown under the depth image.
struct LiDARDepthLegend: View {
    let near: String
    let far: String

    var body: some View {
        HStack(spacing: 8) {
            Text(near).font(.caption)
            LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.2).map { t in
                let (r, g, b) = DepthLegendColor.rgb(t)
                return Color(red: r, green: g, blue: b)
            }, startPoint: .leading, endPoint: .trailing)
            .frame(height: 10)
            .clipShape(Capsule())
            Text(far).font(.caption)
        }
        .accessibilityHidden(true)
    }
}

private enum DepthLegendColor {
    static func rgb(_ t: Double) -> (Double, Double, Double) {
        let (r, g, b) = DepthFrameProcessor.color(t)
        return (Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }
}
