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

    private static func parseImage(_ image: String) -> (normalized: String, repoName: String) {
        let withoutDigest = image.split(separator: "@", maxSplits: 1).first.map(String.init) ?? image
        let withoutTag = withoutDigest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? withoutDigest
        let normalized = withoutTag.lowercased()
        let repoName = (withoutTag.split(separator: "/").last.map(String.init) ?? withoutTag).lowercased()
        return (normalized, repoName)
    }

    /// Maps an image reference (e.g. `ghcr.io/bitnami/redis:7-alpine`) to a known `ServiceKind`.
    public static func from(image: String) -> ServiceKind {
        let (_, repoName) = parseImage(image)
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

    /// Maps an image reference to a bundled Penpot brand logo slug under `Resources/ServiceLogos`, if available.
    public static func logoSlug(for image: String) -> String? {
        let (normalized, repoName) = parseImage(image)
        guard !repoName.isEmpty else { return nil }

        // Check specific multi-word / compound names before generic substrings.
        let rules: [(match: String, slug: String)] = [
            ("node-red", "node-red"),
            ("nodered", "node-red"),
            ("home-assistant", "home-assistant"),
            ("homeassistant", "home-assistant"),
            ("opensearch", "opensearch"),
            ("elasticsearch", "elasticsearch"),
            ("cockroach", "cockroach-labs"),
            ("couchdb", "apache-couchdb"),
            ("superset", "apache-superset"),
            ("mosquitto", "eclipse-mosquitto"),
            ("new-relic", "new-relic"),
            ("newrelic", "new-relic"),
            ("traefik", "traefik-proxy"),
            ("envoy", "envoy-proxy"),
            ("postgres", "postgresql"),
            ("pgvector", "postgresql"),
            ("postgis", "postgresql"),
            ("timescaledb", "postgresql"),
            ("rabbitmq", "rabbitmq"),
            ("redis", "redis"),
            ("valkey", "redis"),
            ("nginx", "nginx"),
            ("mongodb", "mongodb"),
            ("mongo", "mongodb"),
            ("mariadb", "mariadb"),
            ("mysql", "mysql"),
            ("minio", "minio"),
            ("grafana", "grafana"),
            ("prometheus", "prometheus"),
            ("clickhouse", "clickhouse"),
            ("cloudflare", "cloudflare"),
            ("cloudflared", "cloudflare"),
            ("appwrite", "appwrite"),
            ("authentik", "authentik"),
            ("bitwarden", "bitwarden"),
            ("vaultwarden", "bitwarden"),
            ("bookstack", "bookstack"),
            ("directus", "directus"),
            ("django", "django"),
            ("docker", "docker"),
            ("dind", "docker"),
            ("dotnet", "dotnet"),
            ("aspnet", "dotnet"),
            ("drupal", "drupal"),
            ("element", "element"),
            ("fluentd", "fluentd"),
            ("fluent-bit", "fluentd"),
            ("ghost", "ghost"),
            ("github", "github"),
            ("gitlab", "gitlab"),
            ("golang", "go"),
            ("graylog", "graylog"),
            ("helm", "helm"),
            ("javascript", "javascript"),
            ("jellyfin", "jellyfin"),
            ("joomla", "joomla"),
            ("jupyter", "jupyter"),
            ("keycloak", "keycloak"),
            ("kibana", "kibana"),
            ("kong", "kong"),
            ("kubernetes", "kubernetes"),
            ("kubectl", "kubernetes"),
            ("laravel", "laravel"),
            ("logstash", "logstash"),
            ("matrix", "matrix"),
            ("synapse", "matrix"),
            ("mattermost", "mattermost"),
            ("neo4j", "neo4j"),
            ("nextcloud", "nextcloud"),
            ("nextjs", "nextjs"),
            ("next-js", "nextjs"),
            ("nodejs", "nodejs"),
            ("obsidian", "obsidian"),
            ("odoo", "odoo"),
            ("php", "php"),
            ("plex", "plex"),
            ("portainer", "portainer"),
            ("pytorch", "pytorch"),
            ("radarr", "radarr"),
            ("redash", "redash"),
            ("ruby", "ruby"),
            ("sentry", "sentry"),
            ("sonarqube", "sonarqube"),
            ("spring", "spring"),
            ("sqlite", "sqlite"),
            ("strapi", "strapi"),
            ("supabase", "supabase"),
            ("syncthing", "syncthing"),
            ("tailscale", "tailscale"),
            ("tensorflow", "tensorflow"),
            ("terraform", "terraform"),
            ("typescript", "typescript"),
            ("vault", "vault"),
            ("vuejs", "vuejs"),
            ("wordpress", "wordpress"),
            ("angular", "angular"),
            ("ansible", "ansible"),
            ("deno", "deno"),
        ]

        for rule in rules {
            if repoName.contains(rule.match) || normalized.contains("/\(rule.match)/") {
                return rule.slug
            }
        }
        if repoName == "node" || repoName.hasPrefix("node-") {
            return "nodejs"
        }
        if repoName == "go" {
            return "go"
        }
        if repoName == "k8s" || normalized.contains("registry.k8s.io/") {
            return "kubernetes"
        }
        if repoName == "vue" {
            return "vuejs"
        }
        return nil
    }
}
