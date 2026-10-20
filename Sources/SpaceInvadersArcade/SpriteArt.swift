import Foundation
import SpaceInvadersCore

/// Original pixel-art bitmaps for the invaders, cannon, and mystery ship.
/// They are stored as strings so the art is readable and editable in source;
/// the renderer expands every `#` into a quad. None of this is ripped from an
/// arcade ROM. The frames are deliberately hand-built homages to the 1978
/// silhouette language.
enum SpriteArt {
    static let squidFrames: [[String]] = [
        [
            "...##...",
            "..####..",
            ".######.",
            "##.##.##",
            "########",
            "..#..#..",
            ".#.##.#.",
            "#.#..#.#",
        ],
        [
            "...##...",
            "..####..",
            ".######.",
            "##.##.##",
            "########",
            ".#.##.#.",
            "#......#",
            ".#....#.",
        ],
    ]

    static let crabFrames: [[String]] = [
        [
            "..#.....#..",
            "...#...#...",
            "..#######..",
            ".##.###.##.",
            "###########",
            "#.#######.#",
            "#.#.....#.#",
            "...##.##...",
        ],
        [
            "..#.....#..",
            "#..#...#..#",
            "#.#######.#",
            "###.###.###",
            "###########",
            ".#########.",
            "..#.....#..",
            ".#.......#.",
        ],
    ]

    static let octopusFrames: [[String]] = [
        [
            "....####....",
            ".##########.",
            "############",
            "###..##..###",
            "############",
            "...##..##...",
            "..##.##.##..",
            "##........##",
        ],
        [
            "....####....",
            ".##########.",
            "############",
            "###..##..###",
            "############",
            "..###..###..",
            ".##..##..##.",
            "..##....##..",
        ],
    ]

    static let cannon: [String] = [
        "......#......",
        ".....###.....",
        ".....###.....",
        ".###########.",
        "#############",
        "#############",
        "#############",
        "#############",
    ]

    static let mysteryShip: [String] = [
        ".....######.....",
        "...##########...",
        "..############..",
        ".##############.",
        "###.##.##.##.###",
        "..#..######..#..",
        "...#........#...",
    ]

    static func frames(for kind: AlienKind) -> [[String]] {
        switch kind {
        case .squid: return squidFrames
        case .crab: return crabFrames
        case .octopus: return octopusFrames
        }
    }
}
