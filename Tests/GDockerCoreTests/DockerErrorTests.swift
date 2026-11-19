import Foundation
import Testing

@testable import GDockerCore

private func body(_ s: String) -> Data { Data(s.utf8) }

@Test func successStatusesAreNotErrors() {
    #expect(DockerError.from(status: 204, body: Data()) == nil)
    #expect(DockerError.from(status: 200, body: body("{}")) == nil)
    #expect(DockerError.from(status: 304, body: Data()) == nil)
}

@Test func notFoundUsesDockerMessage() {
    let e = DockerError.from(status: 404, body: body(#"{"message":"No such container: x"}"#))
    #expect(e == .notFound("No such container: x"))
}

@Test func conflictUsesDockerMessage() {
    let e = DockerError.from(status: 409, body: body(#"{"message":"container is running"}"#))
    #expect(e == .conflict("container is running"))
}

@Test func otherStatusFallsBackToRawBody() {
    #expect(DockerError.from(status: 500, body: body("boom")) == .server(status: 500, message: "boom"))
}
