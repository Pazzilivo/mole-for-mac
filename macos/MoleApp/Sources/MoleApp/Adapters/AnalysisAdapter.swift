import Foundation

enum AnalysisAdapter {
    static func convert(_ scanResult: ScanResult, path: String) -> AnalyzeOutput {
        AnalyzeOutput(
            path: path,
            overview: false,
            entries: scanResult.entries.map { entry in
                AnalyzeEntry(
                    name: entry.name,
                    path: entry.path,
                    size: entry.size,
                    isDir: entry.isDir
                )
            },
            largeFiles: scanResult.largeFiles.map { file in
                AnalyzeFile(name: file.name, path: file.path, size: file.size)
            },
            totalSize: scanResult.totalSize,
            totalFiles: scanResult.totalFiles
        )
    }
}
