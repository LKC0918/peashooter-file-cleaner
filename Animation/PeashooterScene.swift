import AppKit
import SpriteKit

enum ExperienceLayout {
    static let shooterSize = CGSize(width: 68, height: 68)
    static let zombieSize = CGSize(width: 63, height: 96)
    static let stretcherSize = CGSize(width: 190, height: 45)
    static let defaultFinderIconSize = CGSize(width: 72, height: 72)
    static let shooterTargetCenterDistance: CGFloat = 82
    // Muzzle sits at the dark barrel center of the art, measured on the
    // 512px sheet: idle (~389,128) / shoot (~394,116) -> ~(+24,+24) at 90pt.
    // Converted to the current node size so the pea always leaves the barrel.
    static let shooterMuzzleUnitOffset = CGPoint(x: 0.26, y: 0.26)
    static let projectileSize = CGSize(width: 20, height: 20)
    static let impactSize = CGSize(width: 60, height: 60)
    static let crackOutlineWidth: CGFloat = 7
    static let crackLineWidth: CGFloat = 3.4

    static var shooterMuzzleOffset: CGPoint {
        CGPoint(
            x: shooterSize.width * shooterMuzzleUnitOffset.x,
            y: shooterSize.height * shooterMuzzleUnitOffset.y
        )
    }

    static func normalizedFinderIconSize(_ proposedSize: CGSize?) -> CGSize {
        guard let proposedSize, proposedSize.width > 0, proposedSize.height > 0 else {
            return defaultFinderIconSize
        }
        let side = min(96, max(56, min(proposedSize.width, proposedSize.height)))
        return CGSize(width: side, height: side)
    }
}

@MainActor
final class PeashooterScene: SKScene {
    private let assets: AnimationAssets
    private let shooterNode: SKSpriteNode
    private let fileNode: SKSpriteNode
    private let fileCaption = SKLabelNode(fontNamed: "PingFang SC Semibold")
    private let damageOverlayNode = SKNode()
    private let crackOutlineNode = SKShapeNode()
    private let crackNode = SKShapeNode()
    private var pendingFinalProjectile: SKSpriteNode?

    private var targetPoint: CGPoint = .zero
    private var shooterRestingPoint: CGPoint = .zero
    private var targetIconSize = ExperienceLayout.defaultFinderIconSize

    var shooterPosition: CGPoint { shooterNode.position }
    var shooterRestingPosition: CGPoint { shooterRestingPoint }
    var visualTargetPosition: CGPoint { targetPoint }

    init(size: CGSize, assets: AnimationAssets = .load()) {
        self.assets = assets
        shooterNode = assets.idleTextures.first.map { SKSpriteNode(texture: $0) }
            ?? SKSpriteNode(color: .systemGreen, size: ExperienceLayout.shooterSize)
        fileNode = SKSpriteNode(color: .clear, size: ExperienceLayout.defaultFinderIconSize)
        super.init(size: size)

        scaleMode = .resizeFill
        backgroundColor = .clear
        isUserInteractionEnabled = false

        shooterNode.name = "peashooter"
        shooterNode.zPosition = 20
        shooterNode.size = ExperienceLayout.shooterSize
        addChild(shooterNode)

        fileNode.name = "deferredFileRepresentation"
        fileNode.zPosition = 16
        addChild(fileNode)

        damageOverlayNode.name = "finderDamageOverlay"
        damageOverlayNode.zPosition = 38
        addChild(damageOverlayNode)

        crackOutlineNode.zPosition = 3
        crackOutlineNode.name = "visibleCrackOutline"
        crackOutlineNode.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        crackOutlineNode.lineWidth = ExperienceLayout.crackOutlineWidth
        crackOutlineNode.lineCap = .round
        crackOutlineNode.lineJoin = .round
        damageOverlayNode.addChild(crackOutlineNode)

        crackNode.zPosition = 4
        crackNode.name = "visibleCrackLine"
        crackNode.strokeColor = NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.04, alpha: 1)
        crackNode.lineWidth = ExperienceLayout.crackLineWidth
        crackNode.lineCap = .round
        crackNode.lineJoin = .round
        damageOverlayNode.addChild(crackNode)

        fileCaption.name = "virtualFileCaption"
        fileCaption.fontSize = 13
        fileCaption.fontColor = .white
        fileCaption.zPosition = 18
        fileCaption.horizontalAlignmentMode = .center
        fileCaption.verticalAlignmentMode = .top
        addChild(fileCaption)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        fileIcon: NSImage,
        fileName: String,
        targetPoint proposedPoint: CGPoint,
        targetIconSize proposedIconSize: CGSize?,
        showsVirtualFile: Bool
    ) {
        removeAllActions()
        shooterNode.removeAllActions()
        fileNode.removeAllActions()
        damageOverlayNode.removeAllActions()
        pendingFinalProjectile?.removeFromParent()
        pendingFinalProjectile = nil
        crackOutlineNode.path = nil
        crackOutlineNode.alpha = 1
        crackNode.path = nil
        crackNode.alpha = 1
        targetIconSize = ExperienceLayout.normalizedFinderIconSize(proposedIconSize)

        targetPoint = CGPoint(
            x: min(max(proposedPoint.x, 0), size.width),
            y: min(max(proposedPoint.y, 0), size.height)
        )
        // Keep the shooter geometrically to the target's left even for icons
        // close to the display edge. A portion may sit off-screen, but the pea
        // must never approach the icon from the wrong side.
        let minimumPartiallyVisibleCenter = -ExperienceLayout.shooterSize.width * 0.35
        shooterRestingPoint = CGPoint(
            x: max(
                minimumPartiallyVisibleCenter,
                targetPoint.x - ExperienceLayout.shooterTargetCenterDistance
            ),
            y: min(max(targetPoint.y - 5, 0), size.height)
        )

        let texture = SKTexture(image: fileIcon)
        texture.filteringMode = .linear
        fileNode.texture = texture
        fileNode.color = .clear
        fileNode.colorBlendFactor = 0
        fileNode.size = targetIconSize
        fileNode.position = targetPoint
        fileNode.alpha = showsVirtualFile ? 1 : 0
        fileNode.isHidden = !showsVirtualFile
        fileNode.zRotation = 0
        damageOverlayNode.position = targetPoint
        damageOverlayNode.alpha = 1

        fileCaption.text = fileName
        fileCaption.position = CGPoint(x: targetPoint.x, y: targetPoint.y - targetIconSize.height / 2 - 12)
        fileCaption.alpha = showsVirtualFile ? 1 : 0

        shooterNode.position = CGPoint(x: -ExperienceLayout.shooterSize.width, y: shooterRestingPoint.y)
        shooterNode.alpha = 0
        shooterNode.zRotation = 0
        shooterNode.setScale(1)
        if let firstTexture = assets.idleTextures.first {
            shooterNode.texture = firstTexture
        }
    }

    func spawnAndApproach(completion: @escaping () -> Void) {
        let idle = repeatingAnimation(textures: assets.idleTextures, frameDuration: 0.095)
        shooterNode.run(idle, withKey: "idle")
        shooterNode.alpha = 1

        let dust = makeEmitter(color: .systemBrown, particles: 28, speed: 75)
        dust.position = CGPoint(x: 18, y: shooterRestingPoint.y - ExperienceLayout.shooterSize.height * 0.31)
        dust.zPosition = 8
        addChild(dust)
        dust.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))

        let distance = max(1, shooterRestingPoint.x - shooterNode.position.x)
        let duration = min(2.8, max(1.3, TimeInterval(distance / 360)))
        let move = SKAction.move(to: shooterRestingPoint, duration: duration)
        move.timingMode = .easeInEaseOut
        shooterNode.run(move, completion: completion)
    }

    func playCharge(completion: @escaping () -> Void) {
        shooterNode.removeAction(forKey: "idle")
        guard !assets.shootTextures.isEmpty else {
            run(.sequence([.wait(forDuration: 0.45), .run(completion)]))
            return
        }

        let chargeFrames = Array(assets.shootTextures.prefix(min(6, assets.shootTextures.count)))
        let charge = SKAction.animate(with: chargeFrames, timePerFrame: 0.075, resize: false, restore: false)
        shooterNode.run(charge, completion: completion)
    }

    func fireInitialShots(completion: @escaping () -> Void) {
        fireShots(currentHit: 1, finalHit: 4, completion: completion)
    }

    /// Launches the fifth pea and stops it at the target without showing an
    /// impact. The controller begins the Trash operation only from this
    /// arrival callback, so the real Finder icon cannot disappear before the
    /// final projectile has visibly reached it.
    func launchFinalShot(onArrival: @escaping () -> Void) {
        pendingFinalProjectile?.removeFromParent()

        if !assets.shootTextures.isEmpty {
            shooterNode.run(.animate(with: assets.shootTextures, timePerFrame: 0.037, resize: false, restore: false))
        }
        run(.playSoundFileNamed("assets/sounds/firepea.wav", waitForCompletion: false))

        let pea = makeProjectileNode()
        pea.name = "pendingFinalProjectile"
        pendingFinalProjectile = pea
        addChild(pea)

        let move = SKAction.move(to: targetPoint, duration: 0.42)
        move.timingMode = .easeIn
        pea.run(move, completion: onArrival)
    }

    /// Commits the fifth impact only after FileManager.trashItem has returned
    /// success. Impact, captured-icon fragmentation and Finder disappearance
    /// therefore begin on the same visual beat.
    func completeFinalHitAndShatter(completion: @escaping () -> Void) {
        pendingFinalProjectile?.removeFromParent()
        pendingFinalProjectile = nil
        run(.playSoundFileNamed("assets/sounds/splat.wav", waitForCompletion: false))
        playImpact()
        renderDamageOverlay(level: 5)
        shatterFile(completion: completion)
    }

    func cancelPendingFinalShot() {
        pendingFinalProjectile?.removeFromParent()
        pendingFinalProjectile = nil
    }

    func waitBeforeZombieExit(completion: @escaping () -> Void) {
        run(.sequence([
            .wait(forDuration: 0.8),
            .run(completion)
        ]))
    }

    func showFailure(message: String, completion: @escaping () -> Void) {
        shooterNode.removeAllActions()
        if let firstTexture = assets.idleTextures.first {
            shooterNode.texture = firstTexture
        }
        let label = makeMessageLabel(text: "失败：\(message)", color: .systemRed)
        label.position = CGPoint(
            x: min(size.width - 240, max(240, targetPoint.x)),
            y: targetPoint.y + targetIconSize.height / 2 + 38
        )
        addChild(label)
        label.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 2.2),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
            .run(completion)
        ]))
    }

    func playZombieExit(completion: @escaping () -> Void) {
        shooterNode.removeAllActions()
        if let firstTexture = assets.idleTextures.first {
            shooterNode.texture = firstTexture
        }

        let carryGroup = SKNode()
        carryGroup.name = "zombieCarryGroup"
        carryGroup.zPosition = 55

        let leftZombie = makeZombieNode()
        let rightZombie = makeZombieNode()
        leftZombie.name = "leftStretcherZombie"
        rightZombie.name = "rightStretcherZombie"
        leftZombie.position = CGPoint(x: -112, y: -5)
        rightZombie.position = CGPoint(x: 112, y: -5)

        let stretcher = makeStretcherNode()
        stretcher.name = "stretcher"
        stretcher.position = CGPoint(x: 0, y: -10)

        carryGroup.addChild(stretcher)
        carryGroup.addChild(leftZombie)
        carryGroup.addChild(rightZombie)
        carryGroup.position = CGPoint(
            x: size.width + ExperienceLayout.stretcherSize.width,
            y: shooterRestingPoint.y - 32
        )
        addChild(carryGroup)

        let walk = repeatingAnimation(textures: assets.zombieTextures, frameDuration: 0.13)
        leftZombie.run(walk, withKey: "walk")
        rightZombie.run(walk, withKey: "walk")

        let arrive = SKAction.move(
            to: CGPoint(x: shooterRestingPoint.x, y: shooterRestingPoint.y - 32),
            duration: 1.55
        )
        arrive.timingMode = .easeInEaseOut
        carryGroup.run(arrive)

        run(.sequence([
            .wait(forDuration: 1.6),
            .run { [weak self] in
                guard let self else { return }
                let protest = self.makeMessageLabel(text: "等等，我还能再打一份！", color: .systemYellow)
                protest.position = CGPoint(
                    x: self.shooterRestingPoint.x,
                    y: self.shooterRestingPoint.y + ExperienceLayout.shooterSize.height * 0.72
                )
                self.addChild(protest)
                protest.run(.sequence([.wait(forDuration: 1.0), .fadeOut(withDuration: 0.3), .removeFromParent()]))

                self.shooterNode.removeFromParent()
                carryGroup.addChild(self.shooterNode)
                self.shooterNode.position = CGPoint(x: 0, y: 32)
                self.shooterNode.zPosition = 5
                self.shooterNode.zRotation = -0.16
                self.shooterNode.run(.repeatForever(.sequence([
                    .group([
                        .moveBy(x: 0, y: 5, duration: 0.16),
                        .rotate(toAngle: 0.08, duration: 0.16, shortestUnitArc: true)
                    ]),
                    .group([
                        .moveBy(x: 0, y: -5, duration: 0.16),
                        .rotate(toAngle: -0.16, duration: 0.16, shortestUnitArc: true)
                    ])
                ])), withKey: "stretcherStruggle")
            },
            .wait(forDuration: 0.8),
            .run { [weak self] in
                guard let self else { return }
                let exitX = self.size.width + ExperienceLayout.stretcherSize.width
                let duration: TimeInterval = 2.15
                carryGroup.xScale = -1
                let exit = SKAction.moveTo(x: exitX, duration: duration)
                exit.timingMode = .easeIn
                carryGroup.run(exit) {
                    carryGroup.removeFromParent()
                    completion()
                }
            }
        ]))
    }

    private func fireShots(currentHit: Int, finalHit: Int, completion: @escaping () -> Void) {
        guard currentHit <= finalHit else {
            completion()
            return
        }

        fireSingleShot(hitIndex: currentHit) { [weak self] in
            guard let self else { return }
            self.run(.sequence([
                // 0.42 s flight + 0.05 s reset keeps shot starts about 470 ms apart.
                .wait(forDuration: 0.05),
                .run {
                    self.fireShots(currentHit: currentHit + 1, finalHit: finalHit, completion: completion)
                }
            ]))
        }
    }

    private func fireSingleShot(hitIndex: Int, completion: @escaping () -> Void) {
        if !assets.shootTextures.isEmpty {
            shooterNode.run(.animate(with: assets.shootTextures, timePerFrame: 0.037, resize: false, restore: false))
        }
        run(.playSoundFileNamed("assets/sounds/firepea.wav", waitForCompletion: false))

        let pea = makeProjectileNode()
        addChild(pea)

        let move = SKAction.move(to: targetPoint, duration: 0.42)
        move.timingMode = .easeIn
        pea.run(move) { [weak self, weak pea] in
            pea?.removeFromParent()
            guard let self else { return }
            self.run(.playSoundFileNamed("assets/sounds/splat.wav", waitForCompletion: false))
            self.playImpact()
            self.renderDamageOverlay(level: hitIndex)
            completion()
        }
    }

    private func makeProjectileNode() -> SKSpriteNode {
        let pea = SKSpriteNode(texture: assets.projectileTexture)
        pea.size = ExperienceLayout.projectileSize
        pea.position = CGPoint(
            x: shooterNode.position.x + ExperienceLayout.shooterMuzzleOffset.x,
            y: shooterNode.position.y + ExperienceLayout.shooterMuzzleOffset.y
        )
        pea.zPosition = 30
        return pea
    }

    private func playImpact() {
        guard let first = assets.impactTextures.first else { return }
        let impact = SKSpriteNode(texture: first)
        impact.position = targetPoint
        impact.size = ExperienceLayout.impactSize
        impact.zPosition = 42
        addChild(impact)
        impact.run(.sequence([
            .animate(with: assets.impactTextures, timePerFrame: 0.055, resize: false, restore: false),
            .removeFromParent()
        ]))

        let shockRing = SKShapeNode(circleOfRadius: max(targetIconSize.width, targetIconSize.height) * 0.46)
        shockRing.position = targetPoint
        shockRing.fillColor = .clear
        shockRing.strokeColor = NSColor(calibratedRed: 0.76, green: 1, blue: 0.20, alpha: 0.96)
        shockRing.lineWidth = 5
        shockRing.zPosition = 41
        addChild(shockRing)
        shockRing.run(.sequence([
            .group([
                .scale(to: 1.55, duration: 0.24),
                .fadeOut(withDuration: 0.24)
            ]),
            .removeFromParent()
        ]))
    }

    func renderDamageOverlay(level: Int) {
        let amplitude: CGFloat = level >= 4 ? 8 : CGFloat(2 + level)
        let shake = SKAction.sequence([
            .moveBy(x: -amplitude, y: 2, duration: 0.035),
            .moveBy(x: amplitude * 2, y: -4, duration: 0.06),
            .moveBy(x: -amplitude, y: 2, duration: 0.035)
        ])
        damageOverlayNode.run(shake)

        let path = crackPath(level: level)
        crackOutlineNode.path = path
        crackNode.path = path
        crackOutlineNode.run(.sequence([.fadeAlpha(to: 1, duration: 0.01), .fadeAlpha(to: 0.74, duration: 0.16)]))
        crackNode.run(.sequence([.fadeAlpha(to: 1, duration: 0.01), .fadeAlpha(to: 0.92, duration: 0.16)]))
        if level >= 4 {
            let debris = makeEmitter(color: .lightGray, particles: 18, speed: 95)
            debris.position = targetPoint
            debris.zPosition = 40
            addChild(debris)
            debris.run(.sequence([.wait(forDuration: 1.0), .removeFromParent()]))
        }
    }

    private func crackPath(level: Int) -> CGPath {
        let halfWidth = targetIconSize.width * 0.42
        let halfHeight = targetIconSize.height * 0.44
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -3, y: halfHeight))
        path.addLine(to: CGPoint(x: 2, y: halfHeight * 0.48))
        path.addLine(to: CGPoint(x: -7, y: halfHeight * 0.16))

        if level >= 2 {
            path.addLine(to: CGPoint(x: 4, y: -halfHeight * 0.10))
            path.addLine(to: CGPoint(x: -2, y: -halfHeight * 0.56))
            path.addLine(to: CGPoint(x: 6, y: -halfHeight))
            path.move(to: CGPoint(x: 2, y: halfHeight * 0.48))
            path.addLine(to: CGPoint(x: halfWidth * 0.34, y: halfHeight * 0.30))
        }

        if level >= 3 {
            path.move(to: CGPoint(x: 2, y: halfHeight * 0.48))
            path.addLine(to: CGPoint(x: halfWidth * 0.52, y: halfHeight * 0.25))
            path.addLine(to: CGPoint(x: halfWidth, y: halfHeight * 0.36))
            path.move(to: CGPoint(x: -7, y: halfHeight * 0.16))
            path.addLine(to: CGPoint(x: -halfWidth * 0.58, y: halfHeight * 0.40))
            path.addLine(to: CGPoint(x: -halfWidth, y: halfHeight * 0.16))
        }
        if level >= 4 {
            path.move(to: CGPoint(x: 4, y: -halfHeight * 0.10))
            path.addLine(to: CGPoint(x: halfWidth * 0.65, y: -halfHeight * 0.36))
            path.addLine(to: CGPoint(x: halfWidth, y: -halfHeight * 0.20))
            path.move(to: CGPoint(x: -2, y: -halfHeight * 0.56))
            path.addLine(to: CGPoint(x: -halfWidth * 0.58, y: -halfHeight * 0.78))
            path.addLine(to: CGPoint(x: -halfWidth, y: -halfHeight * 0.62))
        }
        return path
    }

    private func shatterFile(completion: @escaping () -> Void) {
        run(.playSoundFileNamed("assets/sounds/pop.wav", waitForCompletion: false))
        guard let texture = fileNode.texture else {
            fileNode.run(.fadeOut(withDuration: 0.25), completion: completion)
            return
        }

        let columns = 4
        let rows = 4
        let fragmentSize = CGSize(
            width: fileNode.size.width / CGFloat(columns),
            height: fileNode.size.height / CGFloat(rows)
        )

        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(
                    x: CGFloat(column) / CGFloat(columns),
                    y: CGFloat(row) / CGFloat(rows),
                    width: 1 / CGFloat(columns),
                    height: 1 / CGFloat(rows)
                )
                let fragmentTexture = SKTexture(rect: rect, in: texture)
                let fragment = SKSpriteNode(texture: fragmentTexture)
                fragment.name = "fileFragment"
                fragment.size = fragmentSize
                fragment.position = CGPoint(
                    x: targetPoint.x + (CGFloat(column) + 0.5) * fragmentSize.width - fileNode.size.width / 2,
                    y: targetPoint.y + (CGFloat(row) + 0.5) * fragmentSize.height - fileNode.size.height / 2
                )
                fragment.zPosition = 65
                fragment.setScale(1.08)
                addChild(fragment)

                let horizontal = CGFloat.random(in: -155...155)
                let vertical = CGFloat.random(in: -225 ... -105)
                let duration = TimeInterval.random(in: 1.05...1.48)
                fragment.run(.sequence([
                    .group([
                        .moveBy(x: horizontal, y: vertical, duration: duration),
                        .rotate(byAngle: CGFloat.random(in: -2.8...2.8), duration: duration),
                        .scale(to: CGFloat.random(in: 0.2...0.55), duration: duration),
                        .fadeOut(withDuration: duration)
                    ]),
                    .removeFromParent()
                ]))
            }
        }

        let flash = SKShapeNode(circleOfRadius: max(targetIconSize.width, targetIconSize.height) * 0.54)
        flash.position = targetPoint
        flash.fillColor = NSColor(calibratedWhite: 1, alpha: 0.82)
        flash.strokeColor = NSColor(calibratedRed: 0.58, green: 1, blue: 0.16, alpha: 1)
        flash.lineWidth = 6
        flash.zPosition = 60
        addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 1.45, duration: 0.28), .fadeOut(withDuration: 0.28)]),
            .removeFromParent()
        ]))

        let burst = makeEmitter(color: .systemGreen, particles: 70, speed: 185)
        burst.position = targetPoint
        burst.zPosition = 70
        addChild(burst)
        burst.run(.sequence([.wait(forDuration: 1.25), .removeFromParent()]))

        let paper = makeEmitter(color: .lightGray, particles: 38, speed: 135)
        paper.position = targetPoint
        paper.zPosition = 69
        addChild(paper)
        paper.run(.sequence([.wait(forDuration: 1.35), .removeFromParent()]))

        fileNode.isHidden = true
        fileCaption.run(.fadeOut(withDuration: 0.15))
        damageOverlayNode.run(.fadeOut(withDuration: 0.15))
        run(.sequence([.wait(forDuration: 1.55), .run(completion)]))
    }

    private func repeatingAnimation(textures: [SKTexture], frameDuration: TimeInterval) -> SKAction {
        guard !textures.isEmpty else { return .wait(forDuration: frameDuration) }
        return .repeatForever(.animate(with: textures, timePerFrame: frameDuration, resize: false, restore: false))
    }

    private func makeZombieNode() -> SKSpriteNode {
        let node: SKSpriteNode
        if let first = assets.zombieTextures.first {
            node = SKSpriteNode(texture: first)
        } else {
            node = SKSpriteNode(color: .systemGray, size: ExperienceLayout.zombieSize)
        }
        node.size = ExperienceLayout.zombieSize
        node.zPosition = 4
        // The classic PvZ walk frames face left while the zombies enter from the right.
        // They are flipped to face right only when carrying the peashooter off screen.
        node.xScale = 1
        return node
    }

    private func makeStretcherNode() -> SKNode {
        let stretcher = SKNode()
        stretcher.zPosition = 2

        let shadow = SKShapeNode(
            rectOf: CGSize(width: ExperienceLayout.stretcherSize.width - 24, height: 27),
            cornerRadius: 7
        )
        shadow.fillColor = NSColor(calibratedWhite: 0.08, alpha: 0.28)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -3)
        shadow.zPosition = 0
        stretcher.addChild(shadow)

        let canvas = SKShapeNode(
            rectOf: CGSize(width: ExperienceLayout.stretcherSize.width - 30, height: 27),
            cornerRadius: 7
        )
        canvas.fillColor = NSColor(calibratedRed: 0.50, green: 0.62, blue: 0.24, alpha: 1)
        canvas.strokeColor = NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.09, alpha: 1)
        canvas.lineWidth = 2.2
        canvas.zPosition = 1
        stretcher.addChild(canvas)

        for x in [CGFloat(-48), CGFloat(48)] {
            let strap = SKShapeNode(rectOf: CGSize(width: 7, height: 27), cornerRadius: 2)
            strap.fillColor = NSColor(calibratedRed: 0.29, green: 0.40, blue: 0.12, alpha: 0.9)
            strap.strokeColor = .clear
            strap.position = CGPoint(x: x, y: 0)
            strap.zPosition = 2
            stretcher.addChild(strap)
        }

        for y in [CGFloat(-18), CGFloat(18)] {
            let pole = SKShapeNode(
                rectOf: CGSize(width: ExperienceLayout.stretcherSize.width, height: 7),
                cornerRadius: 3.5
            )
            pole.fillColor = NSColor(calibratedRed: 0.46, green: 0.25, blue: 0.08, alpha: 1)
            pole.strokeColor = NSColor(calibratedRed: 0.20, green: 0.10, blue: 0.03, alpha: 1)
            pole.lineWidth = 1.5
            pole.position = CGPoint(x: 0, y: y)
            pole.zPosition = 3
            stretcher.addChild(pole)
        }

        for x in [-ExperienceLayout.stretcherSize.width / 2, ExperienceLayout.stretcherSize.width / 2] {
            let grip = SKShapeNode(circleOfRadius: 4.8)
            grip.fillColor = NSColor(calibratedRed: 0.56, green: 0.35, blue: 0.13, alpha: 1)
            grip.strokeColor = NSColor(calibratedRed: 0.20, green: 0.10, blue: 0.03, alpha: 1)
            grip.lineWidth = 1.2
            grip.position = CGPoint(x: x, y: 0)
            grip.zPosition = 5
            stretcher.addChild(grip)
        }

        return stretcher
    }

    private func makeEmitter(color: NSColor, particles: Int, speed: CGFloat) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 240
        emitter.numParticlesToEmit = particles
        emitter.particleLifetime = 0.85
        emitter.particleLifetimeRange = 0.28
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.45
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 0.95
        emitter.particleAlphaSpeed = -1.05
        emitter.particleTexture = particleTexture(color: color)
        emitter.particleScale = 0.9
        emitter.particleScaleRange = 0.45
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        return emitter
    }

    private func particleTexture(color: NSColor) -> SKTexture {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 12, height: 12)).fill()
        image.unlockFocus()
        return SKTexture(image: image)
    }

    private func makeMessageLabel(text: String, color: NSColor) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "PingFang SC Semibold")
        label.text = text
        label.fontSize = 20
        label.fontColor = color
        label.zPosition = 80
        label.alpha = 0
        return label
    }
}
