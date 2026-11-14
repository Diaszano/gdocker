import Testing
@testable import GDockerCore

@Test func mapsCommonDockerImagesToServiceKind() {
    #expect(ServiceKind.from(image: "postgres:16") == .postgres)
    #expect(ServiceKind.from(image: "ghcr.io/bitnami/redis:7-alpine") == .redis)
    #expect(ServiceKind.from(image: "nginx:1.27") == .nginx)
    #expect(ServiceKind.from(image: "rabbitmq:3-management") == .rabbitmq)
    #expect(ServiceKind.from(image: "mongo:7") == .mongodb)
    #expect(ServiceKind.from(image: "docker.elastic.co/elasticsearch/elasticsearch:8.12.0") == .elasticsearch)
    #expect(ServiceKind.from(image: "mysql:8.4") == .mysql)
    #expect(ServiceKind.from(image: "mailhog/mailhog") == .generic)
    #expect(ServiceKind.from(image: "") == .generic)
}

@Test func mapsDockerImagesToPenpotLogoSlugs() {
    #expect(ServiceKind.logoSlug(for: "cndt-scraper-postgres") == "postgresql")
    #expect(ServiceKind.logoSlug(for: "cndt-scraper-rabbitmq") == "rabbitmq")
    #expect(ServiceKind.logoSlug(for: "ghcr.io/bitnami/redis:7-alpine") == "redis")
    #expect(ServiceKind.logoSlug(for: "opensearchproject/opensearch:2") == "opensearch")
    #expect(ServiceKind.logoSlug(for: "nodered/node-red:latest") == "node-red")
    #expect(ServiceKind.logoSlug(for: "node:20-alpine") == "nodejs")
    #expect(ServiceKind.logoSlug(for: "traefik:v3.0") == "traefik-proxy")
    #expect(ServiceKind.logoSlug(for: "mailhog/mailhog") == nil)
    #expect(ServiceKind.logoSlug(for: "") == nil)
}
