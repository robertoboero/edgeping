// Component and unit tests of StayMachine, VisitTracker, ClosureTracker and classify (Sources/Core/Placement.swift), without AppKit.
import Foundation

runClassifyTests()
runVisitTrackerTests()
runClosureTrackerTests()
runMachineClosureTests()
runMachineVisitTests()
runMachineRecoveryTests()
runMachineReplacementTests()
runMachineFullSideTests()

print("PASSED: \(passed) FAILED: \(failed)")
exit(failed == 0 ? 0 : 1)
