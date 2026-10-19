import Foundation

actor SharedTaskStore<Key: Hashable & Sendable, Value> {
    private struct Entry {
        let generation: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Value, Error>]
    }

    private var entries: [Key: Entry] = [:]

    func value(for key: Key, operation: @escaping () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if var entry = entries[key] {
                    entry.waiters[waiterID] = continuation
                    entries[key] = entry
                    return
                }

                let generation = UUID()
                let task = Task {
                    let result: Result<Value, Error>
                    do {
                        result = .success(try await operation())
                    } catch {
                        result = .failure(error)
                    }
                    finish(key: key, generation: generation, result: result)
                }
                entries[key] = Entry(generation: generation, task: task, waiters: [waiterID: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key: key, waiterID: waiterID) }
        }
    }

    private func finish(key: Key, generation: UUID, result: Result<Value, Error>) {
        guard let entry = entries[key], entry.generation == generation else { return }
        entries[key] = nil
        for continuation in entry.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func cancel(key: Key, waiterID: UUID) {
        guard var entry = entries[key], let continuation = entry.waiters.removeValue(forKey: waiterID) else { return }
        if entry.waiters.isEmpty {
            entries[key] = nil
            entry.task.cancel()
        } else {
            entries[key] = entry
        }
        continuation.resume(throwing: CancellationError())
    }
}
