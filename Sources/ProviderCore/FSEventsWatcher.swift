import CoreServices
import Foundation

/// Thin wrapper around an FSEventStream watching one or more directory trees.
/// Callbacks arrive on the given dispatch queue and carry the paths FSEvents
/// reported, so a watcher's owner can work on what changed instead of
/// rescanning everything it watches.
public final class FSEventsWatcher {
    private var streamRef: FSEventStreamRef?
    private let paths: [String]
    private let latency: CFTimeInterval
    private let queue: DispatchQueue
    private let handler: ([String]) -> Void

    public init(paths: [String], latency: CFTimeInterval, queue: DispatchQueue, handler: @escaping ([String]) -> Void) {
        self.paths = paths
        self.latency = latency
        self.queue = queue
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// FSEvents reports the firmlinked real path ("/private/var/…") while a
    /// URL built for that same directory keeps the "/var" alias, so the two
    /// spellings have to be reconciled before any path comparison. Only
    /// /private/{var,tmp,etc} exist, and all three are aliases.
    public static func canonicalPath(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }

    public func start() {
        guard streamRef == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            // kFSEventStreamCreateFlagUseCFTypes makes eventPaths a CFArray of
            // CFString rather than a C string array.
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            watcher.handler(paths)
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

    public func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }
}
