import SwiftUI

struct Heading: Identifiable, Equatable {
    let id = UUID()
    let level: Int
    let title: String
    let line: Int
}

struct WorkspaceNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let children: [WorkspaceNode]?

    var id: String { url.path }
}

struct WorkspaceSnapshot {
    let files: [URL]
    let tree: [WorkspaceNode]
    let markdownTree: [WorkspaceNode]
    let markdownCount: Int
}

enum ScrollSource: Equatable {
    case editor
    case preview
    case outline
}

struct ScrollPosition: Equatable {
    var line: Int = 0
    var fraction: Double = 0
}

final class ScrollSyncState: ObservableObject {
    @Published var position = ScrollPosition()
    @Published var source: ScrollSource = .editor
}

enum EditorTheme: String, CaseIterable, Identifiable {
    case paper = "Paper"
    case sepia = "Sepia"
    case midnight = "Midnight"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .paper: return Color(red: 0.975, green: 0.97, blue: 0.955)
        case .sepia: return Color(red: 0.96, green: 0.91, blue: 0.79)
        case .midnight: return Color(red: 0.085, green: 0.095, blue: 0.11)
        }
    }

    var foreground: Color {
        self == .midnight ? Color(red: 0.84, green: 0.86, blue: 0.88) : Color(red: 0.16, green: 0.16, blue: 0.15)
    }

    var accent: Color {
        self == .midnight ? Color(red: 0.41, green: 0.78, blue: 0.70) : Color(red: 0.10, green: 0.48, blue: 0.42)
    }

    var css: String {
        switch self {
        case .paper: return "--bg:#f9f7f2;--fg:#292925;--muted:#817e75;--line:#e7e2d8;--accent:#197a6b;--code:#eeebe4;--syn-key:#b12b5b;--syn-string:#357a38;--syn-comment:#8b8275;--syn-number:#a45c12;--syn-type:#176a86;--syn-tag:#9a431a;"
        case .sepia: return "--bg:#f5e9ca;--fg:#3c3325;--muted:#85745c;--line:#dfcfaa;--accent:#8b5b32;--code:#eadbb8;--syn-key:#9c3154;--syn-string:#51722c;--syn-comment:#91816a;--syn-number:#9a5718;--syn-type:#28647a;--syn-tag:#98472a;"
        case .midnight: return "--bg:#16181c;--fg:#d7dbdf;--muted:#858c94;--line:#2d3138;--accent:#68c7b3;--code:#22262c;--syn-key:#f08db2;--syn-string:#9bd58b;--syn-comment:#77818c;--syn-number:#e7ad72;--syn-type:#7ccbe5;--syn-tag:#f1a47c;"
        }
    }
}

struct WritingStats {
    let words: Int
    let characters: Int
    let minutes: Int

    init(text: String) {
        characters = text.count
        let latin = text.split { $0.isWhitespace || $0.isPunctuation }.count
        let cjk = text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        words = latin + cjk
        minutes = max(1, Int(ceil(Double(max(words, 1)) / 250.0)))
    }
}
