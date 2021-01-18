//
//  ContentView.swift
//  Promethean TV, Inc.
//
//  Created by Promethean TV, Inc. on 01/30/2020.
//  Copyright © 2020 Promethean TV, Inc. All rights reserved.
//

import AVFoundation
import PTVSDK
import SwiftUI

let sampleChannelId = "5c701be7dc3d20080e4092f4"
let sampleStreamId = "5de7e7c2a6adde5211684519"
let sampleVideoUrl = "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8"

// This is the UIView that contains the AVPlayerLayer for rendering the video
class PlayerUIView: UIView {
  private var durationObservation: NSKeyValueObservation?
  private let player: AVPlayer
  private let playerLayer = AVPlayerLayer()
  private let seeking: Binding<Bool>
  private var timeObservation: Any?
  private let videoDuration: Binding<Double>
  private let videoPosition: Binding<Double>
  
  init(player: AVPlayer, seeking: Binding<Bool>, videoDuration: Binding<Double>, videoPosition: Binding<Double>) {
    self.player = player
    self.seeking = seeking
    self.videoDuration = videoDuration
    self.videoPosition = videoPosition
    
    super.init(frame: .zero)
    
    backgroundColor = .black
    playerLayer.player = player
    layer.addSublayer(playerLayer)
    
    // Observe the duration of the player's item so we can display it
    // and use it for updating the seek bar's position
    durationObservation = player.currentItem?.observe(\.duration, changeHandler: { [weak self] item, change in
      guard let self = self else { return }
      self.videoDuration.wrappedValue = item.duration.seconds
    })
    
    // Observe the player's time periodically so we can update the seek bar's
    // position as we progress through playback
    timeObservation = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: nil) { [weak self] time in
      guard let self = self else { return }
      // If we're not seeking currently (don't want to override the slider
      // position if the user is interacting)
      guard !self.seeking.wrappedValue else {
        return
      }
      
      // Update videoPosition with the new video time (as a percentage)
      self.videoPosition.wrappedValue = time.seconds / self.videoDuration.wrappedValue
    }
    
    // Add player observers
    PTVSDK.monitorAVPlayer(player: player)
    
    // Attach config ready callback handler to use
    // stream sources paired in Broadcast Center.
    PTVSDK.onConfigReady = { configData in
      if let sources = configData.sources {
        // Load first playable source from array.
        for source in sources {
          if let url = source.url, AVAsset(url: url).isPlayable {
            self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
            break
          }
        }
      }
    }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    playerLayer.frame = bounds
  }
  
  func cleanUp() {
    // Remove observers we setup in init
    durationObservation?.invalidate()
    durationObservation = nil
    
    if let observation = timeObservation {
      // Remove player observers
      PTVSDK.unmonitorAVPlayer()
      
      player.removeTimeObserver(observation)
      timeObservation = nil
    }
  }
  
}

// This is the SwiftUI view which wraps the UIKit-based PlayerUIView above
struct PlayerView: UIViewRepresentable {
  @Binding private(set) var seeking: Bool
  @Binding private(set) var videoDuration: Double
  @Binding private(set) var videoPosition: Double

  let player: AVPlayer
  
  func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<PlayerView>) {
    // This function gets called if the bindings change, which could be useful if
    // you need to respond to external changes, but we don't in this example
  }
  
  func makeUIView(context: UIViewRepresentableContext<PlayerView>) -> UIView {
    let uiView = PlayerUIView(player: player,
                              seeking: $seeking,
                              videoDuration: $videoDuration,
                              videoPosition: $videoPosition)
    
    // Create overlay data object
    let overlayData = PTVSDKOverlayData(channelId: sampleChannelId,
                                        streamId: sampleStreamId)
    
    // Add overlays to player view
    PTVSDK.addOverlaysToPlayerView(playerView: uiView,
                                   overlayData: overlayData)
    
    return uiView
  }
  
  static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
    guard let playerUIView = uiView as? PlayerUIView else {
      return
    }
    
    playerUIView.cleanUp()
    
    // Remove overlays
    PTVSDK.removeOverlays()
  }
}

// This is the SwiftUI view that contains the controls for the player
struct PlayerControlsView : View {
  @Binding private(set) var seeking: Bool
  @Binding private(set) var videoDuration: Double
  @Binding private(set) var videoPosition: Double
  
  let player: AVPlayer
  
  @State private var playerPaused = true
  
  var body: some View {
    HStack {
      // Play/pause button
      Button(action: togglePlayPause) {
        Image(systemName: playerPaused ? "play.fill" : "pause.fill")
          .font(.system(size: 24, weight: .regular))
          .padding(.trailing, 10)
          .padding(.leading, 10)
      }
      // Current video time
      Text("\(Utility.formatSecondsToHMS(videoPosition * videoDuration))")
      // Slider for seeking / showing video progress
      Slider(value: $videoPosition, in: 0...1, onEditingChanged: sliderEditingChanged)
      // Video duration
      Text("\(Utility.formatSecondsToHMS(videoDuration))")
    }
    .padding(.all, 10)
  }
  
  private func togglePlayPause() {
    pausePlayer(!playerPaused)
  }
  
  private func pausePlayer(_ pause: Bool) {
    playerPaused = pause
    if playerPaused {
      player.pause()
    }
    else {
      player.play()
    }
  }
  
  private func sliderEditingChanged(editingStarted: Bool) {
    if editingStarted {
      // Set a flag stating that we're seeking so the slider doesn't
      // get updated by the periodic time observer on the player
      seeking = true
      pausePlayer(true)
    }
    
    // Do the seek if we're finished
    if !editingStarted {
      let targetTime = CMTime(seconds: videoPosition * videoDuration,
                              preferredTimescale: 600)
      player.seek(to: targetTime) { _ in
        // Now the seek is finished, resume normal operation
        self.seeking = false
        self.pausePlayer(false)
      }
    }
  }
}

// This is the SwiftUI view which contains the player and its controls
struct PlayerContainerView : View {
  // Whether we're currently interacting with the seek bar or doing a seek
  @State private var seeking = false
  // The duration of the video in seconds
  @State private var videoDuration: Double = 0
  // The progress through the video, as a percentage (from 0 to 1)
  @State private var videoPosition: Double = 0
  
  private let player: AVPlayer
  
  init(url: URL) {
    player = AVPlayer(url: url)
  }
  
  var body: some View {
    VStack {
      PlayerView(seeking: $seeking,
                 videoDuration: $videoDuration,
                 videoPosition: $videoPosition,
                 player: player)
      PlayerControlsView(seeking: $seeking,
                         videoDuration: $videoDuration,
                         videoPosition: $videoPosition,
                         player: player)
    }
  }
}

// This is the main SwiftUI view for this app, containing a single PlayerContainerView
struct ContentView: View {
  var body: some View {
    PlayerContainerView(url: URL(string: sampleVideoUrl)!)
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
