import Foundation

extension URLSessionTask: Cancellable {}

/// A transport-level, HTTP-specific error.
public struct GraphQLHTTPResponseError: Error, LocalizedError {
  public enum ErrorKind {
    case errorResponse
    case invalidResponse
    
    var description: String {
      switch self {
      case .errorResponse:
        return "Received error response"
      case .invalidResponse:
        return "Received invalid response"
      }
    }
  }
  
  /// The body of the response.
  public let body: Data?
  /// Information about the response as provided by the server.
  public let response: HTTPURLResponse
  public let kind: ErrorKind
  
  public var bodyDescription: String {
    if let body = body {
      if let description = String(data: body, encoding: response.textEncoding ?? .utf8) {
        return description
      } else {
        return "Unreadable response body"
      }
    } else {
      return "Empty response body"
    }
  }
  
  public var errorDescription: String? {
    return "\(kind.description) (\(response.statusCode) \(response.statusCodeDescription)): \(bodyDescription)"
  }
}

/// A network transport that uses HTTP post requests to send GraphQL operations to a server, and that uses `URLSession` as the networking implementation.
public class HTTPNetworkTransport: NetworkTransport {
  let url: URL
  let session: URLSession
  let serializationFormat = JSONSerializationFormat.self
  public var headers: [String:String] = [:]
  
  /// Creates a network transport with the specified server URL and session configuration.
  ///
  /// - Parameters:
  ///   - url: The URL of a GraphQL server to connect to.
  ///   - configuration: A URLSessionConfiguration used to configure the session. Defaults to `URLSessionConfiguration.default`.
  public init(url: URL, configuration: URLSessionConfiguration = URLSessionConfiguration.default) {
    self.url = url
    self.session = URLSession(configuration: configuration)
  }
  
  public func send<Operation: GraphQLOperation>(operation: Operation, completionHandler: @escaping (GraphQLResponse<Operation>?, Error?) -> Void) -> Cancellable {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = headers
    
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let stringVar = try! serializationFormat.serialize(value: operation.variables)
    var dataString = String(data: stringVar, encoding: String.Encoding.utf8)
    let body: GraphQLMap = ["query": type(of: operation).queryDocument, "variables": dataString]
    request.httpBody = try! serializationFormat.serialize(value: body)
    
    let task = session.dataTask(with: request) { (data: Data?, response: URLResponse?, error: Error?) in
      if error != nil {
        completionHandler(nil, error)
        return
      }
      
      guard let httpResponse = response as? HTTPURLResponse else {
        fatalError("Response should be an HTTPURLResponse")
      }
      
      if (!httpResponse.isSuccessful) {
        completionHandler(nil, GraphQLHTTPResponseError(body: data, response: httpResponse, kind: .errorResponse))
        return
      }
      
      guard let data = data else {
        completionHandler(nil, GraphQLHTTPResponseError(body: nil, response: httpResponse, kind: .invalidResponse))
        return
      }
      
      do {
        guard let body =  try self.serializationFormat.deserialize(data: data) as? JSONObject else {
          throw GraphQLHTTPResponseError(body: data, response: httpResponse, kind: .invalidResponse)
        }
        let response = GraphQLResponse(operation: operation, body: body)
        completionHandler(response, nil)
      } catch {
        completionHandler(nil, error)
      }
    }
    
    task.resume()
    
    return task
  }
}
