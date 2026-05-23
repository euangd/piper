// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PDFKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TextImportService: Sendable {
    enum ImportError: Swift.Error {
        case invalidURL
        case unsupportedFileType
        case emptyContent
    }

    func importWebsite(from input: String) async throws -> String {
        guard let url = normalizedURL(from: input) else {
            throw ImportError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.emptyContent
        }

        return try readableText(fromHTML: html)
    }

    func importFile(from url: URL) throws -> String {
        let text: String

        if url.conforms(to: .pdf) {
            text = try pdfText(from: url)
        } else if url.conforms(to: .rtf) {
            text = try attributedText(from: url, documentType: .rtf)
        } else if url.conforms(to: .text) || url.pathExtension.lowercased() == "md" {
            text = try String(contentsOf: url, encoding: .utf8)
        } else {
            throw ImportError.unsupportedFileType
        }

        return try cleanedText(text)
    }

    private func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }

    private func readableText(fromHTML html: String) throws -> String {
        var working = html
        working = working.replacingMatches(of: "(?is)<(script|style|noscript|svg|canvas|iframe)[^>]*>.*?</\\1>", with: " ")
        working = working.replacingMatches(of: "(?is)<(nav|header|footer|aside|form)[^>]*>.*?</\\1>", with: " ")
        working = working.replacingMatches(of: "(?is)<!--.*?-->", with: " ")
        working = working.replacingMatches(of: "(?i)<br\\s*/?>", with: "\n")
        working = working.replacingMatches(of: "(?i)</(p|div|section|article|h[1-6]|li)>", with: "\n")
        working = working.replacingMatches(of: "(?is)<[^>]+>", with: " ")
        working = working.decodingHTMLEntities()
        return try cleanedText(working)
    }

    private func pdfText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.unsupportedFileType
        }

        var pages: [String] = []
        for pageIndex in 0..<document.pageCount {
            if let text = document.page(at: pageIndex)?.string {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n\n")
    }

    private func attributedText(from url: URL, documentType: NSAttributedString.DocumentType) throws -> String {
        let data = try Data(contentsOf: url)
        let attributed = try NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
        return attributed.string
    }

    private func cleanedText(_ text: String) throws -> String {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingMatches(of: "[\\t ]+", with: " ")
            .replacingMatches(of: "\\n{3,}", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw ImportError.emptyContent
        }
        return cleaned
    }
}

private extension URL {
    func conforms(to type: UTType) -> Bool {
        guard let contentType = UTType(filenameExtension: pathExtension) else {
            return false
        }
        return contentType.conforms(to: type)
    }
}

private extension String {
    func replacingMatches(of pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }

    func decodingHTMLEntities() -> String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            return self
        }
        return attributed.string
    }
}
