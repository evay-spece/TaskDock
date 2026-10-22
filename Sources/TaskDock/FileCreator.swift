import AppKit
import Darwin

enum NewFileKind: String, CaseIterable {
    case xlsx, docx, txt, csv, md, rtf

    var title: String {
        switch self {
        case .xlsx: return "Excel 工作簿"
        case .docx: return "Word 文档"
        case .txt: return "文本文档 TXT"
        case .csv: return "CSV 表格"
        case .md: return "Markdown 文档"
        case .rtf: return "富文本文档 RTF"
        }
    }

    var baseName: String {
        switch self {
        case .xlsx: return "新建 Excel 工作簿"
        case .docx: return "新建 Word 文档"
        case .txt: return "新建文本文档"
        case .csv: return "新建 CSV 表格"
        case .md: return "新建 Markdown 文档"
        case .rtf: return "新建富文本文档"
        }
    }

    func contents() throws -> Data {
        switch self {
        case .xlsx, .docx:
            guard let url = Bundle.main.url(forResource: "blank", withExtension: rawValue) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try Data(contentsOf: url)
        case .txt, .csv, .md:
            return Data()
        case .rtf:
            return Data("{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Songti SC;}}\\f0\\fs24\n}\n".utf8)
        }
    }
}

enum FileCreator {
    static func create(_ entry: FileTypeEntry, in directory: URL) throws -> URL {
        let contents = try NewFileKind(rawValue: entry.id)?.contents() ?? Data()
        return try create(baseName: entry.baseName, fileExtension: entry.fileExtension,
                          contents: contents, in: directory)
    }

    static func create(_ kind: NewFileKind, in directory: URL) throws -> URL {
        try create(baseName: kind.baseName, fileExtension: kind.rawValue,
                   contents: kind.contents(), in: directory)
    }

    private static func create(baseName: String, fileExtension: String, contents: Data,
                               in directory: URL) throws -> URL {
        let folder = directory.standardizedFileURL
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw POSIXError(.ENOTDIR) }

        for number in 0..<1000 {
            let suffix = number == 0 ? "" : " \(number + 1)"
            let output = folder.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            let fd = open(output.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            if fd < 0 {
                if errno == EEXIST { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer { close(fd) }
            try contents.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var offset = 0
                while offset < rawBuffer.count {
                    let written = write(fd, base.advanced(by: offset), rawBuffer.count - offset)
                    if written < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    offset += written
                }
            }
            return output
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
