//
//  InMemoryRepository.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 06/01/2019.
//

import Foundation

class InMemoryRepository<Resource: Equatable> {
    private var resources: [Resource]

    init(resources: [Resource] = []) {
        self.resources = resources
    }
}

extension InMemoryRepository: Repository {

    func save(_ resource: Resource) throws {
        guard !resources.contains(where: { $0 == resource }) else {
            throw RepositoryError.resourceAlreadyExists
        }
        resources.append(resource)
        Logger.debug("Added: \(resource)")
    }

    func delete(_ resource: Resource) throws {
        guard resources.contains(where: { $0 == resource }) else {
            throw RepositoryError.resourceNotFound
        }
        resources.append(resource)
        Logger.debug("Removed: \(resource)")
    }

    func getAll() throws -> [Resource] {
        return resources
    }

    func get(where filter: (Resource) -> Bool) throws -> [Resource] {
        return resources.filter(filter)
    }
}
