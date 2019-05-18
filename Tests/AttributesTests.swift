import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttributesTests: QuickSpec {
    
    override func spec() {
        describe("Memory") {
            throwingContext("Exclude from context", closure: {
                it("non-existing file", closure: {
                    expect { try Memory.vmStatistics64() }.toNot(be(vm_statistics64()))
                })
                
                it("non-existing file", closure: {
                    expect { try Processor.processorSetLoadInfo() }.toNot(be(processor_set_load_info()))
                })
                
                it("non-existing file", closure: {
                    expect { try Processor.processorCpuLoadInfo() }.toNot(beEmpty())
                })
                
                it("non-existing file", closure: {
                    expect { try Processor.machTaskBasicInfo() }.toNot(be(mach_task_basic_info()))
                })
                
                it("non-existing file", closure: {
                    expect { try Processor.taskVmInfo() }.toNot(be(task_vm_info()))
                })
                
                it("non-existing file", closure: {
                    expect { try Processor.taskEventsInfo() }.toNot(be(task_events_info()))
                })
            })
        }
    }
}
