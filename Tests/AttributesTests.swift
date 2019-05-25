import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttributesTests: QuickSpec {
    
    override func spec() {
        describe("C API") {
            it("provides vm_statistics64 information", closure: {
                expect { try Statistics.vmStatistics64() }.toNot(be(vm_statistics64()))
            })
            
            it("provides processor_set_load_info information", closure: {
                expect { try Statistics.processorSetLoadInfo() }.toNot(be(processor_set_load_info()))
            })
            
            it("provides [host_cpu_load_info] information", closure: {
            expect { try Statistics.hostCpuLoadInfo() }.toNot(be(host_cpu_load_info()))
            })
            
            it("provides mach_task_basic_info information", closure: {
                expect { try Statistics.machTaskBasicInfo() }.toNot(be(mach_task_basic_info()))
            })
            
            it("provides task_vm_info information", closure: {
                expect { try Statistics.taskVmInfo() }.toNot(be(task_vm_info()))
            })
            
            it("provides task_events_info information", closure: {
                expect { try Statistics.taskEventsInfo() }.toNot(be(task_events_info()))
            })
        }
    }
}
