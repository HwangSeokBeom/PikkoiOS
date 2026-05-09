import Foundation

struct MultipartFormDataBuilder {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(
        fieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) {
#if DEBUG
        Logger(category: "Multipart").debug("[Multipart] part name=\(fieldName) fileName=\(fileName) mime=\(mimeType) bytes=\(fileData.count)")
#endif
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    func build() -> RequestBody {
        var finalData = data
        finalData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return .multipart(finalData, boundary: boundary)
    }

    private mutating func append(_ string: String) {
        data.append(string.data(using: .utf8)!)
    }
}
