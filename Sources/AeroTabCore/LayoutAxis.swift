public enum LayoutAxis: Equatable, Sendable {
    case horizontal, vertical

    public init?(layoutKind: String?) {
        switch layoutKind {
        case "h_tiles", "h_accordion": self = .horizontal
        case "v_tiles", "v_accordion": self = .vertical
        default: return nil
        }
    }

    var opposite: LayoutAxis { self == .horizontal ? .vertical : .horizontal }
}
