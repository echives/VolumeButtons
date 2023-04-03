//
//  VolumeButtonHandler.swift
//
//  Created by Anton Glezman on 24.01.2020.
//

import AVFoundation
import Foundation
import MediaPlayer
import RxSwift

/// Class for handle clicks on hardware volume buttons.
///
/// Keeps track of volume changes in an audio session. When you increase or decrease the volume level,
/// the value will be reset to the initial one, thus pressing the buttons is determined without changing
/// the volume of the media player.
public final class VolumeButtonHandler: NSObject {

    // MARK: - Types

    public typealias ButtonHandler = () -> Void

    // MARK: - Public properties

    /// The closure for handle the button clicks
    public var buttonClosure: ButtonHandler?

    /// Preconditions
    public var checkPreconditions: (() -> Bool)?

    /// This flag indicates whether audio session observation is running.
    public private(set) var isStarted: Bool = false

    // MARK: - Private properties

    /// avoid Rx cycle caused by setInitialVolume
    private var isProcessing: Bool = false
    private var appIsActive: Bool = true
    private var session: AVAudioSession?
    private var sessionCategory: AVAudioSession.Category = .playback
    private var sessionOptions: AVAudioSession.CategoryOptions = .mixWithOthers
    private var volumeView: MPVolumeView
    private var notificationSequenceNumbers = Set<Int>()
    private var lockVolume: Float = 0
    private var bag = DisposeBag()

    // MARK: - Init

    /// - Parameters:
    ///   - containerView: The UIView for placing hidden MPVolumeView instance
    ///   - buttonClosure: The closure for handle button clicks
    public init(containerView: UIView, buttonClosure: ButtonHandler? = nil) {
        self.buttonClosure = buttonClosure
        self.volumeView = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 0, height: 0))
        super.init()
        containerView.addSubview(volumeView)
        containerView.sendSubviewToBack(volumeView)
        volumeView.alpha = 0.01
    }

    deinit {
        stop()
        volumeView.removeFromSuperview()
    }

    // MARK: - Public methods

    /// Start volume button handling
    public func start() {
        setupSession()
    }

    /// Stop volume button handling
    public func stop() {
        guard isStarted else { return }
        bag = DisposeBag()
        try? session?.setActive(false)
        session = nil
        isStarted = false
    }

    // MARK: - Private methods
    func setupSession() {
        guard !isStarted else { return }
        isStarted = true

        let session = AVAudioSession.sharedInstance()
        // this must be done before calling setCategory or else the initial volume is reset
        lockVolume = session.outputVolume
        setInitialVolume()
        do {
            try session.setCategory(sessionCategory, options: sessionOptions)
            try session.setActive(true)
        } catch {
            return
        }

        // Audio session is interrupted when you send the app to the background,
        // and needs to be set to active again when it goes to app goes back to the foreground

        Observable.merge(
            NotificationCenter.default.rx.notification(UIApplication.willResignActiveNotification),
            NotificationCenter.default.rx.notification(UIApplication.didBecomeActiveNotification)
        )
            .subscribe(onNext: { [weak self] notification in
                self?.appIsActive = (notification.name == UIApplication.didBecomeActiveNotification)
            })
            .disposed(by: bag)

        NotificationCenter.default.rx.notification(AVAudioSession.interruptionNotification)
            .subscribe(onNext: { [weak self] notification in
                guard
                    let interuptionDict = notification.userInfo,
                    let rawInteruptionType = interuptionDict[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let interuptionType = AVAudioSession.InterruptionType(rawValue: rawInteruptionType)
                else {
                    return
                }
                switch interuptionType {
                case .ended:
                    try? self?.session?.setActive(true)
                default:
                    break
                }
            })
            .disposed(by: bag)

        // Volume Observe
        if #available(iOS 15, *) {
            NotificationCenter.default.rx.notification(NSNotification.Name(rawValue: "SystemVolumeDidChange"))
                .observeOn(MainScheduler.asyncInstance)
                .filter({ [weak self] _ in
                    guard let self = self else { return false }
                    return !self.isProcessing && self.isStarted && self.appIsActive
                })
                .subscribe(onNext: { [weak self] notification in
                    guard
                        let self = self,
                        self.checkPreconditions?() ?? true
                    else { return }
                    // check notification reason
                    guard
                        let volumeChangeType = notification.userInfo?["Reason"] as? String,
                        volumeChangeType == "ExplicitVolumeChange",
                        let sequenceNumber = notification.userInfo?["SequenceNumber"] as? Int
                    else { return }
                    if !self.notificationSequenceNumbers.contains(sequenceNumber) {
                        self.notificationSequenceNumbers.insert(sequenceNumber)
                        self.isProcessing = true
                        self.buttonClosure?()
                        self.setInitialVolume()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.isProcessing = false
                        }
                    }
                })
                .disposed(by: bag)
        } else {
            NotificationCenter.default.rx.notification(NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"))
                .observeOn(MainScheduler.asyncInstance)
                .filter({ [weak self] _ in
                    guard let self = self else { return false }
                    return !self.isProcessing && self.isStarted && self.appIsActive
                })
                .subscribe(onNext: { [weak self] notification in
                    guard
                        let self = self,
                        self.checkPreconditions?() ?? true
                    else { return }
                    // check notification reason
                    guard
                        let volumeChangeType = notification.userInfo?["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String,
                        volumeChangeType == "ExplicitVolumeChange"
                    else { return }
                    self.isProcessing = true
                    self.buttonClosure?()
                    self.setInitialVolume()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isProcessing = false
                    }
                })
                .disposed(by: bag)
        }

        self.session = session
    }

    private func setInitialVolume() {
        guard let session = session else { return }
        setSystemVolume(lockVolume)
    }

    private func setSystemVolume(_ volume: Float) {
        // find the volumeSlider
        let volumeViewSlider = volumeView.subviews.first { $0 is UISlider } as? UISlider
        volumeViewSlider?.value = volume
    }
}
