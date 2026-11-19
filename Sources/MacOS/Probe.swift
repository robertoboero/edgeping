import CoreGraphics
import Foundation

/// Adapter over the non-public CoreGraphics functions: the only file that sees the system dictionaries.
final class CGSProbe: SpaceProbe {
  private typealias MainConnection = @convention(c) () -> Int32
  private typealias DisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
  private typealias WindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

  // Mask of CGSCopySpacesForWindows that asks for every space of the window.
  private static let allSpacesMask: Int32 = 7
  private static let owner = "Code"

  private let connection: Int32
  private let displaySpaces: DisplaySpaces
  private let windowSpaces: WindowSpaces

  init() throws {
    guard let library = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
      let connect = dlsym(library, "CGSMainConnectionID"),
      let displays = dlsym(library, "CGSCopyManagedDisplaySpaces"),
      let windows = dlsym(library, "CGSCopySpacesForWindows")
    else { throw ProbeError() }
    connection = unsafeBitCast(connect, to: MainConnection.self)()
    displaySpaces = unsafeBitCast(displays, to: DisplaySpaces.self)
    windowSpaces = unsafeBitCast(windows, to: WindowSpaces.self)
  }

  func read() throws -> Reading {
    let spaces = try readSpaces()
    guard let list = windowList() else { throw ProbeError() }
    var windows: [CodeWindow] = []
    for entry in codeEntries(list) {
      guard let id = entry[kCGWindowNumber as String] as? Int else { throw ProbeError() }
      let title = entry[kCGWindowName as String] as? String ?? ""
      windows.append(CodeWindow(id: id, title: title, spaces: spacesOf(id)))
    }
    return Reading(spaces: spaces, windows: windows)
  }

  /// One lookup of the recognised window; a failing system call is reported in the result, never thrown.
  func lookup(window: Int) -> (spaces: Spaces?, window: WindowLookup) {
    let spaces = try? readSpaces()
    guard let list = windowList() else {
      return (spaces, WindowLookup(listReadOK: false, listCount: 0, windowSpaces: nil))
    }
    let found = codeEntries(list).contains { ($0[kCGWindowNumber as String] as? Int) == window }
    return (
      spaces,
      WindowLookup(listReadOK: true, listCount: list.count, windowSpaces: found ? spacesOf(window) : nil))
  }

  func reread(window: Int) throws -> Rereading {
    Rereading(spaces: try readSpaces(), windowSpaces: spacesOf(window))
  }

  private func windowList() -> [[String: Any]]? {
    CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
  }

  private func codeEntries(_ list: [[String: Any]]) -> [[String: Any]] {
    list.filter {
      ($0[kCGWindowOwnerName as String] as? String) == Self.owner && ($0[kCGWindowLayer as String] as? Int) == 0
    }
  }

  private func readSpaces() throws -> Spaces {
    guard let displays = displaySpaces(connection)?.takeRetainedValue() as? [[String: Any]],
      !displays.isEmpty
    else { throw ProbeError() }
    var order: [Int] = []
    var currents: [Int] = []
    for display in displays {
      guard let spaces = display["Spaces"] as? [[String: Any]],
        let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
      else { throw ProbeError() }
      for space in spaces {
        guard let id = space["ManagedSpaceID"] as? Int else { throw ProbeError() }
        order.append(id)
      }
      currents.append(current)
    }
    return Spaces(order: order, current: currents[0], displayCount: displays.count)
  }

  // A closed window comes back with no spaces: the logic turns that into probe-failed.
  private func spacesOf(_ window: Int) -> [Int] {
    let answer = windowSpaces(connection, Self.allSpacesMask, [window] as CFArray)
    return answer?.takeRetainedValue() as? [Int] ?? []
  }
}
