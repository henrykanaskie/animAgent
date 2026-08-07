import Foundation
import Metal
import SpriteKit
import SpriteRoomScene

/// Renders the scene to PNGs without a window.
///
/// A window is the real target, but "the nameplate is legible at this zoom" is
/// not a claim anyone should take on trust, and it cannot be checked from a
/// unit test. This renders the actual `SKScene` through `SKRenderer` at a fixed
/// simulated clock, so what lands in the PNG is what SpriteKit would draw.
@MainActor
final class OffscreenRenderer {

    enum SetupError: Error, CustomStringConvertible {
        case noMetalDevice
        case noCommandQueue
        case noTexture

        var description: String {
            switch self {
            case .noMetalDevice: return "no Metal device — cannot render offscreen"
            case .noCommandQueue: return "could not create a Metal command queue"
            case .noTexture: return "could not create the render target texture"
            }
        }
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let renderer: SKRenderer
    private let target: MTLTexture
    let pixelSize: CGSize

    init(scene: RoomScene, width: Int, height: Int) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw SetupError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw SetupError.noCommandQueue }
        self.device = device
        self.queue = queue
        self.pixelSize = CGSize(width: width, height: height)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor) else {
            throw SetupError.noTexture
        }
        self.target = target

        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        renderer.showsNodeCount = false
        self.renderer = renderer
        scene.setViewport(CGSize(width: width, height: height))
    }

    /// Advances the scene's clock. Actions run here, so a walk cycle that takes
    /// two seconds of fixture time takes two seconds of this clock.
    func update(atTime time: TimeInterval) {
        renderer.update(atTime: time)
    }

    /// Draws one frame into the render target.
    ///
    /// **Must be called every simulated frame, not only at the frames we keep.**
    /// `SKRenderer.update(atTime:)` on its own does not advance the action
    /// tree — characters stay wherever they spawned and no animation ever
    /// plays. Rendering each step is what makes the offscreen clock behave like
    /// a real one, which is the whole point of rendering offscreen at all.
    func renderFrame() {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let buffer = queue.makeCommandBuffer() else { return }
        renderer.render(
            withViewport: CGRect(origin: .zero, size: pixelSize),
            commandBuffer: buffer,
            renderPassDescriptor: pass)
        buffer.commit()
        buffer.waitUntilCompleted()
    }

    func snapshot() -> Bitmap? {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let buffer = queue.makeCommandBuffer() else { return nil }
        renderer.render(
            withViewport: CGRect(origin: .zero, size: pixelSize),
            commandBuffer: buffer,
            renderPassDescriptor: pass)
        buffer.commit()
        buffer.waitUntilCompleted()

        let width = target.width
        let height = target.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        raw.withUnsafeMutableBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            target.getBytes(
                base, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        var bitmap = Bitmap(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                // Metal gives BGRA; the bitmap is RGBA.
                bitmap.set(x, y, Bitmap.RGBA(
                    raw[index + 2], raw[index + 1], raw[index], raw[index + 3]))
            }
        }
        return bitmap
    }

    @discardableResult
    func write(to url: URL) -> Bool {
        guard let bitmap = snapshot() else { return false }
        return PixelImage.writePNG(bitmap, to: url)
    }
}
