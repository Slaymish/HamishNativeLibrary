import Foundation
import CryptoKit

// Verify the archive against the app's embedded PUBLIC key, independent of the secret/tool used to sign it.
guard CommandLine.arguments.count == 4,
      let publicData = Data(base64Encoded: CommandLine.arguments[2]), publicData.count == 32,
      let signature = Data(base64Encoded: CommandLine.arguments[3]), signature.count == 64 else {
    fatalError("Expected ARCHIVE PUBLIC_KEY SIGNATURE with Ed25519 encodings.")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
guard key.isValidSignature(signature, for: archive) else {
    fputs("Update signature does not match the app's public key.\n", stderr)
    exit(1)
}
print("Update signature matches the app's public key.")
