import Foundation
import NetScopeCore

typealias BaselineStoreFactory = () throws -> any TrafficBaselineStoring

final class BaselinePersistenceController: @unchecked Sendable {
    private let store: any TrafficBaselineStoring
    private let queue: DispatchQueue

    init(
        store: any TrafficBaselineStoring,
        queue: DispatchQueue = DispatchQueue(label: "NetScope.BaselinePersistence", qos: .utility)
    ) {
        self.store = store
        self.queue = queue
    }

    func save(_ baseline: TrafficBaseline, completion: @escaping @MainActor (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            let warning: String?
            do {
                try self.store.save(baseline)
                warning = nil
            } catch {
                warning = "Could not save learned baseline."
            }

            Task { @MainActor in
                completion(warning)
            }
        }
    }

    func clear(completion: @escaping @MainActor (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            let warning: String?
            do {
                try self.store.clear()
                warning = nil
            } catch {
                warning = "Could not clear learned baseline."
            }

            Task { @MainActor in
                completion(warning)
            }
        }
    }
}
