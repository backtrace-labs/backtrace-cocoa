//
//  ViewControllerPnP.swift
//  Example-iOS-PnP
//

import UIKit
import AVFoundation
import AVKit

class ViewControllerPnP : UIViewController {
    
    var videoURL: String?
    var playerVC: AVPlayerViewController?
    var avPlayer: AVPlayer?
    
    @IBAction func onBtnPlay() {
        playerVC = AVPlayerViewController()
        
        videoURL = Bundle.main.path(forResource: "0873", ofType: "MOV")
        guard videoURL != nil else {
            BreadcrumbBuilder.Error.addValue("Invalid", forKey: "Video URL").commit()
            return
        }
        
        let url = URL(fileURLWithPath: videoURL!)
        print("Video URL: \(url)")
        BreadcrumbBuilder.Info
            .addValue(url.path, forKey: "Video URL")
            .commit()

        avPlayer = AVPlayer(url: url)
        print("Status: \(avPlayer?.status.rawValue ?? -1)")
        print("Error: \(avPlayer?.error ?? "0")")

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
        }
        catch {
            BreadcrumbBuilder.Error
                .addValue("Failed to set audio session category", forKey: "Audio Session")
                .commit()
        }
        
        playerVC?.player = avPlayer

        
        let dict = [
            "Stage" : "Player Set Up",
            "Player Status:" : String.init(format: "%d", avPlayer?.status.rawValue ?? -1),
            "Player Error" : avPlayer?.error?.localizedDescription ?? "Invalid",
        ]
        BreadcrumbBuilder.Info
            .setValues(dict)
            .commit()

        
        guard playerVC != nil else { return }
        playerVC?.delegate = self
        
        present(playerVC!, animated: true) { [weak self] in
            
            switch self?.playerVC?.player?.status {
                case .failed:
                    BreadcrumbBuilder.Error
                        .addValue("Player Before Play", forKey: "Stage")
                        .addValue("Failed", forKey: "Player Status")
                        .commit()
                case .readyToPlay:
                    BreadcrumbBuilder.Info
                        .setValues([
                            "Stage":"Player Before Play",
                            "Player Status":"Ready To Play",
                        ])
                        .addValue("Play", forKey: "Next Step")
                        .commit()
                case .unknown:
                    BreadcrumbBuilder.Warning
                        .addValue("Player Before Play", forKey: "Stage")
                        .addValue("Unknown", forKey: "Player Status")
                        .commit()
                case .none:
                    BreadcrumbBuilder.Warning
                        .setValues([
                            "Stage":"Player Before Play",
                            "Player Status":"None",
                        ])
                        .commit()
                default: break
            }
            
            self?.playerVC?.player?.play()
            print("Status 2: \(self?.avPlayer?.status.rawValue ?? -1)")
            
            // Simulate crash in 5 seconds
            DispatchQueue
                .main
                .asyncAfter(deadline: .now() + 5,
                            execute: DispatchWorkItem.init(block: {
                    do {
                        let simulator = BacktraceSimulator()
                        try simulator.executeCase(atIndex: 10) // Live report
//                        try simulator.executeCase(atIndex: .random(in: 0..<simulator.numberOfCases()))
                    }
                    catch {}
                }))
        }
    }
}


extension ViewControllerPnP : AVPlayerViewControllerDelegate {
    
//    @available(iOS 12.0, *)
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        
    }
    
//    @available(iOS 12.0, *)
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        
    }

//    @available(iOS 15.0, *)
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              restoreUserInterfaceForFullScreenExitWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
    }

//    @available(iOS 15.0, *)
//    func playerViewControllerRestoreUserInterfaceForFullScreenExit(_ playerViewController: AVPlayerViewController) async -> Bool {
//
//    }

//    @available(iOS 8.0, *)
    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        
    }

//    @available(iOS 8.0, *)
    func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        
    }

//    @available(iOS 8.0, *)
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              failedToStartPictureInPictureWithError error: Error) {
        
    }

//    @available(iOS 8.0, *)
    func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        
    }

//    @available(iOS 8.0, *)
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        
    }

//    @available(iOS 8.0, *)
    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
        return true
    }

//    @available(iOS 8.0, *)
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
    }

//    @available(iOS 8.0, *)
    func playerViewControllerRestoreUserInterfaceForPictureInPictureStop(_ playerViewController: AVPlayerViewController) -> Bool {
        return true
    }
}
