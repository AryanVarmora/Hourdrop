import Foundation
import Testing

/// The tests never use your real drink log, but as a second safety net they must run with
/// a scratch home folder. test.sh sets that up; plain `swift test` fails here instead.
@Test("Tests run with a scratch home folder, so your real drink log can't be reached")
func runsWithScratchHome() {
    let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)
    #expect(NSHomeDirectory() != realHome, "Run the tests with:  bash test.sh")
}
