import Darwin
import Foundation

final class AppResourceMonitor {
    static let shared = AppResourceMonitor()

    func sample() -> AppResourceStats {
        AppResourceStats(
            cpuPercent: currentCPUPercent(),
            residentMemoryBytes: currentResidentMemoryBytes(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    private func currentCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let task = mach_task_self_

        guard task_threads(task, &threadList, &threadCount) == KERN_SUCCESS,
              let threadList else {
            return 0
        }

        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(task, vm_address_t(UInt(bitPattern: threadList)), size)
        }

        var totalCPU = 0.0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(
                        threadList[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        $0,
                        &count
                    )
                }
            }

            guard result == KERN_SUCCESS,
                  (info.flags & TH_FLAGS_IDLE) == 0 else {
                continue
            }

            totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }

        return totalCPU
    }

    private func currentResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return UInt64(info.resident_size)
    }
}
