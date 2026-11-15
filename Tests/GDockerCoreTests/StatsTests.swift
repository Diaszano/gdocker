import Foundation
import Testing
@testable import GDockerCore

private let full = Data("""
{
  "cpu_stats": { "cpu_usage": { "total_usage": 400 }, "system_cpu_usage": 2000, "online_cpus": 4 },
  "precpu_stats": { "cpu_usage": { "total_usage": 200 }, "system_cpu_usage": 1000, "online_cpus": 4 },
  "memory_stats": { "usage": 600, "limit": 1000, "stats": { "inactive_file": 100 } },
  "networks": { "eth0": { "rx_bytes": 10, "tx_bytes": 20 }, "eth1": { "rx_bytes": 5, "tx_bytes": 5 } }
}
""".utf8)

@Test func cpuAndMemory() throws {
    let sample = try #require(try StatsSample.from(json: full))
    #expect(sample.cpuPercent == 80)
    #expect(sample.memoryUsed == 500)
    #expect(sample.memoryLimit == 1000)
    #expect(sample.netRx == 15)
    #expect(sample.netTx == 25)
}

@Test func firstSampleHasNoPreviousCpuReading() throws {
    let first = Data("""
    {
      "cpu_stats": { "cpu_usage": { "total_usage": 400 }, "system_cpu_usage": 2000, "online_cpus": 4 },
      "precpu_stats": { "cpu_usage": { "total_usage": 0 } },
      "memory_stats": { "usage": 600, "limit": 1000 }
    }
    """.utf8)
    #expect(try StatsSample.from(json: first) == nil)
}

@Test func missingNetworksAndInactiveFileCountAsZero() throws {
    let json = Data("""
    {
      "cpu_stats": { "cpu_usage": { "total_usage": 300 }, "system_cpu_usage": 2000, "online_cpus": 1 },
      "precpu_stats": { "cpu_usage": { "total_usage": 200 }, "system_cpu_usage": 1000 },
      "memory_stats": { "usage": 600, "limit": 1000 }
    }
    """.utf8)
    let sample = try #require(try StatsSample.from(json: json))
    #expect(sample.memoryUsed == 600)
    #expect(sample.netRx == 0 && sample.netTx == 0)
}

@Test func counterResetClampsCpuPercentToZero() throws {
    let json = Data("""
    {
      "cpu_stats": { "cpu_usage": { "total_usage": 100 }, "system_cpu_usage": 2000, "online_cpus": 2 },
      "precpu_stats": { "cpu_usage": { "total_usage": 500 }, "system_cpu_usage": 1000 },
      "memory_stats": { "usage": 600, "limit": 1000, "stats": { "cache": 200 } }
    }
    """.utf8)
    let sample = try #require(try StatsSample.from(json: json))
    #expect(sample.cpuPercent == 0)
    #expect(sample.memoryUsed == 400)
}
