/// Art eras. The game is 3D now and opens cel-shaded (ported from the
/// whats_going_through_your_mind toon kit). Later eras will restyle the same
/// scene; until they exist every ante is cel.
public enum ArtStyle: String, CaseIterable, Hashable, Sendable, Codable {
    case cel

    public static func forAnte(_ ante: Int) -> ArtStyle { .cel }

    public var title: String { "CARTOON ALLEY" }
}
