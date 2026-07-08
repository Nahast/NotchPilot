import CoreServices
import Foundation

/// Thin wrapper around an FSEventStream watching one or more directory trees.
/// Callbacks arrive on the given dispatch queue.
final class FSEventsWatcher {
    private var streamRef: FSEventStreamRef?
    private let paths: [String]
    private let latency: CFTimeInterval
    private let queue: DispatchQueue
    private let handler: () -> Void

    init(paths: [String], latency: CFTimeInterval, queue: DispatchQueue, handler: @escaping () -> Void) {
        self.paths = paths
        self.latency = latency
        self.queue = queue
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard streamRef == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handler()
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(
                UInt32(kFSEventStreamCreateFlagUseCFTypes)
                    | UInt32(kFSEventStreamCreateFlagFileEvents)
                    | UInt32(kFSEventStreamCreateFlagNoDefer)
            )
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        streamRef = stream
    }

    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }
}
