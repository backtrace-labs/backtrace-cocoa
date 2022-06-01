import XCTest

import Nimble
import Quick
#if SWIFT_PACKAGE
public typealias FileString = StaticString
#else
public typealias FileString = String
#endif
// MARK: Throwing extension for most common Quick methods.

/**
 A closure executed before an example is run.
 */
public typealias ThrowingBeforeExampleClosure = () throws -> Void

/**
 A closure executed before an example is run. The closure is given example metadata,
 which contains information about the example that is about to be run.
 */
public typealias ThrowingBeforeExampleWithMetadataClosure = (_ exampleMetadata: ExampleMetadata) throws -> Void

/**
 A closure executed after an example is run.
 */
public typealias ThrowingAfterExampleClosure = ThrowingBeforeExampleClosure

/**
 A closure executed after an example is run. The closure is given example metadata,
 which contains information about the example that has just finished running.
 */
public typealias ThrowingAfterExampleWithMetadataClosure = ThrowingBeforeExampleWithMetadataClosure

// MARK: Suite Hooks

/**
 A closure executed before any examples are run.
 */
public typealias ThrowingBeforeSuiteClosure = ThrowingBeforeExampleClosure

/**
 A closure executed after all examples have finished running.
 */
public typealias ThrowingAfterSuiteClosure = ThrowingBeforeSuiteClosure

public func throwingContext(_ description: String, flags: FilterFlags = [:], closure: () throws -> Void) {
    context(description, flags: flags) {
        do {
            try closure()
        } catch {
            fail(error.localizedDescription)
        }
    }
}

public func throwingIt(_ description: String, flags: FilterFlags = [:], file: FileString = #file, line: UInt = #line,
                       closure: @escaping () throws -> Void) {
    it(description, flags: flags, file: file, line: line) {
        do {
            try closure()
        } catch {
            fail(error.localizedDescription, line: line)
        }
    }
}

public func throwingBeforeEach(_ closure: @escaping ThrowingBeforeExampleClosure) {
    beforeEach {
        do {
            try closure()
        } catch {
            fail(error.localizedDescription)
        }
    }
}

/**
 Identical to Quick.DSL.beforeEach, except the closure is provided with
 metadata on the example that the closure is being run prior to.
 */
public func throwingBeforeEach(_ closure: @escaping ThrowingBeforeExampleWithMetadataClosure) {
    beforeEach { (exampleMetadata) in
        do {
            try closure(exampleMetadata)
        } catch {
            fail(error.localizedDescription)
        }
    }
}

/**
 Defines a closure to be run after each example in the current example
 group. This closure is not run for pending or otherwise disabled examples.
 An example group may contain an unlimited number of afterEach. They'll be
 run in the order they're defined, but you shouldn't rely on that behavior.
 
 - parameter closure: The closure to be run after each example.
 */
public func throwingAfterEach(_ closure: @escaping ThrowingAfterExampleClosure) {
    afterEach {
        do {
            try closure()
        } catch {
            fail(error.localizedDescription)
        }
    }
}

/**
 Identical to Quick.DSL.afterEach, except the closure is provided with
 metadata on the example that the closure is being run after.
 */
public func throwignAfterEach(_ closure: @escaping ThrowingAfterExampleWithMetadataClosure) {
    afterEach { (exampleMetadata) in
        do {
            try closure(exampleMetadata)
        } catch {
            fail(error.localizedDescription)
        }
    }
}

/**
 Defines a closure to be run prior to any examples in the test suite.
 You may define an unlimited number of these closures, but there is no
 guarantee as to the order in which they're run.
 
 If the test suite crashes before the first example is run, this closure
 will not be executed.
 
 - parameter closure: The closure to be run prior to any examples in the test suite.
 */
public func throwingBeforeSuite(_ closure: @escaping ThrowingBeforeSuiteClosure) {
    beforeSuite {
        do {
            try closure()
        } catch {
            fail(error.localizedDescription)
        }
    }
}

/**
 Defines a closure to be run after all of the examples in the test suite.
 You may define an unlimited number of these closures, but there is no
 guarantee as to the order in which they're run.
 
 If the test suite crashes before all examples are run, this closure
 will not be executed.
 
 - parameter closure: The closure to be run after all of the examples in the test suite.
 */
public func throwingAfterSuite(_ closure: @escaping ThrowingAfterSuiteClosure) {
    afterSuite {
        do {
            try closure()
        } catch {
            fail(error.localizedDescription)
        }
    }
}
