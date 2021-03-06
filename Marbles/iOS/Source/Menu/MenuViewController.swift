//
//  MenuViewController.swift
//  Marbles AR
//
//  Created by Rafal Grodzinski on 09/02/16.
//  Copyright © 2016 UnalignedByte. All rights reserved.
//

import UIKit
import Crashlytics


class MenuViewController: UIViewController
{
    // Constant
    let logoColorUpdateInterval = 1.0/60.0
    let logoColorUpdateAmount = 1.0/(60.0 * 15.0)
    var resumeButtonHeight: CGFloat = 0.0

    // Variables
    var currentLogoHue = 100.0/360.0
    var logoColorUpdateTimer: Timer!
    var game: Game?
    var gameVc: UIViewController?
    var isArModeSelected = true
    var isArModeChanged: Bool {
        if #available(iOS 11.0, *) {
            let isGameInAr = self.game! is ArKitGame
            return isGameInAr || (isGameInAr != self.isArModeSelected)
        }

        return false
    }

    // Outlets
    @IBOutlet private weak var logoLabel: UILabel!
    @IBOutlet private weak var highScoreLabel: UILabel!
    @IBOutlet private weak var topButton: UIButton!
    @IBOutlet private weak var bottomButton: UIButton!
    @IBOutlet private weak var tipPromptLabel: UILabel!
    @IBOutlet private weak var arModeLabel: UILabel!
    @IBOutlet private weak var arModeSwitch: UISwitch!
    @IBOutlet private weak var arUnsupportedLabel: UILabel!


    // MARK: - Initialization -
    override func viewDidLoad()
    {
        self.updateHighScoreLabel()

        self.logoColorUpdateTimer = Timer.scheduledTimer(timeInterval: self.logoColorUpdateInterval,
                                                                           target: self,
                                                                           selector: #selector(updateLogoLabelColorTimeout),
                                                                           userInfo: nil,
                                                                           repeats: true)

        self.logoLabel.textColor = Color.marblesGreen
        self.highScoreLabel.textColor = Color.marblesGreen
        self.arModeLabel.textColor = Color.marblesGreen
        self.arModeSwitch.onTintColor = Color.marblesGreen
        self.arUnsupportedLabel.textColor = Color.marblesOrange
        self.tipPromptLabel.textColor = Color.white

        if !GameFactory.isArModeAvailable {
            self.isArModeSelected = false
            self.arModeLabel.isEnabled = false
            self.arModeSwitch.isEnabled = false
            self.arModeSwitch.isOn = false
            self.arUnsupportedLabel.isHidden = false
        }

        self.setupForNewGame()
    }


    override func viewDidAppear(_ animated: Bool)
    {
        #if !DEBUG
            Answers.logCustomEvent(withName: "Entered View", customAttributes: ["Name" : "MainMenu"])
        #endif

        if #available(iOS 11.0, *) {
            UIView.topMargin = view.safeAreaInsets.top
        }
    }


    private func setupGame(field: Field?, drawnMarbleColors: [Int]?)
    {
        let graphicsType: GraphicsType = self.isArModeSelected ? .arKit : .sceneKit

        self.gameVc = UIViewController()
        self.game = GameFactory.gameWithGraphicsType(graphicsType, size: Size(9, 9), colorsCount: 5, marblesPerSpawn: 3, lineLength: 5, field: field)
        self.gameVc!.view.addSubview(self.game!.view)
        self.gameVc!.modalTransitionStyle = .crossDissolve
        self.game!.view.frame = gameVc!.view.bounds
        if let field = field {
            self.game!.field = field
        }
        self.game!.drawnMarbleColors = drawnMarbleColors

        self.game!.pauseCallback = { [weak self] in
            self?.currentLogoHue = 100.0/360.0
            self?.updateHighScoreLabel()
            self?.setupForResume()
            self?.gameVc!.dismiss(animated: false, completion: nil)
        }

        self.game!.quitCallback = { [weak self] in
            self?.currentLogoHue = 100.0/360.0
            self?.updateHighScoreLabel()
            self?.setupForNewGame()
            self?.gameVc!.dismiss(animated: false, completion: nil)
        }
    }


    // MARK: - Actions -
    @IBAction func newGameButtonPressed(_ sender: UIButton)
    {
        #if !DEBUG
            Answers.logCustomEvent(withName: "Game", customAttributes: ["Action" : "Started"])
        #endif


        setupGame(field: nil, drawnMarbleColors: nil)

        self.game!.startGame()
        self.present(self.gameVc!, animated: true, completion: nil)
    }


    @IBAction func resumeGameButtonPressed(_ sender: AnyObject)
    {
        #if !DEBUG
            Answers.logCustomEvent(withName: "Game", customAttributes: ["Action" : "Resumed"])
        #endif

        if self.isArModeChanged {
            setupGame(field: game?.field, drawnMarbleColors: game?.drawnMarbleColors)
            self.game?.resumeGame()
        }

        self.present(self.gameVc!, animated: true, completion: nil)
    }


    @IBAction func arModeSwitchToggled(_ sender: UISwitch)
    {
        self.isArModeSelected = sender.isOn
    }


    // MARK: - Internal Control -
    @objc func updateLogoLabelColorTimeout()
    {
         self.logoLabel.textColor = UIColor(hue: CGFloat(self.currentLogoHue), saturation: 0.8, brightness: 0.8, alpha: 1.0)

        self.currentLogoHue += self.logoColorUpdateAmount
        if self.currentLogoHue > 1.0 {
            self.currentLogoHue = 0.0
        }
    }


    func updateHighScoreLabel()
    {
        if ScoreSingleton.sharedInstance.highScore > 0
        {
            self.highScoreLabel.isHidden = false
            self.highScoreLabel.text = "High Score: \(ScoreSingleton.sharedInstance.highScore)"

            if UserDefaults.standard.value(forKey: "hasTipped") == nil {
                self.tipPromptLabel.isHidden = false
            } else {
                self.tipPromptLabel.isHidden = true
            }
        }
        else
        {
            self.highScoreLabel.isHidden = true
            self.tipPromptLabel.isHidden = true
        }
    }


    fileprivate func setupForNewGame()
    {
        // Top Button
        self.topButton.setTitle("New Game", for: .normal)
        self.topButton.removeTarget(nil, action: nil, for: .allEvents)
        self.topButton.addTarget(self, action: #selector(newGameButtonPressed), for: .touchUpInside)

        // Bottom Button
        self.bottomButton.isHidden = true
    }


    fileprivate func setupForResume()
    {
        // Top Button
        self.topButton.setTitle("Resume", for: UIControlState())
        self.topButton.removeTarget(nil, action: nil, for: .allEvents)
        self.topButton.addTarget(self, action: #selector(resumeGameButtonPressed), for: .touchUpInside)

        // Bottom Button
        self.bottomButton.isHidden = false
        self.bottomButton.setTitle("New Game", for: UIControlState())
        self.bottomButton.removeTarget(nil, action: nil, for: .allEvents)
        self.bottomButton.addTarget(self, action: #selector(newGameButtonPressed), for: .touchUpInside)
    }
}
