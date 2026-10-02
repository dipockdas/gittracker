import Foundation
import Network

enum ReceiverError: Error, CustomStringConvertible {
    case invalidPort(UInt16)

    var description: String {
        switch self {
        case .invalidPort(let port): return "invalid port \(port)"
        }
    }
}

struct HTTPRequest {
    var method: String = ""
    var path: String = ""
    var headers: [String: String] = [:]
    var body: Data = Data()
}

struct HTTPResponse {
    var status: Int = 200
    var reason: String = "OK"
    var body: Data = Data()

    static func json(_ payload: [String: Any], status: Int = 200, reason: String = "OK") -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        return HTTPResponse(status: status, reason: reason, body: data)
    }

    static let notFound = HTTPResponse.json(["error": "not found"], status: 404, reason: "Not Found")
}

final class HTTPServer {
    private let port: UInt16
    private let handler: (HTTPRequest) -> HTTPResponse
    let queue = DispatchQueue(label: "gittracker.receiver.http", qos: .utility)
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]

    init(port: UInt16, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ReceiverError.invalidPort(port)
        }
        let listener = try NWListener(using: parameters, on: endpointPort)
        listener.newConnectionHandler = { [weak self] (connection: NWConnection) in
            guard let self else {
                connection.cancel()
                return
            }
            let session = Session(connection: connection, server: self)
            self.sessions[ObjectIdentifier(session)] = session
            session.start()
        }
        listener.stateUpdateHandler = { (state: NWListener.State) in
            if case .failed(let error) = state {
                ReceiverConfig.log("listener failed: \(error)")
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    fileprivate func release(_ session: Session) {
        sessions.removeValue(forKey: ObjectIdentifier(session))
    }

    fileprivate func respond(to request: HTTPRequest) -> HTTPResponse {
        handler(request)
    }

    fileprivate func finish(_ connection: NWConnection, with response: HTTPResponse) {
        let head = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(response.body.count)\r\n"
            + "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(response.body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class Session {
    private static let maxBodyBytes = 1_048_576

    private let connection: NWConnection
    private let server: HTTPServer
    private var buffer = Data()
    private var request = HTTPRequest()
    private var expectedBody = 0
    private var headersParsed = false

    init(connection: NWConnection, server: HTTPServer) {
        self.connection = connection
        self.server = server
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            switch state {
            case .failed, .cancelled:
                self?.terminate()
            default:
                break
            }
        }
        connection.start(queue: server.queue)
        read()
    }

    private func terminate() {
        connection.cancel()
        server.release(self)
    }

    private func read() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }
            if error != nil {
                self.terminate()
                return
            }
            if self.consume() {
                return
            }
            if isComplete {
                self.terminate()
                return
            }
            self.read()
        }
    }

    /// Returns true when a response has been sent and no more reading is needed.
    private func consume() -> Bool {
        if !headersParsed {
            guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 16_384 {
                    server.finish(connection, with: .json(
                        ["error": "header too large"], status: 431, reason: "Request Header Fields Too Large"
                    ))
                    server.release(self)
                    return true
                }
                return false
            }
            let head = buffer.subdata(in: buffer.startIndex..<separator.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<separator.upperBound)
            guard parse(head: head) else {
                server.finish(connection, with: .json(["error": "malformed request"], status: 400, reason: "Bad Request"))
                server.release(self)
                return true
            }
            headersParsed = true
        }

        guard buffer.count >= expectedBody else { return false }

        request.body = buffer.prefix(expectedBody)
        let response = server.respond(to: request)
        server.finish(connection, with: response)
        server.release(self)
        return true
    }

    private func parse(head: Data) -> Bool {
        guard let text = String(data: head, encoding: .utf8) else { return false }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return false }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return false }
        request.method = String(parts[0])
        request.path = String(parts[1])

        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            request.headers[name] = value
        }

        if let raw = request.headers["content-length"], let length = Int(raw) {
            guard length >= 0, length <= Self.maxBodyBytes else { return false }
            expectedBody = length
        } else {
            expectedBody = 0
        }
        return true
    }
}
