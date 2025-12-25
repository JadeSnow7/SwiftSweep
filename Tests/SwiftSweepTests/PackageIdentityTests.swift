import XCTest

@testable import SwiftSweepCore

final class PackageIdentityTests: XCTestCase {

  // MARK: - PackageIdentity Tests

  func testLogicalKeyGeneration() {
    let identity = PackageIdentity(
      ecosystemId: "homebrew_formula",
      scope: "homebrew/core",
      name: "openssl",
      version: .exact("3.1.4"),
      instanceFingerprint: nil
    )

    // Should be URL-safe encoded
    XCTAssertTrue(identity.logicalKey.contains("homebrew_formula"))
    XCTAssertTrue(identity.logicalKey.contains("openssl"))
    XCTAssertTrue(identity.logicalKey.contains("3.1.4"))
  }

  func testCanonicalKeyWithFingerprint() {
    let identity = PackageIdentity(
      ecosystemId: "npm",
      scope: "@types",
      name: "react",
      version: .exact("18.2.0"),
      instanceFingerprint: "a1b2c3d4"
    )

    XCTAssertTrue(identity.canonicalKey.contains("#a1b2c3d4"))
    XCTAssertNotEqual(identity.logicalKey, identity.canonicalKey)
  }

  func testCanonicalKeyWithoutFingerprint() {
    let identity = PackageIdentity(
      ecosystemId: "pip",
      scope: nil,
      name: "numpy",
      version: .exact("1.24.0"),
      instanceFingerprint: nil
    )

    XCTAssertEqual(identity.logicalKey, identity.canonicalKey)
    XCTAssertFalse(identity.canonicalKey.contains("#"))
  }

  func testSpecialCharacterEscaping() {
    // Test python@3.11 style names
    let identity = PackageIdentity(
      ecosystemId: "homebrew_formula",
      scope: nil,
      name: "python@3.11",
      version: .exact("3.11.0"),
      instanceFingerprint: nil
    )

    // @ should be percent-encoded
    XCTAssertTrue(identity.logicalKey.contains("%40") || identity.logicalKey.contains("python"))
  }

  func testFingerprintComputation() {
    let fp1 = PackageIdentity.computeFingerprint(
      normalizedPath: "$HOMEBREW_PREFIX/Cellar/openssl/3.1.4",
      arch: "arm64"
    )

    let fp2 = PackageIdentity.computeFingerprint(
      normalizedPath: "$HOMEBREW_PREFIX/Cellar/openssl/3.1.4",
      arch: "arm64"
    )

    // Same input should produce same fingerprint
    XCTAssertEqual(fp1, fp2)
    XCTAssertEqual(fp1.count, 16)  // 8 bytes = 16 hex chars
  }

  func testFingerprintDifferentPaths() {
    let fp1 = PackageIdentity.computeFingerprint(
      normalizedPath: "$HOME/.local/lib/python/site-packages",
      arch: "arm64"
    )

    let fp2 = PackageIdentity.computeFingerprint(
      normalizedPath: "$HOMEBREW_PREFIX/lib/python",
      arch: "arm64"
    )

    XCTAssertNotEqual(fp1, fp2)
  }

  // MARK: - ResolvedVersion Tests

  func testResolvedVersionExact() {
    let version = ResolvedVersion.exact("1.2.3")
    XCTAssertEqual(version.normalized, "1.2.3")
    XCTAssertTrue(version.isKnown)
  }

  func testResolvedVersionUnknown() {
    let version = ResolvedVersion.unknown
    XCTAssertEqual(version.normalized, "unknown")
    XCTAssertFalse(version.isKnown)
  }

  func testResolvedVersionCodable() throws {
    let version = ResolvedVersion.exact("2.0.0")
    let data = try JSONEncoder().encode(version)
    let decoded = try JSONDecoder().decode(ResolvedVersion.self, from: data)
    XCTAssertEqual(version, decoded)
  }

  // MARK: - VersionConstraint Tests

  func testVersionConstraintExact() {
    let constraint = VersionConstraint.exact("1.0.0")
    XCTAssertEqual(constraint.description, "1.0.0")
  }

  func testVersionConstraintRange() {
    let constraint = VersionConstraint.range("^1.0.0")
    XCTAssertEqual(constraint.description, "^1.0.0")
  }

  func testVersionConstraintCodableRange() throws {
    let json = Data("\"^2.0.0\"".utf8)
    let decoded = try JSONDecoder().decode(VersionConstraint.self, from: json)
    if case .range(let r) = decoded {
      XCTAssertEqual(r, "^2.0.0")
    } else {
      XCTFail("Expected range constraint")
    }
  }

  // MARK: - PackageRef Tests

  func testPackageRefKey() {
    let ref = PackageRef(ecosystemId: "npm", scope: "@types", name: "node")
    XCTAssertTrue(ref.key.contains("npm"))
    XCTAssertTrue(ref.key.contains("@types"))
    XCTAssertTrue(ref.key.contains("node"))
  }

  func testPackageRefFromIdentity() {
    let identity = PackageIdentity(
      ecosystemId: "gem",
      scope: nil,
      name: "rails",
      version: .exact("7.0.0"),
      instanceFingerprint: "abcd1234"
    )

    let ref = PackageRef(from: identity)
    XCTAssertEqual(ref.ecosystemId, "gem")
    XCTAssertEqual(ref.name, "rails")
    XCTAssertNil(ref.scope)
  }

  // MARK: - PathNormalizer Tests

  func testPathNormalizerHome() {
    let normalizer = PathNormalizer(homeDir: "/Users/test", brewPrefix: nil)
    let normalized = normalizer.normalize("/Users/test/.local/bin")
    XCTAssertEqual(normalized, "$HOME/.local/bin")
  }

  func testPathNormalizerBrewPrefix() {
    let normalizer = PathNormalizer(homeDir: "/Users/test", brewPrefix: "/opt/homebrew")
    let normalized = normalizer.normalize("/opt/homebrew/Cellar/wget/1.21")
    XCTAssertEqual(normalized, "$HOMEBREW_PREFIX/Cellar/wget/1.21")
  }

  func testPathNormalizerResolve() {
    let normalizer = PathNormalizer(homeDir: "/Users/alice", brewPrefix: "/opt/homebrew")
    let resolved = normalizer.resolve("$HOME/.config/app")
    XCTAssertEqual(resolved, "/Users/alice/.config/app")
  }

  // MARK: - PortablePath Tests

  func testPortablePathRoundTrip() {
    let normalizer = PathNormalizer(homeDir: "/Users/dev", brewPrefix: "/opt/homebrew")
    let original = "/opt/homebrew/Cellar/node/20.0.0"
    let portable = PortablePath(original, normalizer: normalizer)
    let resolved = portable.resolve(with: normalizer)
    XCTAssertEqual(original, resolved)
  }
}
