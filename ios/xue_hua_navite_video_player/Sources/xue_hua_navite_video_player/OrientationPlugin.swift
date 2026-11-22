import CoreMotion
import Flutter
import UIKit

/// iOS 原生设备方向控制与物理重力传感器插件实现。
///
/// 使用 `CMMotionManager` 监听三轴加速度计并通过重力向量 $(x, y, z)$ 解算真实物理朝向，
/// 完全无视系统控制中心的“竖屏方向锁定”；结合 iOS 16+ `UIWindowScene.requestGeometryUpdate`
/// 与低版本兼容方案实现丝滑强制横竖屏切换，并支持查询当前真实界面方向以彻底消除锁屏/解锁
/// 时的 180° 误旋转问题。
final class OrientationPlugin: NSObject, OrientationHostApi {
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.kurban.xue_hua_navite_video_player.orientation_motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var flutterApi: OrientationFlutterApi?
    private var isListening = false
    private var lastEmittedOrientation: DevicePhysicalOrientation = .unknown
    private var pendingOrientation: DevicePhysicalOrientation?
    private var debounceWorkItem: DispatchWorkItem?

    /// 滞回死区半角（度）：±20° 防止躺卧观看时在 45°/135° 临界线附近频繁抖动。
    private static let enterHalfRangeDegrees: Double = 25.0
    private static let retainHalfRangeDegrees: Double = 45.0
    private static let debounceIntervalSeconds: TimeInterval = 0.30
    private static let flatZThreshold: Double = 0.75
    private static let minPlanarMagnitude: Double = 0.45

    func attach(binaryMessenger: FlutterBinaryMessenger) {
        flutterApi = OrientationFlutterApi(binaryMessenger: binaryMessenger)
        OrientationHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: self)
    }

    func detach(binaryMessenger: FlutterBinaryMessenger) {
        stopSensorListeningInternal()
        OrientationHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: nil)
        flutterApi = nil
    }

    // MARK: - OrientationHostApi

    func setTargetOrientation(orientation: DevicePhysicalOrientation) async throws {
        await MainActor.run {
            applyInterfaceOrientation(orientation)
        }
    }

    func getCurrentOrientation() async throws -> DevicePhysicalOrientation {
        return await MainActor.run {
            currentInterfaceOrientation()
        }
    }

    func startSensorListening() throws {
        guard !isListening else { return }
        guard motionManager.isAccelerometerAvailable else { return }

        isListening = true
        motionManager.accelerometerUpdateInterval = 0.05 // 20 Hz
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let acceleration = data?.acceleration else { return }
            self.handleAcceleration(
                x: acceleration.x,
                y: acceleration.y,
                z: acceleration.z
            )
        }
    }

    func stopSensorListening() throws {
        stopSensorListeningInternal()
    }

    func setImmersiveFullscreen(enabled: Bool) async throws {
        await MainActor.run {
            guard let rootVC = Self.activeRootViewController() else { return }
            rootVC.setNeedsStatusBarAppearanceUpdate()
            rootVC.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    // MARK: - Gravity Vector Orientation Calculation

    private func handleAcceleration(x: Double, y: Double, z: Double) {
        // 1. 过滤平放姿态（桌面平放或仰卧正上方）
        let planarMagnitude = hypot(x, y)
        if abs(z) > Self.flatZThreshold || planarMagnitude < Self.minPlanarMagnitude {
            return
        }

        // 2. 计算平面物理旋转角度（0° = 竖屏正向，90° = 顺时针右横，180° = 倒置，270° = 逆时针左横）
        // CoreMotion 坐标系：竖屏正向时 x ≈ 0, y ≈ -1；
        // 逆时针 90°（顶部朝左 landscapeLeft）时 x ≈ -1, y ≈ 0 -> atan2(-1, 0) = -90° -> 270°；
        // 顺时针 90°（顶部朝右 landscapeRight）时 x ≈ +1, y ≈ 0 -> atan2(+1, 0) = +90° -> 90°。
        var angleDegrees = atan2(x, -y) * 180.0 / .pi
        if angleDegrees < 0 {
            angleDegrees += 360.0
        }

        // 3. 主动过滤 portraitDown（135° ~ 225° 倒置姿态）
        if angleDegrees >= 135.0 && angleDegrees <= 225.0 {
            return
        }

        let resolved = resolveWithHysteresis(
            angleDegrees: angleDegrees,
            previous: lastEmittedOrientation
        )
        guard resolved != .unknown else { return }

        let confidence = computeConfidence(
            angleDegrees: angleDegrees,
            orientation: resolved,
            z: z
        )

        scheduleDebouncedEmit(
            orientation: resolved,
            confidence: confidence,
            angleDegrees: angleDegrees
        )
    }

    private func resolveWithHysteresis(
        angleDegrees: Double,
        previous: DevicePhysicalOrientation
    ) -> DevicePhysicalOrientation {
        let enterHalf = Self.enterHalfRangeDegrees
        let retainHalf = Self.retainHalfRangeDegrees

        // 严格进入区间（±25° 围绕 0° / 90° / 270°）
        if Self.angularDistance(angleDegrees, 0.0) <= enterHalf {
            return .portraitUp
        }
        if Self.angularDistance(angleDegrees, 270.0) <= enterHalf {
            return .landscapeLeft
        }
        if Self.angularDistance(angleDegrees, 90.0) <= enterHalf {
            return .landscapeRight
        }

        // 位于滞回死区（25° ~ 45°）时，保持上一次已确认方向，避免临界抽搐
        switch previous {
        case .portraitUp where Self.angularDistance(angleDegrees, 0.0) <= retainHalf:
            return .portraitUp
        case .landscapeLeft where Self.angularDistance(angleDegrees, 270.0) <= retainHalf:
            return .landscapeLeft
        case .landscapeRight where Self.angularDistance(angleDegrees, 90.0) <= retainHalf:
            return .landscapeRight
        default:
            return .unknown
        }
    }

    private func computeConfidence(
        angleDegrees: Double,
        orientation: DevicePhysicalOrientation,
        z: Double
    ) -> Double {
        let targetAngle: Double
        switch orientation {
        case .portraitUp:
            targetAngle = 0.0
        case .landscapeLeft:
            targetAngle = 270.0
        case .landscapeRight:
            targetAngle = 90.0
        case .unknown:
            return 0.0
        }
        let dist = Self.angularDistance(angleDegrees, targetAngle)
        let angleFactor = max(0.0, min(1.0, 1.0 - dist / 45.0))
        let zFactor = max(0.0, min(1.0, 1.0 - abs(z)))
        return max(0.0, min(1.0, angleFactor * 0.6 + zFactor * 0.4))
    }

    private func scheduleDebouncedEmit(
        orientation: DevicePhysicalOrientation,
        confidence: Double,
        angleDegrees: Double
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isListening else { return }
            if orientation == self.lastEmittedOrientation {
                self.pendingOrientation = nil
                self.debounceWorkItem?.cancel()
                self.debounceWorkItem = nil
                return
            }
            if self.pendingOrientation == orientation {
                return
            }

            self.pendingOrientation = orientation
            self.debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isListening else { return }
                self.lastEmittedOrientation = orientation
                self.pendingOrientation = nil
                self.debounceWorkItem = nil
                let event = OrientationSensorEvent(
                    orientation: orientation,
                    confidence: confidence,
                    angleDegrees: angleDegrees
                )
                Task { @MainActor [weak self] in
                    try? await self?.flutterApi?.onPhysicalOrientationChanged(event: event)
                }
            }
            self.debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.debounceIntervalSeconds,
                execute: workItem
            )
        }
    }

    private func stopSensorListeningInternal() {
        isListening = false
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        DispatchQueue.main.async { [weak self] in
            self?.debounceWorkItem?.cancel()
            self?.debounceWorkItem = nil
            self?.pendingOrientation = nil
        }
    }

    // MARK: - Interface Orientation Control

    @MainActor
    private func applyInterfaceOrientation(_ orientation: DevicePhysicalOrientation) {
        // 关键映射：
        // DevicePhysicalOrientation.landscapeLeft（顶部朝左、Home 在右）
        //   == UIInterfaceOrientation.landscapeRight / UIInterfaceOrientationMask.landscapeRight
        // DevicePhysicalOrientation.landscapeRight（顶部朝右、Home 在左）
        //   == UIInterfaceOrientation.landscapeLeft / UIInterfaceOrientationMask.landscapeLeft
        let mask: UIInterfaceOrientationMask
        let legacyDeviceOrientation: UIDeviceOrientation
        switch orientation {
        case .portraitUp:
            mask = .portrait
            legacyDeviceOrientation = .portrait
        case .landscapeLeft:
            mask = .landscapeRight
            legacyDeviceOrientation = .landscapeLeft
        case .landscapeRight:
            mask = .landscapeLeft
            legacyDeviceOrientation = .landscapeRight
        case .unknown:
            mask = .allButUpsideDown
            legacyDeviceOrientation = .unknown
        }

        if #available(iOS 16.0, *) {
            if let rootVC = Self.activeRootViewController() {
                rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if let windowScene = Self.activeWindowScene() {
                let preferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: mask
                )
                windowScene.requestGeometryUpdate(preferences) { _ in
                    // Ignore transient scene rejection if already transitioning.
                }
            }
        } else {
            if legacyDeviceOrientation != .unknown {
                UIDevice.current.setValue(legacyDeviceOrientation.rawValue, forKey: "orientation")
            }
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    @MainActor
    private func currentInterfaceOrientation() -> DevicePhysicalOrientation {
        guard let windowScene = Self.activeWindowScene() else {
            return .unknown
        }
        switch windowScene.interfaceOrientation {
        case .portrait:
            return .portraitUp
        case .landscapeRight:
            // Home button on right -> device top on left -> landscapeLeft
            return .landscapeLeft
        case .landscapeLeft:
            // Home button on left -> device top on right -> landscapeRight
            return .landscapeRight
        default:
            return .unknown
        }
    }

    // MARK: - Helpers

    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360.0)
        return diff > 180.0 ? 360.0 - diff : diff
    }

    @MainActor
    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    @MainActor
    private static func activeRootViewController() -> UIViewController? {
        guard let scene = activeWindowScene() else { return nil }
        let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        return keyWindow?.rootViewController
    }
}
