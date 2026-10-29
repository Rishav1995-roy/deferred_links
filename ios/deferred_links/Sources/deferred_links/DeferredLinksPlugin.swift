import Flutter
import UIKit

/// Receives Universal Links / custom-scheme URLs and provides coarse device
/// signals for deferred-link matching. No clipboard access happens here.
public class DeferredLinksPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let checkedKey = "dev.rishav.deferred_links.checked"

  private var sink: FlutterEventSink?
  private var initialLink: String?
  private var lastDelivered: (url: String, at: Date)?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DeferredLinksPlugin()
    let methods = FlutterMethodChannel(
      name: "dev.rishav/deferred_links", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "dev.rishav/deferred_links/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    registrar.addApplicationDelegate(instance)
    // Apps on the UIScene lifecycle (new Flutter templates) get links through the scene
    // delegate. The selector is looked up at runtime so the plugin still compiles on older
    // Flutter versions that do not have `addSceneDelegate:`.
    let selector = NSSelectorFromString("addSceneDelegate:")
    if (registrar as AnyObject).responds(to: selector) {
      _ = (registrar as AnyObject).perform(selector, with: instance)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getInitialLink":
      result(initialLink)
    case "getInstallReferrer":
      // Android only. iOS has no install referrer.
      result(["status": "unavailable"])
    case "isFirstLaunch":
      result(!UserDefaults.standard.bool(forKey: Self.checkedKey))
    case "markDeferredChecked":
      UserDefaults.standard.set(true, forKey: Self.checkedKey)
      result(nil)
    case "getDeviceSignals":
      result(Self.deviceSignals())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func deviceSignals() -> [String: Any] {
    var systemInfo = utsname()
    uname(&systemInfo)
    let model = withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
    let bounds = UIScreen.main.bounds
    return [
      "platform": "ios",
      "osVersion": UIDevice.current.systemVersion,
      "model": model,
      "screenWidth": Int(min(bounds.width, bounds.height)),
      "screenHeight": Int(max(bounds.width, bounds.height)),
      "language": Locale.preferredLanguages.first ?? "",
      "timezoneOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
    ]
  }

  // MARK: FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: UIApplicationDelegate forwarding

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
  ) -> Bool {
    if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
      initialLink = url.absoluteString
    } else if let dict = launchOptions[UIApplication.LaunchOptionsKey.userActivityDictionary]
      as? [AnyHashable: Any]
    {
      for value in dict.values {
        if let activity = value as? NSUserActivity,
          activity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = activity.webpageURL
        {
          initialLink = url.absoluteString
        }
      }
    }
    return true
  }

  public func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([Any]) -> Void
  ) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL
    else { return false }
    deliver(url)
    return false
  }

  public func application(
    _ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    deliver(url)
    return false
  }

  // MARK: UIScene lifecycle (called by Flutter's scene delegate forwarding)

  @objc(scene:willConnectToSession:options:)
  public func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) -> Bool {
    if let url = connectionOptions.urlContexts.first?.url {
      deliver(url)
    } else if let activity = connectionOptions.userActivities.first(where: {
      $0.activityType == NSUserActivityTypeBrowsingWeb
    }), let url = activity.webpageURL {
      deliver(url)
    }
    return false
  }

  @objc(scene:openURLContexts:)
  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    if let url = URLContexts.first?.url { deliver(url) }
    return false
  }

  @objc(scene:continueUserActivity:)
  public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
      deliver(url)
    }
    return false
  }

  private func deliver(_ url: URL) {
    // The app and scene delegates can both report the same open; drop the echo.
    let now = Date()
    if let last = lastDelivered, last.url == url.absoluteString, now.timeIntervalSince(last.at) < 1 {
      return
    }
    lastDelivered = (url.absoluteString, now)
    if let sink = sink {
      sink(url.absoluteString)
    } else if initialLink == nil {
      initialLink = url.absoluteString
    }
  }
}
