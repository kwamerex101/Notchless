import Foundation

/// One of the 9 screen-relative positions a floating HUD panel can occupy,
/// matching MediaMate's layout: {top, middle, bottom} × {left, center, right}.
enum HUDPosition: String, CaseIterable, Codable, StoredValue {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
}
