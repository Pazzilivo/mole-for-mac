import Foundation

// MetricCollector protocol
protocol MetricCollector {
    associatedtype Output
    func collect() async throws -> Output
}