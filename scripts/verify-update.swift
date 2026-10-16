import Foundation
import CryptoKit

// Independently verify both public release assets using the key embedded in the app.
// The signing tool's success alone isn't enough: CI might hold the wrong private key.
do {
    guard CommandLine.arguments.count == 3,
          let rawKey = Data(base64Encoded: CommandLine.arguments[2]) else { throw CocoaError(.fileReadCorruptFile) }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    let feed = try Data(contentsOf: directory.appendingPathComponent("appcast.xml"))
    guard let boundary = feed.range(of: Data("<!-- sparkle-signatures:".utf8), options: .backwards) else { throw CocoaError(.fileReadCorruptFile) }
    let trailer = String(decoding: feed[boundary.lowerBound...], as: UTF8.self)
    func field(_ name: String) -> String? {
        trailer.components(separatedBy: "\n").first { $0.hasPrefix(name + ": ") }.map { String($0.dropFirst(name.count + 2)) }
    }
    guard let length = field("length").flatMap(Int.init), length == boundary.lowerBound,
          let signature = field("edSignature").flatMap({ Data(base64Encoded: $0) }),
          key.isValidSignature(signature, for: feed.prefix(length)) else { throw CocoaError(.fileReadCorruptFile) }
    let xml = try XMLDocument(data: Data(feed.prefix(length)))
    guard let enclosure = try xml.nodes(forXPath: "/rss/channel/item/enclosure").first as? XMLElement,
          let archiveSignature = enclosure.attribute(forLocalName: "edSignature", uri: "http://www.andymatuschak.org/xml-namespaces/sparkle")?.stringValue.flatMap({ Data(base64Encoded: $0) }) else { throw CocoaError(.fileReadCorruptFile) }
    let archive = try Data(contentsOf: directory.appendingPathComponent("GitGaze.zip"), options: .mappedIfSafe)
    guard key.isValidSignature(archiveSignature, for: archive) else { throw CocoaError(.fileReadCorruptFile) }
    print("Verified appcast and archive Ed25519 signatures against the app's public key.")
} catch {
    fputs("Update signature verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
