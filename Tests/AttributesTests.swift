import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttributesTests: QuickSpec {
    
    override func spec() {
        describe("C API") {
            it("provides vm_statistics64 information", closure: {
                expect { try Memory.vmStatistics64() }.toNot(be(vm_statistics64()))
            })
            
            it("provides processor_set_load_info information", closure: {
                expect { try Processor.processorSetLoadInfo() }.toNot(be(processor_set_load_info()))
            })
            
            it("provides [processor_cpu_load_info] information", closure: {
            expect { try Processor.processorCpuLoadInfo() }.toNot(beEmpty())
            })
            
            it("provides mach_task_basic_info information", closure: {
                expect { try Processor.machTaskBasicInfo() }.toNot(be(mach_task_basic_info()))
            })
            
            it("provides task_vm_info information", closure: {
                expect { try Processor.taskVmInfo() }.toNot(be(task_vm_info()))
            })
            
            it("provides task_events_info information", closure: {
                expect { try Processor.taskEventsInfo() }.toNot(be(task_events_info()))
            })
        }
    }
}
