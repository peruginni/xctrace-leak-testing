import Foundation
import Testing
@testable import MemoryLeakingApp_iOS

struct MemoryLeakingApp_iOSTests {
    @Test
    func leakingScreenModelIsReleased() {
        weak var model: LeakingScreenModel?

        autoreleasepool {
            let createdModel = LeakingScreenModel()
            model = createdModel
        }

        #expect(model == nil, "LeakingScreenModel leaked")
    }
}
