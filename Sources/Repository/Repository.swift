//
//  Repository.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 22/12/2018.
//

import Foundation

protocol Repository {
    associatedtype Resource

    func save(_ resource: Resource) throws
    func delete(_ resource: Resource) throws
    func getAll() throws -> [Resource]
    func get(where filter: (Resource) -> Bool) throws -> [Resource]
}
