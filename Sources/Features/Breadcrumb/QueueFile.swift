import Foundation

@objcMembers
public class Queue<T>: NSObject {
    private var elements: [T] = []

    func enqueue(_ element: T) {
        elements.append(element)
    }

    func dequeue() -> T? {
        if elements.isEmpty {
            return nil
        } else {
            return elements.removeFirst()
        }
    }

    func peek() -> T? {
        return elements.first
    }

    func pop() -> T? {
        guard !elements.isEmpty else {
                return nil
            }
        return elements.popLast()
    }
    
    public func allElements() -> [T] {
        return elements
    }

    func clear() {
        elements.removeAll()
    }
    
    var isEmpty: Bool {
        return elements.isEmpty
    }

    var count: Int {
        return elements.count
    }
}
