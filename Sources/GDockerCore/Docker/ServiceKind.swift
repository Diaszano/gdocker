import Foundation

/// Known Docker container services for rendering recognizable icons in the container list.
public enum ServiceKind: String, CaseIterable, Sendable {
    case postgres
    case redis
    case nginx
    case rabbitmq
    case mongodb
    case mysql
    case elasticsearch
    case kafka
    case traefik
    case grafana
    case prometheus
    case minio
    case generic

    /// Maps an image reference (e.g. `ghcr.io/bitnami/redis:7-alpine`) to a known `ServiceKind`.
    public static func from(image: String) -> ServiceKind {
        let withoutDigest = image.split(separator: "@", maxSplits: 1).first.map(String.init) ?? image
        let withoutTag = withoutDigest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? withoutDigest
        let repoName = (withoutTag.split(separator: "/").last.map(String.init) ?? withoutTag).lowercased()

        if repoName.isEmpty { return .generic }
        if repoName.contains("postgres") || repoName == "pgvector" { return .postgres }
        if repoName.contains("redis") || repoName == "valkey" { return .redis }
        if repoName.contains("nginx") { return .nginx }
        if repoName.contains("rabbitmq") { return .rabbitmq }
        if repoName.contains("mongo") { return .mongodb }
        if repoName.contains("mysql") || repoName.contains("mariadb") { return .mysql }
        if repoName.contains("elasticsearch") || repoName.contains("opensearch") { return .elasticsearch }
        if repoName.contains("kafka") || repoName.contains("redpanda") { return .kafka }
        if repoName.contains("traefik") { return .traefik }
        if repoName.contains("grafana") { return .grafana }
        if repoName.contains("prometheus") { return .prometheus }
        if repoName.contains("minio") { return .minio }
        return .generic
    }
}
