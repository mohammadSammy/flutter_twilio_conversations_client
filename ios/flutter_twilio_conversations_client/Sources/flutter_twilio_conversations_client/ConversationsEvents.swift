/// Holds the Dart listener; native code reports every `PlatformEvent` through `send`.
final class ConversationsEvents: EventsStreamHandler {
  private var sink: PigeonEventSink<PlatformEvent>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<PlatformEvent>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func send(_ event: PlatformEvent) {
    sink?.success(event)
  }
}
