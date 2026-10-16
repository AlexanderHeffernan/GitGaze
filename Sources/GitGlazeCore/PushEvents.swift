import Foundation

/// Keeps only push session identifiers, never command arguments, paths, or trace logs.
public struct PushEvents: Sendable {
    private var pushes: [String: Date] = [:]
    public init() {}

    public mutating func receive(_ data: Data, now: Date = Date()) -> Bool {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = event["event"] as? String, let sid = event["sid"] as? String else { return false }
        pushes = pushes.filter { now.timeIntervalSince($0.value) < 3600 }
        if kind == "cmd_name", event["name"] as? String == "push" {
            if pushes.count >= 256, let oldest = pushes.min(by: { $0.value < $1.value })?.key { pushes.removeValue(forKey: oldest) }
            pushes[sid] = now
        }
        if kind == "signal" { pushes.removeValue(forKey: sid) }
        guard kind == "exit", pushes.removeValue(forKey: sid) != nil else { return false }
        return event["code"] as? Int == 0
    }
}
