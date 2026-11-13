// The capture stream for the live-state strip's reader (docs/specs/29.md, section 8).
//
// It captures a rectangle of one display many times a second and writes the pixels to its
// standard output. It knows nothing of the strip's format: tools/hellolink_strip.py reads the
// frames and does the rest. It keeps nothing: no file is written.
//
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

// Every way out stops the stream first. A stream whose program just dies stays open in the
// system's capture service; after some hundreds of those the service gives no frame to anyone.
var live: SCStream?
let leaving = NSLock()
var left = false

func finish(_ code: Int32) {
    leaving.lock()
    let first = !left
    left = true
    leaving.unlock()
    guard first else { return }
    guard let stream = live else { exit(code) }
    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { exit(code) } // a stop that hangs
    stream.stopCapture { _ in exit(code) }
}

final class Frames: NSObject, SCStreamOutput, SCStreamDelegate {
    var left: Int
    let out = FileHandle.standardOutput

    init(count: Int) { left = count }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only whole frames: a sample can be an idle or a blank notice with no new picture.
        guard type == .screen, sample.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sample.imageBuffer else { return }
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

let arguments = CommandLine.arguments
var keep: [Any] = [] // the stream and its output must outlive the task that made them

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays
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
            fail("usage: strip_capture list | stream <display> <x> <y> <width> <height> <frames a second> [count]")
        }
        let display = displays[numbers[0]]
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: CGFloat(numbers[1]) / scale, y: CGFloat(numbers[2]) / scale,
                                          width: CGFloat(numbers[3]) / scale, height: CGFloat(numbers[4]) / scale)
        configuration.width = numbers[3]
        configuration.height = numbers[4]
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(numbers[5]))
        configuration.showsCursor = false
        configuration.queueDepth = 3
        let frames = Frames(count: numbers.count > 6 ? numbers[6] : 0)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: frames)
        try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
        keep = [stream, frames]
        live = stream
        try await stream.startCapture()
    } catch {
        fail("capture failed: \(error.localizedDescription)")
    }
}
RunLoop.main.run()
