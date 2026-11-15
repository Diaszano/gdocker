import Foundation

public struct StatsSample: Sendable, Equatable {
    public let cpuPercent: Double
    public let memoryUsed: UInt64
    public let memoryLimit: UInt64
    public let netRx: UInt64
    public let netTx: UInt64

    /// `nil` while Docker has no previous CPU reading (the first sample of a stream).
    public static func from(json: Data) throws -> StatsSample? {
        let raw = try JSONDecoder().decode(Raw.self, from: json)
        guard let system = raw.cpu_stats.system_cpu_usage,
              let previousSystem = raw.precpu_stats.system_cpu_usage,
              system > previousSystem
        else { return nil }
        let cpuDelta = max(0, Double(raw.cpu_stats.total) - Double(raw.precpu_stats.total))
        let systemDelta = Double(system - previousSystem)
        let cpus = Double(raw.cpu_stats.online_cpus ?? 1)
        let memory = raw.memory_stats
        let used = memory.usage ?? 0
        let inactive = memory.stats?.inactive_file ?? memory.stats?.cache ?? 0
        let networks = raw.networks?.values
        return StatsSample(
            cpuPercent: cpuDelta / systemDelta * cpus * 100,
            memoryUsed: used > inactive ? used - inactive : 0,
            memoryLimit: memory.limit ?? 0,
            netRx: networks?.reduce(0) { $0 + $1.rx_bytes } ?? 0,
            netTx: networks?.reduce(0) { $0 + $1.tx_bytes } ?? 0
        )
    }

    private struct Raw: Decodable {
        struct CPU: Decodable {
            struct Usage: Decodable { let total_usage: UInt64 }
            let cpu_usage: Usage?
            let system_cpu_usage: UInt64?
            let online_cpus: Int?
            var total: UInt64 { cpu_usage?.total_usage ?? 0 }
        }
        struct Memory: Decodable {
            struct Detail: Decodable {
                let inactive_file: UInt64?
                let cache: UInt64?
            }
            let usage: UInt64?
            let limit: UInt64?
            let stats: Detail?
        }
        struct Network: Decodable { let rx_bytes: UInt64; let tx_bytes: UInt64 }

        let cpu_stats: CPU
        let precpu_stats: CPU
        let memory_stats: Memory
        let networks: [String: Network]?
    }
}
