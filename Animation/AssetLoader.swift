import AppKit
import SpriteKit

struct AnimationAssets {
    let idleTextures: [SKTexture]
    let shootTextures: [SKTexture]
    let impactTextures: [SKTexture]
    let zombieTextures: [SKTexture]
    let projectileTexture: SKTexture

    static func load(bundle: Bundle = .main) -> AnimationAssets {
        AnimationAssets(
            idleTextures: loadSequence(prefix: "idle", count: 12, subdirectory: "assets/peashooter/idle", bundle: bundle),
            shootTextures: loadSequence(prefix: "shoot", count: 11, subdirectory: "assets/peashooter/shoot", bundle: bundle),
            impactTextures: loadSequence(prefix: "impact", count: 4, subdirectory: "assets/impact", bundle: bundle),
            zombieTextures: loadSequence(prefix: "zombie", count: 16, subdirectory: "assets/zombies/walk", bundle: bundle),
            projectileTexture: loadTexture(name: "projectile_01", subdirectory: "assets/projectile", bundle: bundle)
                ?? SKTexture(image: fallbackImage(color: .systemGreen, size: NSSize(width: 64, height: 64)))
        )
    }

    private static func loadSequence(
        prefix: String,
        count: Int,
        subdirectory: String,
        bundle: Bundle
    ) -> [SKTexture] {
        (1...count).compactMap { index in
            loadTexture(
                name: String(format: "%@_%02d", prefix, index),
                subdirectory: subdirectory,
                bundle: bundle
            )
        }
    }

    private static func loadTexture(name: String, subdirectory: String, bundle: Bundle) -> SKTexture? {
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: subdirectory),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func fallbackImage(color: NSColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
