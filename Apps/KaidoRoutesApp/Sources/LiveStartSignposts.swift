import OSLog
import UIKit

/// Signpost intervals for the start of a live drive, under one category so
/// Instruments shows them together. The start runs on the main thread between
/// the tap and the first live frame; these say where that time goes on a
/// device, where no probe build is installed.
@MainActor
enum LiveStartSignposts {
  static let signposter = OSSignposter(subsystem: "app.kaidoroutes", category: "LiveStart")

  private static var phaseChangeLink: UIUpdateLink?

  /// Times the frame that carries the switch to the driving phase in two
  /// intervals: from the phase change to the start of that frame's commit
  /// (the SwiftUI update), then the commit itself. A passive update link
  /// observes the next UI update without asking for one.
  static func measurePhaseChange() {
    guard
      let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene }).first
    else { return }
    let id = signposter.makeSignpostID()
    let update = signposter.beginInterval("Phase update", id: id)
    var commit: OSSignpostIntervalState?
    let link = UIUpdateLink(windowScene: scene)
    link.addAction(to: .beforeCATransactionCommit) { _, _ in
      guard commit == nil else { return }
      signposter.endInterval("Phase update", update)
      commit = signposter.beginInterval("First frame commit", id: id)
    }
    link.addAction(to: .afterCATransactionCommit) { link, _ in
      guard let started = commit else { return }
      signposter.endInterval("First frame commit", started)
      link.isEnabled = false
      phaseChangeLink = nil
    }
    link.isEnabled = true
    phaseChangeLink = link
  }
}
