//
//  MemoryLeakingAppTests.swift
//  MemoryLeakingAppTests
//
//  Created for the sample project.
//

import Testing
import Foundation
@testable import MemoryLeakingApp

struct MemoryLeakingAppTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test
    func viewModelDoesNotLeak() {
        expectNoLeak {
            LeakingObject()
        }
    }
}

func expectNoLeak<T: AnyObject>(
    _ factory: () -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    weak var weakObject: T?
    
    autoreleasepool {
        let object = factory()
        weakObject = object
    }
    
    #expect(
        weakObject == nil,
        sourceLocation: sourceLocation
    )
}


final class LeakingObject {
    
    var closure: (() -> Void)?
    
    init() {
        closure = {
            self.doSomething()
        }
        
    }
    
    private func doSomething() {}
    
}
