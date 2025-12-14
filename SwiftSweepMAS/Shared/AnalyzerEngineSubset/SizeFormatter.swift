import Foundation

/// Utility for formatting file sizes
public struct SizeFormatter {
    public static let shared = SizeFormatter()
    
    private let formatter: ByteCountFormatter
    
    private init() {
        formatter = ByteCountFormatter()
        formatter.countStyle = .file
    }
    
    /// Format byte count to human-readable string
    public func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
    
    /// Format with specific style
    public func format(_ bytes: Int64, style: ByteCountFormatter.CountStyle) -> String {
        let f = ByteCountFormatter()
        f.countStyle = style
        return f.string(fromByteCount: bytes)
    }
}
