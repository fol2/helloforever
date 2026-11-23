// The capture stream for the live-state strip's reader (docs/specs/29.md, section 8).
//
// It captures a rectangle of one display many times a second and writes the pixels to its
// standard output. It knows nothing of the strip's format: tools/hellolink_strip.py reads the
// frames and does the rest. It keeps nothing: no file is written.
//
//   strip_capture [--colour srgb|display] [--window <application name>] list | stream ...
//       `--window`: the largest window of that application (the game: "Wow"), not a display. It
//       is read as the game draws it, also while another window is over it (the owner, 23 Nov
//       2026: the reader reads the game's window, not the screen). `list` then gives that window
//       as display 0, and `stream 0 ...` takes the rectangle from the window's top-left corner.
//       `--colour display`: the pixels in the display's own colour space (docs/specs/232.md,
//       part C), not in sRGB (the default). The stream then fails when a frame comes in
//       another colour space.
//   strip_capture list
//       one line a display: index, width and height in pixels (no line when the displays
//       are asleep)
//   strip_capture stream <display index> <x> <y> <width> <height> <frames a second> [count]
//       the rectangle, in pixels from the display's top-left corner; `count` frames, or
//       without it until the reader closes the pipe
//
// A frame on the output: the four bytes "HLC1", the width and the height as 32-bit
// little-endian numbers, then width * height * 4 bytes, blue green red alpha, rows from the
// top. A frame comes when something in the rectangle changed, and once at the start.
//
// macOS shows other programs' windows only to a program with Screen Recording consent.
//
// Build: swiftc -O -swift-version 5 tools/strip_capture.swift -o <somewhere>/strip_capture

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

// Every way out stops the stream first, so that nothing is left for the system's capture
// service to clean up after a program that just died.
// `gate` guards the three facts below, so that a stop and the start cannot pass each other.
let gate = NSLock()
var live: SCStream?      // set before the start is asked for
var started = false      // the start came back
var leaving: Int32?      // the exit code, once somebody asked to leave

// Asks for the stop and returns: the stop's answer, or two seconds, ends the program. The
// caller may be the frames queue, which must not be held.
func stopThenExit(_ stream: SCStream, _ code: Int32) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { exit(code) } // a stop that hangs
    stream.stopCapture { _ in exit(code) }
}

// The starter's two steps. Each returns the exit code when somebody already asked to leave.
func note(made stream: SCStream) -> Int32? {
    gate.lock()
    defer { gate.unlock() }
    live = stream
    return leaving
}

func noteStarted() -> Int32? {
    gate.lock()
    defer { gate.unlock() }
    started = true
    return leaving
}

func asked() -> Int32? {
    gate.lock()
    defer { gate.unlock() }
    return leaving
}

func finish(_ code: Int32) {
    gate.lock()
    let first = leaving == nil
    if first { leaving = code }
    let stream = live, running = started
    gate.unlock()
    guard first else { return }
    guard let stream = stream else { exit(code) }     // no stream was made
    if running { return stopThenExit(stream, code) }
    // The start is on its way: the starter sees `leaving` when it comes back and stops the
    // stream itself. If the start never comes back, leave anyway.
    DispatchQueue.global().asyncAfter(deadline: .now() + 4) { exit(code) }
}

final class Frames: NSObject, SCStreamOutput, SCStreamDelegate {
    var left: Int
    let out = FileHandle.standardOutput
    /// With `--colour display`: the display's colour space, which each frame must carry.
    let space: CGColorSpace?

    init(count: Int, space: CGColorSpace?) { left = count; self.space = space }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only whole frames: a sample can be an idle or a blank notice with no new picture.
        guard asked() == nil else { return }     // leaving: no frame after the last one
        guard type == .screen, sample.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sample.imageBuffer else { return }
        if let space = space {
            let carried = CVBufferCopyAttachment(buffer, kCVImageBufferCGColorSpaceKey, nil)
            guard let carried = carried, CFEqual(carried, space) else {
                FileHandle.standardError.write("the frame is not in the display's colour space\n".data(using: .utf8)!)
                return finish(2)
            }
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var data = Data(capacity: 12 + width * height * 4)
        data.append(contentsOf: Array("HLC1".utf8))
        for number in [UInt32(width).littleEndian, UInt32(height).littleEndian] {
            withUnsafeBytes(of: number) { data.append(contentsOf: $0) }
        }
        for y in 0..<height {
            data.append(Data(bytes: base + y * stride, count: width * 4))
        }
        do { try out.write(contentsOf: data) } catch { return finish(0) } // the reader closed the pipe
        if left > 0 {
            left -= 1
            if left == 0 { finish(0) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if let code = asked() { exit(code) }     // the stop we asked for
        fail("the capture stopped: \(error.localizedDescription)", 2)
    }
}

// A closed pipe is an error on the write, not a death; a request to stop is a clean stop.
signal(SIGPIPE, SIG_IGN)
var stops: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT, SIGHUP] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler { finish(0) }
    source.resume()
    stops.append(source)
}

var arguments = CommandLine.arguments
var inDisplaySpace = false
if arguments.count >= 3, arguments[1] == "--colour" {
    guard ["srgb", "display"].contains(arguments[2]) else { fail("--colour: srgb or display, not \(arguments[2])") }
    inDisplaySpace = arguments[2] == "display"
    arguments.removeSubrange(1...2)
}
var windowOf: String?
if arguments.count >= 3, arguments[1] == "--window" {
    windowOf = arguments[2]
    arguments.removeSubrange(1...2)
}
var keep: [Any] = [] // the stream and its output must outlive the task that made them
_ = CGMainDisplayID() // starts the window server's connection: a window's filter needs it (it asserts otherwise)

// Streams `numbers` (display, x, y, width, height, frames a second, [count]) of `filter`: the
// rectangle in pixels from the filter's top-left corner. `space`: the colour space each frame must
// carry (`--colour display`), or nil for sRGB.
func start(filter: SCContentFilter, scale: CGFloat, numbers: [Int], space: CGColorSpace?) async throws {
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = CGRect(x: CGFloat(numbers[1]) / scale, y: CGFloat(numbers[2]) / scale,
                                      width: CGFloat(numbers[3]) / scale, height: CGFloat(numbers[4]) / scale)
    configuration.width = numbers[3]
    configuration.height = numbers[4]
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    // With no name, ScreenCaptureKit gives the display's own colour space (seen on 22 Nov
    // 2026: the frames carry the space that CGDisplayCopyColorSpace gives). A display's
    // space has no name, so it cannot be named here.
    if space == nil { configuration.colorSpaceName = CGColorSpace.sRGB }
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(numbers[5]))
    configuration.showsCursor = false
    configuration.queueDepth = 3
    let frames = Frames(count: numbers.count > 6 ? numbers[6] : 0, space: space)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: frames)
    try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
    keep = [stream, frames]
    if let code = note(made: stream) { exit(code) }           // asked to leave before the start: nothing is open
    try await stream.startCapture()
    if let code = noteStarted() { stopThenExit(stream, code) } // asked to leave during the start
}

Task {
    do {
        // a window may be on another Space or under another window: all windows are asked for then
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: windowOf == nil)
        let displays = content.displays
        if let name = windowOf {
            if inDisplaySpace { fail("--window takes the sRGB stream only") }
            let theirs = content.windows.filter { $0.owningApplication?.applicationName == name && $0.frame.width > 0 && $0.frame.height > 0 }
            guard let window = theirs.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                fail("no window of \(name) to capture", 3)
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let width = Int(window.frame.width * scale), height = Int(window.frame.height * scale)
            if arguments.count == 2, arguments[1] == "list" {
                print("0 \(width) \(height)")
                exit(0)
            }
            let numbers = arguments.dropFirst(2).compactMap { Int($0) }
            guard arguments.count >= 8, arguments[1] == "stream", numbers.count >= 6, numbers.count == arguments.count - 2,
                  numbers[0] == 0, numbers[3] > 0, numbers[4] > 0, numbers[5] > 0 else {
                fail("usage: strip_capture --window <application> list | stream 0 <x> <y> <width> <height> <frames a second> [count]")
            }
            try await start(filter: filter, scale: scale, numbers: numbers, space: nil)
            return
        }
        if displays.isEmpty, arguments.count >= 2, arguments[1] == "stream" {
            fail("no display to capture (the displays may be asleep)", 3)
        }
        if arguments.count == 2, arguments[1] == "list" {
            for (index, display) in displays.enumerated() {
                let scale = Int(SCContentFilter(display: display, excludingWindows: []).pointPixelScale)
                print("\(index) \(display.width * scale) \(display.height * scale)")
            }
            exit(0)
        }
        let numbers = arguments.dropFirst(2).compactMap { Int($0) }
        guard arguments.count >= 8, arguments[1] == "stream", numbers.count >= 6, numbers.count == arguments.count - 2,
              numbers[0] >= 0, numbers[0] < displays.count, numbers[3] > 0, numbers[4] > 0, numbers[5] > 0 else {
            fail("usage: strip_capture [--colour srgb|display] list | stream <display> <x> <y> <width> <height> <frames a second> [count]")
        }
        let display = displays[numbers[0]]
        let filter = SCContentFilter(display: display, excludingWindows: [])
        try await start(filter: filter, scale: CGFloat(filter.pointPixelScale), numbers: numbers,
                        space: inDisplaySpace ? CGDisplayCopyColorSpace(display.displayID) : nil)
    } catch {
        fail("capture failed: \(error.localizedDescription)")
    }
}
RunLoop.main.run()
