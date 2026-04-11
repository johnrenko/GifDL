import Foundation

struct FetchResolutionResponse: Codable, Equatable {
    var status: String
    var mediaURL: String?
    var filename: String?
    var mimeType: String?
    var jobID: String?
    var errorMessage: String?
}

protocol FetchServicing {
    func submit(url: URL) async throws -> FetchResolutionResponse
    func poll(jobID: String) async throws -> FetchResolutionResponse
}

struct FetchService: FetchServicing {
    let baseURL: URL
    let session: URLSession

    func submit(url: URL) async throws -> FetchResolutionResponse {
        let requestURL = baseURL.appending(path: "resolve")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": url.absoluteString])
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(FetchResolutionResponse.self, from: data)
    }

    func poll(jobID: String) async throws -> FetchResolutionResponse {
        let requestURL = baseURL.appending(path: "jobs").appending(path: jobID)
        let (data, response) = try await session.data(from: requestURL)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(FetchResolutionResponse.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw FetchServiceError.invalidResponse(message)
        }
    }
}

enum FetchServiceError: LocalizedError {
    case invalidResponse(String)
    case missingMediaURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return message
        case .missingMediaURL:
            return "The fetch service did not return a downloadable media URL."
        }
    }
}
