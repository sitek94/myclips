// Seeds a throwaway store with synthetic clips and reports search latency.
// usage: clips-bench [count]
import MyClipsCore
import Foundation

let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 100_000
let dir = FileManager.default.temporaryDirectory.appending(path: "clips-bench-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: dir) }
let store = try Store(url: dir.appending(path: "clips.sqlite"))

let words = """
    the of and to in is for on that with as was at by from this be or an are which have not it has but \
    meeting invoice project budget deploy server release customer ticket dashboard report review design \
    garden river coffee window planet guitar sensor reading device sync account password token order shipping \
    café naïve résumé Zürich Kraków
    """.split(separator: " ").map(String.init)

func sentence(_ n: Int) -> String {
    (0..<n).map { _ in words.randomElement()! }.joined(separator: " ")
}

func payload(_ i: Int) -> ClipPayload {
    let text: String = switch i % 10 {
    case 0: "https://example.com/\(sentence(3).replacingOccurrences(of: " ", with: "/"))?id=\(i)"
    case 1: "unique-\(i) " + sentence(4)
    default: sentence(Int.random(in: 5...60)) + " #\(i)"
    }
    return ClipPayload(
        kind: .text, text: text,
        representations: [Representation(item: 0, type: "public.utf8-plain-text", data: Data(text.utf8))],
        sourceBundleID: "com.example.app\(i % 7)"
    )
}

let start = ContinuousClock.now
for i in 0..<count {
    try await store.record(payload(i), at: Date(timeIntervalSince1970: Double(i)))
}
print("seeded \(count) clips in \(ContinuousClock.now - start)")

let queries = ["", "a", "zz", "the", "deploy", "guitar sensor", "cafe", "unique-\(count / 2 + 1)", "https example", "no-such-text-anywhere"]
for query in queries {
    var samples: [Duration] = []
    var hits = 0
    for _ in 0..<30 {
        let t = ContinuousClock.now
        hits = try await store.clips(matching: query).count
        samples.append(ContinuousClock.now - t)
    }
    samples.sort()
    let ms = { (d: Duration) in String(format: "%.2f ms", Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000) }
    print("\(query.isEmpty ? "<empty>" : query)".padding(toLength: 24, withPad: " ", startingAt: 0),
          "hits \(hits)".padding(toLength: 10, withPad: " ", startingAt: 0),
          "p50 \(ms(samples[samples.count / 2]))", " p95 \(ms(samples[samples.count * 95 / 100]))")
}
