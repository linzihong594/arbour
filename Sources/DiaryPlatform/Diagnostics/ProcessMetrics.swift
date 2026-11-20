import Darwin
import Foundation

public struct ProcessMetrics: Codable, Sendable {
    public let physicalFootprintBytes: UInt64
    public let cpuSeconds: Double

    public static func current() throws -> ProcessMetrics {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw PlatformError.message("无法读取进程物理内存指标。") }
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw PlatformError.message("无法读取进程 CPU 指标。") }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return ProcessMetrics(physicalFootprintBytes: info.phys_footprint, cpuSeconds: user + system)
    }
}
