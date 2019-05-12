import Foundation

// MARK: - Processor statistics
struct Processor {
    let cpuTicks: CpuTicks
    let taskBasicInfo: mach_task_basic_info
    let taskEventsInfo: task_events_info
    let processorSetLoadInfo: processor_set_load_info
    
    init() throws {
        self.cpuTicks = try Processor.processorCpuLoadInfo()
            .map(\.cpu_ticks)
            .map(CpuTicks.init(cpu_tick:))
            .reduce(CpuTicks(), +)
        self.taskBasicInfo = try Processor.taskInfo()
        self.taskEventsInfo = try Processor.taskInfo()
        self.processorSetLoadInfo = try Processor.processorSetLoadInfo()
    }
}

// MARK: - Error type
enum KernError: Error {
    case code(_ value: Int32)
    case unexpected
}

// MARK: - Task info protocol
protocol TaskInfoType {
    init()
    static var flavor: Int32 { get }
}

extension mach_task_basic_info: TaskInfoType {
    static var flavor: Int32 {
        return MACH_TASK_BASIC_INFO
    }
}

extension task_events_info: TaskInfoType {
    static var flavor: Int32 {
        return TASK_EVENTS_INFO
    }
}

// MARK: - Low level API functions 
extension Processor {
    
    static func taskInfo<T: TaskInfoType>() throws -> T {
        var info = T()
        var count = mach_msg_type_number_t(MemoryLayout<T>.stride / MemoryLayout<natural_t>.stride)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { (pointer) -> kern_return_t in
            task_info(mach_task_self_,
                      task_flavor_t(T.flavor),
                      pointer.withMemoryRebound(to: Int32.self, capacity: 1) { task_info_t($0) },
                      &count)
        }
        guard kerr == KERN_SUCCESS else {
            throw KernError.code(kerr)
        }
        
        return info
    }
    
    static func processorSetLoadInfo() throws -> processor_set_load_info {
        var pset = processor_set_name_t()
        var result = processor_set_default(mach_host_self(), &pset)
        guard result == KERN_SUCCESS else {
            throw KernError.code(result)
        }
        var count = mach_msg_type_number_t(MemoryLayout<processor_set_load_info>.stride/MemoryLayout<natural_t>.stride)
        var processorSetLoadInfo = processor_set_load_info()
        result = withUnsafeMutablePointer(to: &processorSetLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                processor_set_statistics(pset, PROCESSOR_SET_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw KernError.code(result)
        }
        return processorSetLoadInfo
    }
    
    static func processorCpuLoadInfo() throws -> [processor_cpu_load_info] {
        var processorCpuLoadArray = processor_info_array_t(bitPattern: 0)
        var processorMsgCount = mach_msg_type_name_t()
        var processorCount = natural_t()
        
        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &processorCount,
                                         &processorCpuLoadArray,
                                         &processorMsgCount)
        guard result == KERN_SUCCESS else {
            throw KernError.code(result)
        }
        
        guard let cpuLoadArray = processorCpuLoadArray else {
            throw KernError.unexpected
        }
        let capacity = Int(processorCount) * MemoryLayout<processor_cpu_load_info>.size
        let cpuLoad = cpuLoadArray.withMemoryRebound(to: processor_cpu_load_info.self, capacity: capacity) { $0 }
        return (0..<Int(processorCount)).map { cpuLoad[$0] }
    }
}

// MARK: - CPU ticks
extension Processor {
    struct CpuTicks {
        let user: UInt
        let system: UInt
        let idle: UInt
        let nice: UInt
        
        init(_ user: UInt = 0, _ system: UInt = 0, _ idle: UInt = 0, _ nice: UInt = 0) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
        
        //swiftlint:disable identifier_name large_tuple
        init(cpu_tick: (UInt32, UInt32, UInt32, UInt32)) {
            //swiftlint:enable identifier_name large_tuple
            self.init(UInt(cpu_tick.0),
                      UInt(cpu_tick.1),
                      UInt(cpu_tick.2),
                      UInt(cpu_tick.3))
        }
        
        static func + (lhs: CpuTicks, rhs: CpuTicks) -> CpuTicks {
            return CpuTicks(lhs.user + rhs.user, lhs.system + rhs.system, lhs.idle + rhs.idle, lhs.nice + rhs.nice)
        }
    }
}
