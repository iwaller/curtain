import Foundation
import CoreGraphics
import Darwin

/// A disposable wallpaper worker. It has no display, input or authentication responsibilities.
@main
enum RendererMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let parent = getppid()
        guard parent > 1 else { exit(1) }
        let watcher = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global())
        watcher.setEventHandler { _exit(1) }
        watcher.resume()
        guard getppid() == parent else { exit(1) }
        // Independent of the parent reader, including a blocked stdout write.
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { _exit(1) }
        withExtendedLifetime(watcher) {
            let args = CommandLine.arguments
            guard args.count == 4, let width = Double(args[2]), let height = Double(args[3]),
                  let image = BackdropRenderer.render(url: URL(fileURLWithPath: args[1]), size: CGSize(width: width, height: height)),
                  let packet = BackdropPacket.encode(image) else { exit(1) }
            do { try FileHandle.standardOutput.write(contentsOf: packet) }
            catch { exit(1) }
        }
    }
}
