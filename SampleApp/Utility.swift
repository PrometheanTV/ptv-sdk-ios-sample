//
//  Utility.swift
//  Promethean TV, Inc.
//
//  Created by Promethean TV, Inc. on 01/30/2020.
//  Copyright © 2020 Promethean TV, Inc. All rights reserved.
//

import Foundation

class Utility: NSObject {
  
  private static var timeHMSFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.allowedUnits = [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter
  }()
  
  static func formatSecondsToHMS(_ seconds: Double) -> String {
    return timeHMSFormatter.string(from: seconds) ?? "00:00"
  }
  
}
