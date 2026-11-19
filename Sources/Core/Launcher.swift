import Foundation

struct LaunchFailed: Error {}

/// Launches its own executable detached: new session, input and outputs on /dev/null, no wait.
struct Launcher {
  let executable: String
  let environment: [String: String]

  // A child that kept the launcher's channels open would make Claude Code wait.
  func launch(_ arguments: [String]) throws {
    var attributes: posix_spawnattr_t?
    var actions: posix_spawn_file_actions_t?
    posix_spawnattr_init(&attributes)
    posix_spawn_file_actions_init(&actions)
    defer {
      posix_spawnattr_destroy(&attributes)
      posix_spawn_file_actions_destroy(&actions)
    }
    guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID)) == 0 else { throw LaunchFailed() }
    for descriptor: Int32 in 0...2 {
      let flags = descriptor == 0 ? O_RDONLY : O_WRONLY
      guard posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", flags, 0) == 0
      else { throw LaunchFailed() }
    }
    let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { (argv + envp).forEach { free($0) } }
    var pid: pid_t = 0
    guard posix_spawn(&pid, executable, &actions, &attributes, argv, envp) == 0 else { throw LaunchFailed() }
  }
}
