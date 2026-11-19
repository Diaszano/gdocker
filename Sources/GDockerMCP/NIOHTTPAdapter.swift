// Adapted from modelcontextprotocol/swift-sdk, Sources/MCPConformance/Server/HTTPApp.swift (Apache-2.0 / MIT).
// A thin SwiftNIO layer that turns NIO HTTP parts into the SDK's framework-agnostic HTTPRequest/HTTPResponse and
// back; all MCP logic lives in McpHTTPServer.

import Foundation
import MCP
import NIOCore
import NIOHTTP1

final class McpNIOHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    static let maxBodyBytes = 1_048_576

    private struct RequestState {
        var head: HTTPRequestHead
        var body: ByteBuffer
    }

    private let path: String
    private let handle: @Sendable (HTTPRequest) async -> HTTPResponse
    private var state: RequestState?

    init(path: String, handle: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.path = path
        self.handle = handle
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            state = RequestState(head: head, body: context.channel.allocator.buffer(capacity: 0))
        case .body(var buffer):
            guard var current = state else { return }
            if current.body.readableBytes + buffer.readableBytes > Self.maxBodyBytes {
                state = nil
                var head = current.head
                head.headers.replaceOrAdd(name: "Connection", value: "close")
                nonisolated(unsafe) let unsafeContext = context
                let response = HTTPResponse.error(statusCode: 413, .invalidRequest("Payload Too Large"))
                Task { await self.write(response, head: head, context: unsafeContext) }
                return
            }
            current.body.writeBuffer(&buffer)
            state = current
        case .end:
            guard let request = state else { return }
            state = nil
            nonisolated(unsafe) let unsafeContext = context
            Task { await self.respond(to: request, context: unsafeContext) }
        }
    }

    private func respond(to request: RequestState, context: ChannelHandlerContext) async {
        let head = request.head
        let requestPath = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
        guard requestPath == path else {
            await write(
                .error(statusCode: 404, .invalidRequest("Not Found")), head: head, context: context)
            return
        }
        await write(await handle(makeRequest(request, path: requestPath)), head: head, context: context)
    }

    private func makeRequest(_ state: RequestState, path: String) -> HTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            headers[name] = headers[name].map { $0 + ", " + value } ?? value
        }
        var body: Data?
        if state.body.readableBytes > 0, let bytes = state.body.getBytes(at: 0, length: state.body.readableBytes) {
            body = Data(bytes)
        }
        return HTTPRequest(method: state.head.method.rawValue, headers: headers, body: body, path: path)
    }

    private func write(_ response: HTTPResponse, head requestHead: HTTPRequestHead, context: ChannelHandlerContext)
        async
    {
        nonisolated(unsafe) let unsafeContext = context
        let loop = context.eventLoop
        let version = requestHead.version
        // A client that sent `Connection: close` (or speaks HTTP/1.0) expects the server to hang up after the reply.
        let keepAlive = requestHead.isKeepAlive
        let status = HTTPResponseStatus(statusCode: response.statusCode)
        let headers = response.headers

        @Sendable func finish() {
            let done = unsafeContext.eventLoop.makePromise(of: Void.self)
            unsafeContext.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: done)
            if !keepAlive { done.futureResult.whenComplete { _ in unsafeContext.close(promise: nil) } }
        }

        @Sendable func head() -> HTTPResponseHead {
            var head = HTTPResponseHead(version: version, status: status)
            for (name, value) in headers { head.headers.add(name: name, value: value) }
            return head
        }

        if case .stream(let stream, _) = response {
            loop.execute {
                unsafeContext.write(self.wrapOutboundOut(.head(head())), promise: nil)
                unsafeContext.flush()
            }
            do {
                for try await chunk in stream {
                    loop.execute {
                        var buffer = unsafeContext.channel.allocator.buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        unsafeContext.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    }
                }
            } catch {
                // The stream ended with an error: finish the response and let the client reconnect.
            }
            loop.execute { finish() }
        } else {
            let body = response.bodyData
            loop.execute {
                unsafeContext.write(self.wrapOutboundOut(.head(head())), promise: nil)
                if let body {
                    var buffer = unsafeContext.channel.allocator.buffer(capacity: body.count)
                    buffer.writeBytes(body)
                    unsafeContext.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }
                finish()
            }
        }
    }
}
