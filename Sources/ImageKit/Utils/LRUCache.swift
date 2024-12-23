//
//  LRUCache.swift
//  ImageKit
//
//  Created by saucymqin on 2020/1/7.
//

import Foundation

public class Node<K: Hashable, V> {
    var next: Node?
    weak var previous: Node?
    var key: K
    var value: V

    init(key: K, value: V) {
        self.key = key
        self.value = value
    }
}

public class LinkedList<K: Hashable, V> {
    var head: Node<K, V>?
    weak var tail: Node<K, V>?

    func addToHead(node: Node<K, V>) {
        if head == nil  {
            head = node
            tail = node
        } else {
            node.next = head
            head?.previous = node
            head = node
        }
    }
    
    func addToTail(node: Node<K, V>) {
        if head == nil  {
            head = node
            tail = node
        } else {
            node.previous = tail
            tail?.next = node;
            tail = node
        }
    }

    func remove(node: Node<K, V>) {
        if node === head {
            if head?.next != nil {
                head = head?.next
                head?.previous = nil
            } else {
                head = nil
                tail = nil
            }
        } else if node.next != nil {
            node.previous?.next = node.next
            node.next?.previous = node.previous
        } else {
            node.previous?.next = nil
            tail = node.previous
        }
    }
}

/// read write remove O(1)
open class LRUCache<K: Hashable, V> {
    public let capacity: Int
    public var count = 0
    private let queue = LinkedList<K, V>()
    private var hashTable: [K : Node<K, V>]

    public init(capacity: Int) {
        self.capacity = capacity
        self.hashTable = [K : Node<K, V>](minimumCapacity: capacity)
    }

    public subscript (key: K) -> V? {
        get {
            if let node = hashTable[key] {
                queue.remove(node: node)
                queue.addToHead(node: node)
                return node.value
            } else {
                return nil
            }
        }

        set(value) {
            if let node = hashTable[key] {
                queue.remove(node: node)
                if let value = value {
                    node.value = value
                    queue.addToHead(node: node)
                } else {
                    hashTable[key] = nil
                }
            } else {
                guard let value = value else { return }
                let node = Node(key: key, value: value)

                if count < capacity {
                    queue.addToHead(node: node)
                    hashTable[key] = node

                    count = count + 1
                } else {
                    if let tail = queue.tail {
                        hashTable.removeValue(forKey: tail.key)
                        queue.remove(node: tail)
                    }

                    queue.addToHead(node: node)
                    hashTable[key] = node
                }
            }
        }
    }

    public func clean() {
        queue.head = nil
        queue.tail = nil
        count = 0
        hashTable.removeAll()
    }
}

extension Node: CustomStringConvertible {
    public var description: String {
        return "(\(key): \(value))"
    }
}

extension LRUCache: CustomStringConvertible {
    public var description: String {
        return queue.reduce("\(type(of: self))(\(count)) \n", { $0 + "\($1)\n" })
    }
}

public struct LinkedListIterator<K: Hashable, V>: IteratorProtocol {
    var current: Node<K, V>?
    mutating public func next() -> Node<K, V>? {
        let next = current
        current = current?.next
        return next
    }
}

extension LinkedList: Sequence {
    public func makeIterator() -> LinkedListIterator<K, V> {
        return LinkedListIterator(current: head)
    }
}


extension LRUCache: Sequence {
    public func makeIterator() -> LinkedListIterator<K, V> {
        return queue.makeIterator()
    }
}
