import CoreLocation
import Observation
import SwiftUI
import UIKit
import UserNotifications

@main
struct OrbitFixtureApp: App {
    @UIApplicationDelegateAdaptor(FixtureAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            FixtureView()
        }
    }
}

@MainActor
@Observable
private final class FixturePushState {
    static let shared = FixturePushState()
    var lastTitle = "none"
    var count = 0

    func received(title: String) {
        lastTitle = title
        count += 1
    }
}

private final class FixtureAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let title = notification.request.content.title
        Task { @MainActor in FixturePushState.shared.received(title: title) }
        completionHandler([])
    }
}

private struct FixtureView: View {
    @State private var tapCount = 0
    @State private var enteredText = ""
    @State private var lastLink = "none"
    @State private var pushState = FixturePushState.shared
    @State private var notificationStatus = "not requested"
    @State private var locationManager = CLLocationManager()
    @State private var locationStatus = "not read"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("OrbitFixture")
                .font(.largeTitle.bold())
            Text("Ready")
                .accessibilityIdentifier("fixture.status")
            Button("Tap target") { tapCount += 1 }
                .accessibilityIdentifier("fixture.tap")
            Text("Taps: \(tapCount)")
                .accessibilityIdentifier("fixture.tap-count")
            TextField("Type here", text: $enteredText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fixture.input")
            Text("Input: \(enteredText)")
                .accessibilityIdentifier("fixture.input-value")
            Text("Link: \(lastLink)")
                .accessibilityIdentifier("fixture.link")
            Button("Enable notifications") {
                Task {
                    do {
                        let granted = try await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge])
                        notificationStatus = granted ? "allowed" : "denied"
                        if granted { UIApplication.shared.registerForRemoteNotifications() }
                    } catch {
                        notificationStatus = "error"
                    }
                }
            }
            .accessibilityIdentifier("fixture.notification-permission")
            Text("Notifications: \(notificationStatus)")
                .accessibilityIdentifier("fixture.notification-status")
            Text("Push: \(pushState.count) · \(pushState.lastTitle)")
                .accessibilityIdentifier("fixture.push")
            HStack {
                Button("Read location permission") { refreshLocationPermission() }
                    .accessibilityIdentifier("fixture.location-read")
                Button("Request location") { locationManager.requestWhenInUseAuthorization() }
                    .accessibilityIdentifier("fixture.location-request")
            }
            Text("Location permission: \(locationStatus)")
                .accessibilityIdentifier("fixture.location-status")
            Spacer()
        }
        .padding(30)
        .onOpenURL { lastLink = $0.absoluteString }
        .onAppear { refreshLocationPermission() }
    }

    private func refreshLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined: locationStatus = "not determined"
        case .restricted: locationStatus = "restricted"
        case .denied: locationStatus = "denied"
        case .authorizedAlways: locationStatus = "always"
        case .authorizedWhenInUse: locationStatus = "when in use"
        @unknown default: locationStatus = "unknown"
        }
    }
}
