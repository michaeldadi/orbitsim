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

@MainActor
@Observable
private final class FixtureLocationState: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status = "not read"
    var coordinate = "none"
    var updateCount = 0
    var isTracking = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        readPermission()
    }

    func readPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: status = "not determined"
        case .restricted: status = "restricted"
        case .denied: status = "denied"
        case .authorizedAlways: status = "always"
        case .authorizedWhenInUse: status = "when in use"
        @unknown default: status = "unknown"
        }
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    func start() {
        isTracking = true
        if manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        isTracking = false
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.readPermission()
            if self?.isTracking == true { self?.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let latitude = latest.coordinate.latitude
        let longitude = latest.coordinate.longitude
        let count = locations.count
        Task { @MainActor [weak self] in
            self?.coordinate = String(format: "%.6f, %.6f", latitude, longitude)
            self?.updateCount += count
        }
    }
}

private struct FixtureView: View {
    @State private var tapCount = 0
    @State private var enteredText = ""
    @State private var lastLink = "none"
    @State private var pushState = FixturePushState.shared
    @State private var notificationStatus = "not requested"
    @State private var locationState = FixtureLocationState()

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
                Button("Read location permission") { locationState.readPermission() }
                    .accessibilityIdentifier("fixture.location-read")
                Button("Request location") { locationState.requestPermission() }
                    .accessibilityIdentifier("fixture.location-request")
            }
            Text("Location permission: \(locationState.status)")
                .accessibilityIdentifier("fixture.location-status")
            HStack {
                Button(locationState.isTracking ? "Stop tracking" : "Track location") {
                    if locationState.isTracking { locationState.stop() }
                    else { locationState.start() }
                }
                .accessibilityIdentifier("fixture.location-track")
                Text("Location: \(locationState.coordinate) · \(locationState.updateCount) updates")
                    .accessibilityIdentifier("fixture.location-coordinate")
            }
            Spacer()
        }
        .padding(30)
        .onOpenURL { lastLink = $0.absoluteString }
        .onAppear { locationState.readPermission() }
        .onDisappear { locationState.stop() }
    }
}
