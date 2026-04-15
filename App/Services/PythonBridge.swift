import Foundation

/// Bridge to run background removal + lasso refinement via Python subprocess.
/// Primary: RMBG-1.4 → Fallback: SAM → Lasso refinement: SAM with point prompts.
/// All models loaded from local cache — no network calls.
final class PythonBridge: Sendable {

    private var pythonPath: String {
        let venvPython = projectRoot
            .appendingPathComponent("venv/bin/python3")
            .path
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            return venvPython
        }
        return "/usr/bin/env"
    }

    private var pythonArgs: [String] {
        let venvPython = projectRoot
            .appendingPathComponent("venv/bin/python3")
            .path
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            return []
        }
        return ["python3"]
    }

    private var projectRoot: URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Scripts").path) {
            return cwd
        }

        // Distributed layout: Scripts/ and venv/ live next to the .app bundle.
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: sibling.appendingPathComponent("Scripts").path) {
            return sibling
        }

        // SwiftPM dev fallback (run via `swift run`).
        return Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - Background Removal (Pipeline)

    func runBackgroundRemoval(input: URL, output: URL) async throws {
        try await runPythonModule(
            module: "pipeline.main",
            arguments: [input.path, output.path]
        )
    }

    // MARK: - Image Conversion (Pillow)

    func runImageConversion(input: URL, output: URL, format: String, quality: Int, targetKB: Int) async throws {
        try await runPythonModule(
            module: "pipeline.convert",
            arguments: [input.path, output.path, format, String(quality), String(targetKB)]
        )
    }

    // MARK: - Lasso Refinement (SAM)

    func runLassoRefinement(input: URL, output: URL, lassoPoints: [[Double]]) async throws {
        // Write lasso points to temp JSON file
        let pointsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mw_lasso_\(UUID().uuidString).json")
        let jsonData = try JSONSerialization.data(withJSONObject: lassoPoints)
        try jsonData.write(to: pointsURL)
        defer { try? FileManager.default.removeItem(at: pointsURL) }

        try await runPythonModule(
            module: "pipeline.main",
            arguments: ["--lasso", pointsURL.path, input.path, output.path]
        )
    }

    // MARK: - Execution

    private func runPythonModule(module: String, arguments: [String]) async throws {
        let result = try await executeProcess(
            path: pythonPath,
            arguments: pythonArgs + ["-m", module] + arguments
        )

        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProcessingError.processingFailed(
                err.count > 200 ? String(err.suffix(200)) : err
            )
        }
    }

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func executeProcess(path: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            process.currentDirectoryURL = projectRoot

            var env = ProcessInfo.processInfo.environment
            let venvBin = projectRoot.appendingPathComponent("venv/bin").path
            env["PATH"] = "\(venvBin):\(env["PATH"] ?? "/usr/bin")"
            env["VIRTUAL_ENV"] = projectRoot.appendingPathComponent("venv").path
            env["HF_HUB_OFFLINE"] = "1"
            env["TRANSFORMERS_OFFLINE"] = "1"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ProcessResult(
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? "",
                    exitCode: proc.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessingError.processingFailed("Python not found. Run setup_ml_models.sh"))
            }
        }
    }
}
