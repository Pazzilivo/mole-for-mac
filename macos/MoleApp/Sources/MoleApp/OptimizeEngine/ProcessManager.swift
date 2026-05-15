import Foundation
import os.log

/// Process execution manager with support for sudo operations
actor ProcessManager {
    private let logger = Logger(subsystem: "com.mole.process", category: "ProcessManager")

    /// Execute a command without sudo
    func execute(command: String, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        logger.debug("Executing command: \(command) with arguments: \(arguments)")

        do {
            try process.run()
            // C9 FIX: Use Task.detached to avoid blocking actor isolation
            await Task.detached {
                process.waitUntilExit()
            }.value

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("Command failed with exit code \(process.terminationStatus): \(errorMessage)")
                throw ProcessError.commandFailed(exitCode: process.terminationStatus, message: errorMessage)
            }

            logger.debug("Command executed successfully")
        } catch {
            logger.error("Failed to execute command: \(error.localizedDescription)")
            throw ProcessError.executionFailed(message: error.localizedDescription)
        }
    }

    /// Execute a command with sudo privileges
    func executeWithSudo(command: String, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", command] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        logger.debug("Executing sudo command: \(command) with arguments: \(arguments)")

        do {
            try process.run()
            // C9 FIX: Use Task.detached to avoid blocking actor isolation
            await Task.detached {
                process.waitUntilExit()
            }.value

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("Sudo command failed with exit code \(process.terminationStatus): \(errorMessage)")
                throw ProcessError.sudoFailed(exitCode: process.terminationStatus, message: errorMessage)
            }

            logger.debug("Sudo command executed successfully")
        } catch {
            logger.error("Failed to execute sudo command: \(error.localizedDescription)")
            throw ProcessError.executionFailed(message: error.localizedDescription)
        }
    }

    /// Execute a command and return its output
    func executeWithOutput(command: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        logger.debug("Executing command with output: \(command) with arguments: \(arguments)")

        do {
            try process.run()
            // C9 FIX: Use Task.detached to avoid blocking actor isolation
            await Task.detached {
                process.waitUntilExit()
            }.value

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("Command failed with exit code \(process.terminationStatus): \(errorMessage)")
                throw ProcessError.commandFailed(exitCode: process.terminationStatus, message: errorMessage)
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            logger.debug("Command executed successfully, output length: \(output.count)")
            return output
        } catch {
            logger.error("Failed to execute command: \(error.localizedDescription)")
            throw ProcessError.executionFailed(message: error.localizedDescription)
        }
    }

    /// Execute a command with sudo and return its output
    func executeWithSudoOutput(command: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", command] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        logger.debug("Executing sudo command with output: \(command) with arguments: \(arguments)")

        do {
            try process.run()
            // C9 FIX: Use Task.detached to avoid blocking actor isolation
            await Task.detached {
                process.waitUntilExit()
            }.value

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("Sudo command failed with exit code \(process.terminationStatus): \(errorMessage)")
                throw ProcessError.sudoFailed(exitCode: process.terminationStatus, message: errorMessage)
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            logger.debug("Sudo command executed successfully, output length: \(output.count)")
            return output
        } catch {
            logger.error("Failed to execute sudo command: \(error.localizedDescription)")
            throw ProcessError.executionFailed(message: error.localizedDescription)
        }
    }
}

/// Process execution errors
enum ProcessError: LocalizedError {
    case executionFailed(message: String)
    case commandFailed(exitCode: Int32, message: String)
    case sudoFailed(exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case let .executionFailed(message):
            return "Process execution failed: \(message)"
        case let .commandFailed(exitCode, message):
            return "Command failed with exit code \(exitCode): \(message)"
        case let .sudoFailed(exitCode, message):
            return "Sudo command failed with exit code \(exitCode): \(message)"
        }
    }
}