import Foundation
import KaidoNavigation

enum SurfaceManeuver: Equatable {
  case left, right, slightLeft, slightRight, straight, uTurn, unknown

  var symbol: String {
    switch self {
    case .left: "arrow.turn.up.left"
    case .right: "arrow.turn.up.right"
    case .slightLeft: "arrow.up.left"
    case .slightRight: "arrow.up.right"
    case .straight: "arrow.up"
    case .uTurn: "arrow.uturn.down"
    case .unknown: "mappin.and.ellipse"
    }
  }

  // MapKit supplies localized text, not a maneuver enum. Match only an
  // explicit leading action; a direction inside a street name is not a turn.
  static func from(instruction: String) -> Self {
    let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let actions: [(Self, [String])] = [
      (.slightLeft, ["slight left", "bear left", "keep left", "稍向左", "靠左", "左方向", "斜め左"]),
      (.slightRight, ["slight right", "bear right", "keep right", "稍向右", "靠右", "右方向", "斜め右"]),
      (.uTurn, ["make a u-turn", "make a u turn", "u-turn", "掉头", "掉頭", "uターン"]),
      (.left, ["turn left", "左转", "左轉", "向左转", "向左轉", "左折"]),
      (.right, ["turn right", "右转", "右轉", "向右转", "向右轉", "右折"]),
      (.straight, ["continue straight", "continue on", "head straight", "直行", "继续直行", "繼續直行", "そのまま", "直進"]),
    ]
    for (maneuver, prefixes) in actions {
      for prefix in prefixes where text.hasPrefix(prefix) {
        let remainder = text.dropFirst(prefix.count)
        if prefix.last?.isASCII == true,
          let next = remainder.first, next.isLetter
        { continue }
        return maneuver
      }
    }
    return .unknown
  }
}

enum NavigationDirectionPresentation {
  static func screenAngle(bearing: Double, cameraHeading: Double, cameraPitch: Double) -> Double {
    let relative = (bearing - cameraHeading) * .pi / 180
    let pitch = cameraPitch * .pi / 180
    return atan2(sin(relative), cos(relative) * cos(pitch)) * 180 / .pi
  }

  static func vehicleCourse(from observation: RouteMatcherObservation) -> Double? {
    guard let course = observation.courseDegrees,
      course.isFinite, (0..<360).contains(course),
      let accuracy = observation.courseAccuracyDegrees,
      accuracy.isFinite, (0...30).contains(accuracy),
      let speed = observation.speedMetersPerSecond,
      speed.isFinite, speed > 1.5,
      observation.horizontalAccuracyMeters > 0,
      observation.horizontalAccuracyMeters < 30,
      (0..<10_000).contains(observation.receivedAtMilliseconds - observation.observedAtMilliseconds)
    else { return nil }
    return course
  }
}
