import Foundation

/// One of the 9 screen-relative positions a floating HUD panel can occupy,
/// matching MediaMate's layout: {top, middle, bottom} × {left, center, right}.
enum HUDPosition: String, CaseIterable, Codable, StoredValue {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left";      case .top: return "Top";       case .topRight: return "Top Right"
        case .left: return "Left";             case .center: return "Center"; case .right: return "Right"
        case .bottomLeft: return "Bottom Left"; case .bottom: return "Bottom"; case .bottomRight: return "Bottom Right"
        }
    }
}
