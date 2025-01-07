import Foundation

public actor Queue<T> {
    private var elements: [T] = []

    /// Adds an element to the end of the queue.
    func enqueue(_ element: T) {
        elements.append(element)
    }

    /// Removes and returns the first element of the queue.
    func dequeue() async -> T? {
        return elements.isEmpty ? nil : elements.removeFirst()
    }

    /// Returns the first element of the queue without removing it.
    func peek() async -> T? {
        return elements.first
    }

    /// Removes a range of elements from the queue.
    func removeSubrange(_ range: Range<Int>) {
        elements.removeSubrange(range)
    }

    /// Removes and returns an element at a specified index.
    func remove(at index: Int) async -> T? {
        guard index >= 0 && index < elements.count else {
            return nil
        }
        return elements.remove(at: index)
    }

    /// Removes and returns the last element of the queue.
    func pop() async -> T? {
        return elements.isEmpty ? nil : elements.popLast()
    }

    /// Returns all elements of the queue.
    func allElements() async -> [T] {
        return elements
    }

    /// Clears all elements from the queue.
    func clear() {
        elements.removeAll()
    }

    /// Checks if the queue is empty.
    var isEmpty: Bool {
        return elements.isEmpty
    }

    /// Returns the number of elements in the queue.
    var count: Int {
        return elements.count
    }

    /// Checks if the queue contains a specific element.
    func contains(_ element: T) -> Bool where T: Equatable {
        return elements.contains(element)
    }
}
