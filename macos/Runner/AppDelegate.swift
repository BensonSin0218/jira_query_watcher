import Cocoa
import FlutterMacOS
import Security
import ServiceManagement
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private let settings = UserDefaults.standard
  private var methodChannel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  weak var mainWindow: MainFlutterWindow?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    UNUserNotificationCenter.current().delegate = self
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  func configureMethodChannel(
    for flutterViewController: FlutterViewController,
    window: MainFlutterWindow
  ) {
    mainWindow = window
    methodChannel = FlutterMethodChannel(
      name: "jira_query_watcher/native",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    configureStatusItem()

    if settings.bool(forKey: "launchAtLogin") {
      DispatchQueue.main.async {
        window.orderOut(nil)
      }
    }
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showMainWindow()
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .sound])
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadSettings":
      result(loadSettings())
    case "saveSettings":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "設定格式不正確。", details: nil))
        return
      }
      saveSettings(arguments)
      result(nil)
    case "saveSnapshot":
      guard let arguments = call.arguments as? [String: Any],
            let snapshotJson = arguments["snapshotJson"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "快照格式不正確。", details: nil))
        return
      }
      settings.set(snapshotJson, forKey: "snapshotJson")
      if let timestamp = arguments["lastCheckedAt"] as? NSNumber {
        settings.set(timestamp.int64Value, forKey: "lastCheckedAt")
      }
      settings.set(true, forKey: "hasSnapshot")
      result(nil)
    case "clearSnapshot":
      settings.removeObject(forKey: "snapshotJson")
      settings.removeObject(forKey: "lastCheckedAt")
      settings.set(false, forKey: "hasSnapshot")
      result(nil)
    case "requestNotificationPermission":
      requestNotificationPermission(result: result)
    case "showNotification":
      guard let arguments = call.arguments as? [String: Any],
            let title = arguments["title"] as? String,
            let body = arguments["body"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "通知格式不正確。", details: nil))
        return
      }
      showNotification(title: title, body: body, result: result)
    case "setLaunchAtLogin":
      guard let arguments = call.arguments as? [String: Any],
            let enabled = arguments["enabled"] as? Bool else {
        result(FlutterError(code: "invalid_arguments", message: "登入啟動設定不正確。", details: nil))
        return
      }
      setLaunchAtLogin(enabled: enabled, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func loadSettings() -> [String: Any] {
    let token = readToken() ?? ""
    return [
      "baseUrl": settings.string(forKey: "baseUrl") ?? "",
      "username": settings.string(forKey: "username") ?? "",
      "token": token,
      "hasToken": !token.isEmpty,
      "jql": settings.string(forKey: "jql") ?? "",
      "intervalMinutes": settings.integer(forKey: "intervalMinutes") == 0
        ? 5
        : settings.integer(forKey: "intervalMinutes"),
      "authMode": settings.string(forKey: "authMode") ?? "cloud",
      "watchesJson": settings.string(forKey: "watchesJson") ?? "",
      "watchStatesJson": settings.string(forKey: "watchStatesJson") ?? "",
      "enabled": settings.bool(forKey: "enabled"),
      "launchAtLogin": settings.bool(forKey: "launchAtLogin"),
      "snapshotJson": settings.string(forKey: "snapshotJson") ?? "",
      "hasSnapshot": settings.bool(forKey: "hasSnapshot"),
      "lastCheckedAt": settings.object(forKey: "lastCheckedAt") as? NSNumber ?? 0,
    ]
  }

  private func saveSettings(_ arguments: [String: Any]) {
    let stringKeys = [
      "baseUrl",
      "username",
      "jql",
      "authMode",
      "watchesJson",
      "watchStatesJson",
    ]
    for key in stringKeys {
      if let value = arguments[key] as? String {
        settings.set(value, forKey: key)
      }
    }
    if let interval = arguments["intervalMinutes"] as? NSNumber {
      settings.set(interval.intValue, forKey: "intervalMinutes")
    }
    if let enabled = arguments["enabled"] as? Bool {
      settings.set(enabled, forKey: "enabled")
    }
    if let launchAtLogin = arguments["launchAtLogin"] as? Bool {
      settings.set(launchAtLogin, forKey: "launchAtLogin")
    }
    if let token = arguments["token"] as? String, !token.isEmpty {
      _ = saveToken(token)
    }
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      _, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "notification_permission",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private func showNotification(
    title: String,
    body: String,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "notification",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private func setLaunchAtLogin(enabled: Bool, result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(FlutterError(
        code: "unsupported",
        message: "登入後自動啟動需要 macOS 13 或以上。",
        details: nil
      ))
      return
    }

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      settings.set(enabled, forKey: "launchAtLogin")
      result(nil)
    } catch {
      result(FlutterError(
        code: "launch_at_login",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private var keychainQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Bundle.main.bundleIdentifier ?? "jira_query_watcher",
      kSecAttrAccount as String: "jira-api-token",
    ]
  }

  private func saveToken(_ token: String) -> OSStatus {
    let data = Data(token.utf8)
    let status = SecItemUpdate(
      keychainQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if status == errSecItemNotFound {
      var item = keychainQuery
      item[kSecValueData as String] = data
      return SecItemAdd(item as CFDictionary, nil)
    }
    return status
  }

  private func readToken() -> String? {
    var query = keychainQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func configureStatusItem() {
    guard statusItem == nil else { return }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem?.button?.title = "Jira"

    let menu = NSMenu()
    let showItem = NSMenuItem(
      title: "Show Jira Query Watcher",
      action: #selector(showMainWindow),
      keyEquivalent: ""
    )
    showItem.target = self
    menu.addItem(showItem)
    menu.addItem(NSMenuItem.separator())
    let quitItem = NSMenuItem(
      title: "Quit",
      action: #selector(quitApplication),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    statusItem?.menu = menu
  }

  @objc private func showMainWindow() {
    mainWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quitApplication() {
    NSApp.terminate(nil)
  }
}
