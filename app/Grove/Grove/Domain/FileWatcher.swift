// Domain/FileWatcher.swift
// Grove
//
// FSEvents-based file system watcher.

import Foundation
import os

final class FileWatcher: Sendable {

    private let paths: [String]
    private let latency: CFTimeInterval
    private let queue: DispatchQueue
    private let box: StreamBox

    init(
        paths: [String],
        latency: CFTimeInterval = 0.5,
        handler: @escaping @Sendable () -> Void
    ) {
        self.paths = paths
        self.latency = latency
        self.queue = DispatchQueue(label: "grove.filewatcher", qos: .utility)
        self.box = StreamBox(handler: handler)
    }

    deinit { box.stop() }

    func start() {
        guard !box.isRunning else { return }

        Logger.fileWatcher.info("Starting file watcher for paths: \(self.paths.joined(separator: ", "), privacy: .public)")

        let cfPaths = paths as CFArray

        // C function pointer — cannot capture context, so we pass the box via FSEventStreamContext.info
        let callback: FSEventStreamCallback = { _, info, numEvents, _, _, _ in
            guard let info else { return }
            let b = Unmanaged<StreamBox>.fromOpaque(info).takeUnretainedValue()
            Logger.fileWatcher.debug("FSEvents callback fired: \(numEvents, privacy: .public) event(s)")
            b.invokeHandler()
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Logger.fileWatcher.error("FSEventStreamCreate failed for paths: \(self.paths.joined(separator: ", "), privacy: .public)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        box.set(stream: stream)
        Logger.fileWatcher.info("File watcher started")
    }

    func stop() {
        Logger.fileWatcher.info("Stopping file watcher")
        box.stop()
        Logger.fileWatcher.info("File watcher stopped")
    }
}

private final class StreamBox: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let lock = NSLock()
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    var isRunning: Bool { lock.withLock { stream != nil } }

    func set(stream: FSEventStreamRef) {
        lock.withLock { self.stream = stream }
    }

    func invokeHandler() {
        DispatchQueue.main.async { [handler] in handler() }
    }

    func stop() {
        lock.withLock {
            guard let s = stream else { return }
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }
}
