import Testing

@testable import GDockerCore

@Test func pathSegmentEncodesSeparatorsAndSpaces() {
    #expect(DockerClient.pathSegment("a/b?c#d e") == "a%2Fb%3Fc%23d%20e")
}

@Test func pathSegmentLeavesOrdinaryNamesAlone() {
    #expect(DockerClient.pathSegment("my-app_1.x") == "my-app_1.x")
}
