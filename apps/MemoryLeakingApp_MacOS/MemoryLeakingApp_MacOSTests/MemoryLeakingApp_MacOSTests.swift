import Foundation
import Testing
@testable import MemoryLeakingApp_MacOS

struct MemoryLeakingApp_MacOSTests {
    @Test
    func leakingScreenModelIsReleased() {
        weak var model: MacLeakingScreenModel?

        autoreleasepool {
            let createdModel = MacLeakingScreenModel()
            model = createdModel
        }

        #expect(model == nil, "MacLeakingScreenModel leaked")
    }
}
