import Foundation

/// Structured error codes for Helper operations
public enum HelperError: Int, Error, CustomNSError, Sendable {
    case notAllowedPath = 1001
    case symlinkEscape = 1002
    case fileNotFound = 1003
    case permissionDenied = 1004
    case immutableFile = 1005
    case readOnlyFS = 1006
    case directoryNotEmpty = 1007
    case unknown = 9999
    
    public static var errorDomain: String { "com.swiftsweep.helper" }
    public var errorCode: Int { rawValue }
    public var errorUserInfo: [String: Any] { [:] }
    
    public var description: String {
        switch self {
        case .notAllowedPath: return "Path not in allowed list"
        case .symlinkEscape: return "Symlink escape detected"
        case .fileNotFound: return "File not found"
        case .permissionDenied: return "Permission denied"
        case .immutableFile: return "File is immutable"
        case .readOnlyFS: return "Read-only filesystem"
        case .directoryNotEmpty: return "Directory not empty"
        case .unknown: return "Unknown error"
        }
    }
    
    /// Map errno to HelperError
    public static func fromErrno(_ err: Int32) -> HelperError {
        switch err {
        case ENOENT: return .fileNotFound
        case EACCES, EPERM: return .permissionDenied
        case EROFS: return .readOnlyFS
        case ELOOP: return .symlinkEscape
        case ENOTEMPTY: return .directoryNotEmpty
        default: return .unknown
        }
    }
}
