import Flutter

/// The class Flutter registers: connects the generated Pigeon channels to their implementations.
public class FlutterTwilioConversationsClientPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let events = ConversationsEvents()
    ConversationsHostApiSetup.setUp(binaryMessenger: messenger, api: ConversationsHostApiImpl(events: events))
    EventsStreamHandler.register(with: messenger, streamHandler: events)
  }
}
