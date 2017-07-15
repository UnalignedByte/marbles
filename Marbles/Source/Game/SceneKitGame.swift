//
//  SceneKitGame.swift
//  Kulki
//
//  Created by Rafal Grodzinski on 26/04/16.
//  Copyright © 2016 UnalignedByte. All rights reserved.
//

import SceneKit
import SpriteKit
import GLKit
import Crashlytics


class SceneKitGame: Game, UIGestureRecognizerDelegate
{
    internal var scene: SCNScene!
    internal var centerNode: SCNNode!
    internal var gameScale: Float = 1.0

    internal var spotLight: SCNLight!
    internal var ambientLight: SCNLight!

    fileprivate var tileSelectionParticleNode: SCNNode!
    fileprivate var tileSelectionParticle: SCNParticleSystem!

    fileprivate let _marbleScale: Float = 1.0
    internal var marbleScale: Float  {
        return self._marbleScale * self.gameScale
    }
    fileprivate let _tileSize = SCNVector3(x: 1.0, y: 1.0, z: 0.25)
    fileprivate var tileSize: SCNVector3 {
        return SCNVector3(x: self._tileSize.x * self.gameScale, y: self._tileSize.y * self.gameScale, z: self._tileSize.z * self.gameScale)
    }
    fileprivate let fieldMoveDuration: Float = 0.4

    lazy var tilePrototype: SCNNode = {
        let tileNode = SCNNode()
        tileNode.geometry = SCNBox(width: CGFloat(self.tileSize.x), height: CGFloat(self.tileSize.y),
                                   length: CGFloat(self.tileSize.z), chamferRadius: 0.0)
        tileNode.geometry?.materials.first?.diffuse.contents = "Tile Diffuse"
        tileNode.geometry?.materials.first?.normal.contents = "Tile Normal"
        tileNode.geometry?.materials.first?.normal.intensity = 0.5
        tileNode.physicsBody = SCNPhysicsBody.static()
        return tileNode
    }()

    fileprivate var scoreLabel: SKLabelNode!
    fileprivate var scoreLabelShadow: SKLabelNode!
    fileprivate var gameOverPopup: GameOverPopup!

    fileprivate var nextMarbles = [Marble]()


    // MARK: - Initialization -
    override func setupView()
    {
        self.view = SCNView()

        #if DEBUG
            (self.view as! SCNView).showsStatistics = true
        #endif
    }


    override func setupCustom()
    {
        setupScene()
        setupShadowPlane()
        setupParticles()
        setupLight()
        setupOverlay()
        setupCamera()

        // Start the game
        (self.view as! SCNView).isPlaying = true
    }

    internal func setupScene()
    {
        (self.view as! SCNView).isPlaying = false
        (self.view as! SCNView).antialiasingMode = .multisampling2X
        (self.view as! SCNView).preferredFramesPerSecond = 60
        self.view.backgroundColor = UIColor.white

        if self.scene == nil {
            self.scene = SCNScene()
            (self.view as! SCNView).scene = self.scene!

            let backgroundView = MainMenuBackgroundView(frame: self.view.bounds)
            self.view.superview?.insertSubview(backgroundView, at: 0)

            self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        } else {
            self.scene.rootNode.enumerateChildNodes() { (node, p) in node.removeFromParentNode() }
        }

        self.scene.physicsWorld.gravity = SCNVector3(0.0, 0.0, -18)

        self.centerNode = SCNNode()
        self.scene.rootNode.addChildNode(self.centerNode)
    }

    internal func setupShadowPlane()
    {
        let shadowPlane = SCNFloor()
        shadowPlane.reflectivity = 0.0
        shadowPlane.firstMaterial?.diffuse.contents = UIColor.white
        if #available(iOS 11.0, *) {
            shadowPlane.firstMaterial?.colorBufferWriteMask = []
        }
        let shadowPlaneNode = SCNNode(geometry: shadowPlane)

        shadowPlaneNode.rotation = SCNVector4(x: 1.0, y: 0.0, z: 0.0, w: Float.pi * 0.5)
        centerNode.addChildNode(shadowPlaneNode)
    }

    internal func setupParticles()
    {
        // Selection particle
        self.tileSelectionParticleNode = SCNNode()
        self.centerNode.addChildNode(self.tileSelectionParticleNode)

        self.tileSelectionParticle = SCNParticleSystem(named: "Selection.scnp", inDirectory: nil)
        self.tileSelectionParticle.particleSize *= CGFloat(gameScale)
    }

    internal func setupCamera()
    {
        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        let height = Float(self.field.size.width > self.field.size.height ? self.field.size.width : self.field.size.height) * 1.6
        cameraNode.position = SCNVector3(0.0, 0.0, height)
        self.scene.rootNode.addChildNode(cameraNode)
    }

    internal func setupLight()
    {
        // Create spot light
        spotLight = SCNLight()
        spotLight.type = SCNLight.LightType.spot
        spotLight.shadowMode = .deferred
        spotLight.castsShadow = true
        spotLight.spotInnerAngle = 45.0;
        spotLight.spotOuterAngle = 90.0;
        spotLight.shadowColor = UIColor(colorLiteralRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.5)
        spotLight.attenuationEndDistance = 50.0
        spotLight.attenuationStartDistance = 50.0
        spotLight.zNear = 1.0 * CGFloat(gameScale)
        spotLight.zFar = 100.0 * CGFloat(gameScale)
        spotLight.attenuationFalloffExponent = 0
        spotLight.shadowMapSize = CGSize(width: 4096, height: 4096)

        let spotLightNode = SCNNode()
        spotLightNode.light = spotLight
        spotLightNode.constraints = [SCNLookAtConstraint(target: self.centerNode)]

        var spotLightPos = self.tilePositionForFieldPosition(Point(-self.field.size.width/2, -self.field.size.height/2))!
        spotLightPos.z = Float(self.field.size.width + self.field.size.height) * gameScale
        spotLightNode.position = spotLightPos
        self.centerNode.addChildNode(spotLightNode)

        // Create ambient light
        ambientLight = SCNLight()
        ambientLight.type = SCNLight.LightType.ambient
        ambientLight.color = UIColor(white: 0.2, alpha: 1.0)

        let ambientLightNode = SCNNode()
        ambientLightNode.light = ambientLight
        self.centerNode.addChildNode(ambientLightNode)
    }

    internal func setupOverlay()
    {
        // Create overlay
        let overlayScene = SKScene(size: self.view.frame.size)
        (self.view as! SCNView).overlaySKScene = overlayScene

        // Score label
        self.scoreLabel = SKLabelNode(fontNamed: "BunakenUnderwater")
        self.scoreLabel.fontSize = 32.0
        self.scoreLabel.fontColor = UIColor.marblesGreen()
        self.scoreLabel.horizontalAlignmentMode = .center
        self.scoreLabel.verticalAlignmentMode = .center
        self.scoreLabel.position = CGPoint(x: overlayScene.size.width*2.0/3.0, y: overlayScene.size.height - 32.0)
        // Score label shadow
        self.scoreLabelShadow =  self.scoreLabel.copy() as! SKLabelNode
        self.scoreLabelShadow.fontColor = UIColor.black
        self.scoreLabelShadow.position.x += 1.5
        self.scoreLabelShadow.position.y -= 1.5

        overlayScene.addChild(self.scoreLabelShadow)
        overlayScene.addChild(self.scoreLabel)
        self.updateScore(0)

        // Next label
        let nextLabel = SKLabelNode(fontNamed: "BunakenUnderwater")
        nextLabel.fontSize = 32.0
        nextLabel.fontColor = UIColor.marblesGreen()
        nextLabel.horizontalAlignmentMode = .left
        nextLabel.verticalAlignmentMode = .center
        nextLabel.position = CGPoint(x: 16.0, y: overlayScene.size.height/6.0)
        nextLabel.text = "Next:"

        // Next label shadow
        let nextLabelShadow =  nextLabel.copy() as! SKLabelNode
        nextLabelShadow.fontColor = UIColor.black
        nextLabelShadow.alpha = 1.0
        nextLabelShadow.position.x += 1.5
        nextLabelShadow.position.y -= 1.5

        overlayScene.addChild(nextLabelShadow)
        overlayScene.addChild(nextLabel)

        // Menu button
        let menuButton = Button(defaultTexture: SKTexture(imageNamed: "Menu Button") , pressedTexture: nil)
        menuButton.position = CGPoint(x: menuButton.size.width/2.0 + 16.0, y: overlayScene.size.height - menuButton.size.height/2.0 - 16.0)
        menuButton.callback =  { [weak self] in self?.pauseCallback!() }
        overlayScene.addChild(menuButton)

        // Game over popup
        self.gameOverPopup = GameOverPopup(size: overlayScene.size)
        self.gameOverPopup.position = CGPoint(x: overlayScene.frame.midX, y: overlayScene.frame.midY)
        self.gameOverPopup.restartCallback = { [weak self] in self?.startGame() }
        self.gameOverPopup.quitCallback = { [weak self] in self?.quitCallback!() }
        overlayScene.addChild(self.gameOverPopup)

        (self.view as! SCNView).overlaySKScene = overlayScene
    }


    // MARK: - Game Logic
    override func showBoard(_ finished: @escaping () -> Void)
    {
        for y in 0 ..< field.size.height {
            for x in 0 ..< field.size.width {
                let tileNode = self.tilePrototype.flattenedClone()
                
                tileNode.position = self.tilePositionForFieldPosition(Point(x, y))!
                tileNode.position.z = 0.0
                self.centerNode.addChildNode(tileNode)

                tileNode.scale = SCNVector3Zero
                let delayAction = SCNAction.wait(duration: Double(x + y) * 0.05 + 0.2)
                let scaleAction = SCNAction.scale(to: 1.0, duration: 0.2)
                scaleAction.timingMode = .easeInEaseOut

                let sequence = SCNAction.sequence([delayAction, scaleAction])

                tileNode.runAction(sequence)
            }
        }

        let delay = DispatchTime.now() + Double(Int64(Double(NSEC_PER_SEC) * 1.0)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            finished()
        }
    }


    override func showMarbles(_ marbles: [Marble], nextMarbleColors: [Int], finished: @escaping () -> Void)
    {
        for (index, marble) in marbles.enumerated() {
            let scnMarble = marble as! SceneKitMarble
            let targetPosition = scnMarble.node.position
            let targetScale = CGFloat(scnMarble.node.scale.x)
            scnMarble.node.scale = SCNVector3Zero
            scnMarble.node.position.z += (tileSize.x + tileSize.y) / 2.0

            let waitAction = SCNAction.wait(duration: 0.2 * TimeInterval(index))
            let nextMarble: Marble? = self.nextMarbles.count > index ? self.nextMarbles[index] : nil
            let hideNextAction = SCNAction.run { (node: SCNNode) in self.hideNextMarble(nextMarble) }

            let scaleAction = SCNAction.scale(to: targetScale, duration: 0.2)
            let fadeInAction = SCNAction.fadeIn(duration: 0.1)
            let appearAction = SCNAction.group([scaleAction, fadeInAction])
            let addGravityAction = SCNAction.run { (node: SCNNode) in node.physicsBody = SCNPhysicsBody.dynamic() }
            let waitToSettle = SCNAction.wait(duration: 0.8)
            let moveToPoint = SCNAction.move(to: targetPosition, duration: 0.1)
            let removeGravityAction = SCNAction.run { (node: SCNNode) in node.physicsBody = nil }

            let runBlockAction = SCNAction.run { (node: SCNNode) in
                if index == marbles.count-1 {
                    self.showNextMarbles(nextMarbleColors)
                    finished()
                }
            }

            self.centerNode.addChildNode(scnMarble.node)

            scnMarble.node.runAction(SCNAction.sequence([waitAction, hideNextAction, appearAction, addGravityAction,
                waitToSettle, moveToPoint, removeGravityAction, runBlockAction]))
        }
    }


    func hideNextMarble(_ nextMarble: Marble?)
    {
        if let nextMarble = nextMarble as? SceneKitMarble {
            let scaleAction = SCNAction.scale(to: 0.0, duration: 0.2)
            let removeAction = SCNAction.removeFromParentNode()

            nextMarble.node.runAction(SCNAction.sequence([scaleAction, removeAction]))
        }
    }


    func showNextMarbles(_ nextMarbleColors: [Int])
    {
        // Reset game scale to 1.0
        let savedScale = self.gameScale
        self.gameScale = 1.0

        self.nextMarbles = [Marble]()

        for (index, color) in nextMarbleColors.enumerated() {
            let nextMarble = self.field.marbleFactory.marbleWithColor(color, fieldPosition: Point(index, 0)) as! SceneKitMarble
            self.nextMarbles.append(nextMarble)

            nextMarble.node.scale = SCNVector3Zero
            nextMarble.node.position.x += 2.6
            nextMarble.node.position.y -= 1.5
            addNextMarble(nextMarble)
            nextMarble.node.runAction(SCNAction.scale(to: 1.0, duration: 0.2))
        }

        self.gameScale = savedScale
    }

    func addNextMarble(_ marble: SceneKitMarble)
    {
        self.scene.rootNode.addChildNode(marble.node)
    }


    override func hideMarbles(_ marbles: [Marble], finished: @escaping () -> Void)
    {
        for (index, marble) in marbles.enumerated() {
            let scnMarble = marble as! SceneKitMarble

            let waitAction = SCNAction.wait(duration: 0.1 * TimeInterval(index))

            let scaleAction = SCNAction.scale(to: 0.0, duration: 0.2)
            let fadeOutAction = SCNAction.fadeOut(duration: 0.2)
            let disappearAction = SCNAction.group([scaleAction, fadeOutAction])
            let removeAction = SCNAction.removeFromParentNode()
            let runBlockAction = SCNAction.run { (node: SCNNode) in if index == marbles.count-1 { finished() } }

            scnMarble.node.runAction(SCNAction.sequence([waitAction, disappearAction, removeAction, runBlockAction]))
        }
    }


    override func selectMarble(_ marbe: Marble)
    {
        (marbe as! SceneKitMarble).selected = true
    }


    override func deselectMarble(_ marbe: Marble)
    {
        (marbe as! SceneKitMarble).selected = false
    }


    override func moveMarble(_ marble: Marble, overFieldPath fieldPath: [Point], finished: @escaping () -> Void)
    {
        self.tileSelectionParticleNode.position = self.tilePositionForFieldPosition(fieldPath.last!)!
        self.tileSelectionParticleNode.addParticleSystem(self.tileSelectionParticle)

        let scnMarble = marble as! SceneKitMarble
        let scale = scnMarble.node.scale

        var previousFieldPosition = fieldPath.first!

        for (index, position) in fieldPath.enumerated() where index != 0 {
            // Rotation
            let radius = Float((scnMarble.node.geometry as! SCNSphere).radius) * gameScale
            let rotationAngle: Float = (self.tileSize.x / (2.0 * π * radius)) * 2 * π

            var xAngle: Float = 0.0
            if position.x > previousFieldPosition.x {
                xAngle = rotationAngle
            } else if (position.x < previousFieldPosition.x) {
                xAngle = -rotationAngle
            }

            var yAngle: Float = 0.0
            if position.y < previousFieldPosition.y {
                yAngle = rotationAngle
            } else if (position.y > previousFieldPosition.y) {
                yAngle = -rotationAngle
            }

            // X rotation
            var xAxisRotation = GLKVector3Make(0.0, 1.0, 0.0)
            xAxisRotation = GLKQuaternionRotateVector3(GLKQuaternionInvert(scnMarble.rotationQuat), xAxisRotation)
            scnMarble.rotationQuat = GLKQuaternionMultiply(scnMarble.rotationQuat, GLKQuaternionMakeWithAngleAndVector3Axis(Float(xAngle), xAxisRotation))

            // Y rotation
            var yAxisRotation = GLKVector3Make(1.0, 0.0, 0.0)
            yAxisRotation = GLKQuaternionRotateVector3(GLKQuaternionInvert(scnMarble.rotationQuat), yAxisRotation)
            scnMarble.rotationQuat = GLKQuaternionMultiply(scnMarble.rotationQuat, GLKQuaternionMakeWithAngleAndVector3Axis(Float(yAngle), yAxisRotation))

            let newRotationMatrix = GLKMatrix4MakeWithQuaternion(scnMarble.rotationQuat)
            let newPosition = self.marblePositionForFieldPosition(position)!

            // Timing function
            var timingFunction =  kCAMediaTimingFunctionLinear

            let positionDiff = position - previousFieldPosition
            let wasStraight = index >= 2 && fieldPath[index-2] == (previousFieldPosition - positionDiff)
            let willBeStraight = index <= fieldPath.count-2 && fieldPath[index+1] == (position + positionDiff)

            if !wasStraight && willBeStraight {
                timingFunction = kCAMediaTimingFunctionEaseIn
            } else if wasStraight && !willBeStraight {
                timingFunction = kCAMediaTimingFunctionEaseOut
            } else if !wasStraight && !willBeStraight {
                timingFunction = kCAMediaTimingFunctionEaseInEaseOut
            }

            // Actions
            let waitAction = SCNAction.wait(duration: TimeInterval(self.fieldMoveDuration) * TimeInterval(index-1))

            let animAct = SCNAction.run { (node:SCNNode) in
                SCNTransaction.begin()
                SCNTransaction.animationDuration = TimeInterval(self.fieldMoveDuration)
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: timingFunction)
                node.transform = SCNMatrix4FromGLKMatrix4(newRotationMatrix)
                node.position = newPosition
                node.scale = scale
                SCNTransaction.commit()
            }

            let lastWaitAction = SCNAction.wait(duration: TimeInterval(index == fieldPath.count-1 ? self.fieldMoveDuration : 0.0))

            let runBlockAction = SCNAction.run { (node: SCNNode) in if index == fieldPath.count-1 { finished() } }

            (marble as! SceneKitMarble).node.runAction(SCNAction.sequence([waitAction, animAct, lastWaitAction, runBlockAction]))

            previousFieldPosition = position
        }
    }


    override func updateScore(_ newScore: Int)
    {
        self.scoreLabel.text = "Score: \(newScore)"
        self.scoreLabelShadow.text = self.scoreLabel.text

        // Increased score, not reset
        if newScore > 0 {
            let scaleOut = SKAction.scale(to: 1.3, duration: 0.2)
            scaleOut.timingMode = .easeInEaseOut

            let scaleIn = SKAction.scale(to: 1.0, duration: 0.2)
            scaleIn.timingMode = .easeInEaseOut

            let scaleSequence = SKAction.sequence([scaleOut, scaleIn])

            self.scoreLabel.run(scaleSequence)
            self.scoreLabelShadow.run(scaleSequence)
        }
    }


    override func gameFinished(_ score: Int, isHighScore: Bool)
    {
        #if !DEBUG
            Answers.logCustomEvent(withName: "Game", customAttributes: ["Action" : "Finished",
                                                                        "Score" : score])
        #endif

        self.gameOverPopup.show(score, isHighScore: isHighScore)
    }


    // MARK: - Control -
    @objc func handleTap(_ sender: UITapGestureRecognizer)
    {
        let results = (self.view as! SCNView).hitTest(sender.location(in: self.view), options: nil)

        for result in results {
            if let fieldPosition = self.fieldPositionForPosition(result.node.position) {
                self.tappedFieldPosition(fieldPosition)
                break
            }
        }
    }


    // MARK: - Utils -
    func tilePositionForFieldPosition(_ fieldPosition: Point) -> SCNVector3?
    {
        let tileXOrigin = -(Float(self.field.size.width) * self.tileSize.x - self.tileSize.x) / 2.0
        let tileYOrigin = -(Float(self.field.size.height) * self.tileSize.y - self.tileSize.y) / 2.0

        let x = tileXOrigin + self.tileSize.x * Float(fieldPosition.x)
        let y = tileYOrigin + self.tileSize.y * Float(fieldPosition.y)

        return SCNVector3(x: x, y: y, z: 0.0)
    }


    func marblePositionForFieldPosition(_ fieldPosition: Point) -> SCNVector3?
    {
        guard fieldPosition.x >= 0 && fieldPosition.x < self.field.size.width &&
            fieldPosition.y >= 0 && fieldPosition.y < self.field.size.height else {
                return nil
        }

        let tileXOrigin = -(Float(self.field.size.width) * self.tileSize.x - self.tileSize.x) / 2.0
        let tileYOrigin = -(Float(self.field.size.height) * self.tileSize.y - self.tileSize.x) / 2.0

        let x = tileXOrigin + self.tileSize.x * Float(fieldPosition.x)
        let y = tileYOrigin + self.tileSize.y * Float(fieldPosition.y)

        return SCNVector3(x: x, y: y, z: marbleScale * 0.5)
    }


    func fieldPositionForPosition(_ position: SCNVector3) -> Point?
    {
        let tileXOrigin = -(Float(self.field.size.width) * self.tileSize.x) / 2.0
        let tileYOrigin = -(Float(self.field.size.height) * self.tileSize.y) / 2.0

        let x = Int((Float(position.x) - tileXOrigin)/self.tileSize.x)
        let y = Int((Float(position.y) - tileYOrigin)/self.tileSize.y)

        guard x >= 0 && x < self.field.size.width && y >= 0 && y < self.field.size.height else {
            return nil
        }

        return Point(x, y)
    }


    /*deinit
    {
        for node in self.scene.rootNode.childNodes {
            node.geometry = nil
            node.removeAllActions()
            node.removeFromParentNode()
        }
    }*/
}
