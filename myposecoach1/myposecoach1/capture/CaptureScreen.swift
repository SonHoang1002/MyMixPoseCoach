import SwiftUI
import UIKit

// MÀN CHỤP THẬT — port 1:1 từ `capture/CaptureScreen.kt` (1617 dòng) của Android.
//
// Chia việc như bản Android:
//   - `CaptureViewModel` giữ TRẠNG THÁI (đo, hướng dẫn, quay, chấm điểm).
//   - Màn hình giữ VÒNG ĐỜI phần cứng: camera (`CaptureController`), bộ nhận diện
//     (`PoseDetector`), cảm biến nghiêng (`DeviceTilt`), và hai vòng lặp nền
//     (lấy cảm biến 33ms + đồng hồ quay).
//
// Khác Android VÌ NỀN TẢNG (mỗi dòng có lý do, không phải làm tắt):
//   - Không có `PreviewView` → bọc `AVCaptureVideoPreviewLayer` qua `PreviewHost`.
//   - Không có `LifecycleOwner` → bật/tắt camera trong `.onAppear` / `.onDisappear`.
//   - Không có nút back hệ thống → nút thoát là một nút trên màn hình.
//   - Android xin quyền ở MainActivity, màn chụp chỉ hiện PermissionNotice; iOS
//     không có chỗ đó nên xin quyền được gộp vào `CaptureController.start()` và
//     bản này thêm nút "Mở Cài đặt" mở thẳng Cài đặt quyền.
//   - Không có ML Kit Face Detector trên iOS → `face` luôn nil từ màn hình.
//   - Không có nút back hệ thống → thoát màn bằng chevron + "Đổi mẫu" ở cột phải.
struct CaptureScreen: View {
    let templateFile: URL
    var onBack: () -> Void = {}
    var onFinished: (URL) -> Void = { _ in }
    var onOpenLibrary: () -> Void = {}

    @StateObject private var vm = CaptureViewModel()

    /// Camera + bộ nhận diện sống theo vòng đời màn hình, KHÔNG phải của VM.
    @State private var controller: CaptureController?
    @State private var poseDetector: PoseDetector?
    @State private var tilt = DeviceTilt()

    /// Đã `startFresh` lần đầu chưa. Quay lại từ màn kết quả KHÔNG được xoá state
    /// của lần chụp vừa rồi (`onAppear` chạy lại nhưng `daKhoiTao` vẫn true).
    @State private var daKhoiTao = false

    /// Đang chờ bộ xử lý burst (ngăn chạm hai lần, giống cờ `isProcessing` Android).
    @State private var daHienBurst = false

    @State private var tiLeHienTai: TiLeKhung = .BA_BON
    @State private var cacMucZoom: [Float] = [0.5, 1, 2]
    @State private var zoomPinchBase: Float? = nil

    /// Lưới 3×3 do người dùng bật/tắt (Android: `hienLuoi`, mặc định TẮT).
    @State private var hienLuoi = false
    /// Khung xương có vẽ lên hay không (Android: `showSkeleton`, mặc định BẬT).
    @State private var hienKhungXuong = true
    /// Bảng số liệu đo — mở khi bấm chip "Thấy mẫu" (Android: `showDebug`).
    @State private var hienSoLieu = false

    // -----------------------------------------------------------------
    // Hằng số chung — khớp CaptureScreen.kt của Android.
    // -----------------------------------------------------------------
    private let MIN_VIS: Float = 0.5
    private let SCORE_STEP_MS: Int64 = 500
    private let AUTO_COUNTDOWN_SEC = 5
    private let BURST_COUNT = 8
    private let BURST_INTERVAL_MS: Int64 = 500
    /// Phải đủ ổn định bấy nhiêu mili-giây chế độ tự động mới đếm ngược.
    private let AUTO_STABLE_MS: Int64 = 800
    /// Khung hình đo để chấm điểm: cạnh ngắn.
    private let NGAN_CANH_DIEM = 480
    /// Cắt lại 5 ảnh cuối ở độ phân giải cao.
    private let CUOI_CAO = 1440

    var body: some View {
        Group {
            if vm.state.processing {
                ProcessingScreen(progress: vm.state.processProgress, note: vm.state.processNote)
            } else if vm.state.analyzingTemplate {
                TemplateAnalyzingScreen(thumb: vm.state.templateThumb)
            } else {
                cameraBody
            }
        }
        .onAppear { khoiTao() }
        .onDisappear { tatMay() }
        .task(id: templateFile) { await phanTichAnhMau() }
        .task(id: vm.state.cameraReady) {
            if vm.state.cameraReady, let c = controller {
                vm.onZoomMin(c.zoomRange().lowerBound)
                cacMucZoom = c.zoomStops()
            }
        }
        .task(id: vm.state.autoMode) {
            guard vm.state.autoMode else { return }
            await chuTrinhTuDong()
        }
        .task(id: vm.state.recording) {
            guard vm.state.recording else { return }
            await dongHoQuay()
        }
        .task { await vongLayCamBien() }
        .onChange(of: vm.state.finishedSession) { _, dir in
            if let dir { onFinished(dir) }
        }
    }

    // -----------------------------------------------------------------
    // Khởi tạo / thoát
    // -----------------------------------------------------------------

    private func khoiTao() {
        if !daKhoiTao {
            daKhoiTao = true
            vm.startFresh()
            vm.onShootModeChanged(cheDoCho(templateFile))
            // Mặc định 3:4 như Android. Người dùng có thể đổi ở hàng chip.
            vm.onTiLeKhungChanged(TiLeKhung.BA_BON.tiLe(manHinh: manHinhRatio))
        }
        batMay()
    }

    private func tatMay() {
        // THỨ TỰ BẮT BUỘC: dừng camera (chờ luồng phân tích dừng hẳn) RỒI mới
        // đóng bộ nhận diện — ngược là sập ở tầng C++ (xem CaptureController.stop()).
        controller?.stop()
        controller = nil
        poseDetector?.close()
        poseDetector = nil
        tilt.stop()
    }

    private func batMay() {
        guard controller == nil else { return }

        let detector = PoseDetector(
            onResult: { [vm] frame, stats in
                Task { @MainActor in
                    vm.onLiveFrame(rawFrame: frame, stats: stats, minVisibility: MIN_VIS)
                }
            },
            onError: { [vm] msg in
                Task { @MainActor in vm.onCameraError(msg) }
            },
            onFrameImage: nil
        )
        // Nạp model MediaPipe (~9MB) + dựng đồ thị C++ Ở LUỒNG NỀN. Nạp trên main
        // là bảng đứng im đúng lúc vừa bấm vào màn, và còn KHOÁ chết main khi
        // `phanTichAnhMau` (cũng đang nạp model) giữ MediaPipeGuard — đúng cảnh
        // "bấm vào là app đơ" người dùng báo. Tương đương `Dispatchers.Default`
        // bên Android. Khung hình đầu tiên về trễ thêm vài trăm mili-giây là vô
        // hại: `PoseDetector.detect` bỏ qua khi chưa có bộ nhận diện.
        Task.detached(priority: .userInitiated) { detector.setup() }
        poseDetector = detector

        let c = CaptureController(
            detector: detector,
            onReady: { [vm] live in
                Task { @MainActor in vm.onCameraReady(live) }
            },
            onRotationChanged: { [vm] rot in
                Task { @MainActor in vm.onRotationChanged(portrait: rot.isPortrait) }
            },
            onError: { [vm] msg in
                Task { @MainActor in vm.onCameraError(msg) }
            }
        )
        controller = c
        c.setShootMode(vm.mode)
        c.setMode(vm.state.burstMode ? .burst : .video)
        // Một tỉ lệ cho cả bốn chỗ (xem `TiLeKhung`) — đồng bộ ngay khi camera
        // dựng lại, đúng việc `LaunchedEffect(tiLe, …)` của Android làm.
        c.setTiLeKhung(tiLeHienTai.tiLe(manHinh: manHinhRatio))
        c.start()
        tilt.start()
    }

    /// Chế độ chụp theo nhóm ảnh mẫu — Android đặt TRƯỚC cho đúng nhóm
    /// (SELFIE = tự chụp bằng camera trước).
    private func cheDoCho(_ file: URL) -> ShootMode {
        switch MediaLibrary.TemplateKind.of(file.lastPathComponent) {
        case .MIRROR: return .TU_CHUP_GUONG
        case .SELFIE: return .TU_CHUP_CAM_TRUOC
        case .PHOTOGRAPHER: return .NGUOI_KHAC
        }
    }

    /// Chế độ camera SAU — nút xoay camera quay về đây khi rời camera trước.
    /// Ảnh mẫu gương thì về chế độ gương, còn lại về người khác chụp.
    private var cheDoCamSau: ShootMode {
        MediaLibrary.TemplateKind.of(templateFile.lastPathComponent) == .MIRROR
            ? .TU_CHUP_GUONG : .NGUOI_KHAC
    }

    /// Xoay camera trước/sau. Đổi camera trước/sau phải gắn lại toàn bộ camera
    /// nên báo controller TRƯỚC rồi mới đổi trạng thái — đúng thứ tự Android.
    private func xoayCamera() {
        let next: ShootMode = vm.mode.camTruoc ? cheDoCamSau : .TU_CHUP_CAM_TRUOC
        controller?.setShootMode(next)
        vm.onShootModeChanged(next)
    }

    /// Đổi tỉ lệ khung — MỘT tỉ lệ áp cho cả bốn chỗ (xem `TiLeKhung`):
    /// xem trước, phép đo live, góc mở dọc, ảnh ra.
    private func datTiLe(_ tl: TiLeKhung) {
        tiLeHienTai = tl
        let tiLe = tl.tiLe(manHinh: manHinhRatio)
        vm.onTiLeKhungChanged(tiLe)
        controller?.setTiLeKhung(tiLe)
        if let c = controller {
            vm.onVerticalFovChanged(c.verticalFovDeg(tiLeKhung: tiLe))
        }
    }

    private var manHinhRatio: Double {
        let b = UIScreen.main.bounds
        return b.width > 0 ? Double(b.width / b.height) : 3.0 / 4.0
    }

    // -----------------------------------------------------------------
    // Phân tích ảnh mẫu
    // -----------------------------------------------------------------

    private func phanTichAnhMau() async {
        let url = templateFile
        let ten = url.deletingPathExtension().lastPathComponent
        let khoi = await Task.detached(priority: .userInitiated) { () -> (thumb: UIImage?, frame: PoseFrame?) in
            guard let anh = UprightBitmap.decode(file: url, shortSide: 320) else {
                return (nil, nil)
            }
            let khung = StillPoseAnalyzer.analyze(image: anh, modelAsset: PoseDetector.MODEL_FULL)
            return (anh, khung)
        }.value
        vm.onTemplateAnalyzed(name: ten, thumb: khoi.thumb, frame: khoi.frame,
                              minVisibility: MIN_VIS, face: nil)
    }

    // -----------------------------------------------------------------
    // Camera body
    // -----------------------------------------------------------------

    private var cameraBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            previewArea
            topBar
            bottomPanel
        }
    }

    private var previewArea: some View {
        GeometryReader { geo in
            let tl = tiLeHienTai.tiLe(manHinh: manHinhRatio)
            ZStack {
                PreviewHost(layer: controller?.previewLayer)
                    .aspectRatio(tl, contentMode: .fit)
                    .clipped()
                if vm.state.liveDetectionActive && hienKhungXuong {
                    KhungXươngOverlay(state: vm.state)
                        .aspectRatio(tl, contentMode: .fit)
                        .clipped()
                }
                LuoiBaPhan(show: hienLuoi)
                    .aspectRatio(tl, contentMode: .fit)
                    .clipped()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(edges: .all)
        .gesture(pinchZoom)
    }

    /// Chụm hai ngón để zoom — màn iOS bọc thêm như bản Android có `setZoomRatio`.
    private var pinchZoom: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                guard let c = controller else { return }
                let base = zoomPinchBase ?? c.zoomRatio
                if zoomPinchBase == nil { zoomPinchBase = c.zoomRatio }
                c.setZoom(Float(Double(base) * Double(scale)))
            }
            .onEnded { _ in zoomPinchBase = nil }
    }

    /// Hai cột trên cùng — đúng bố cục `Row(SpaceBetween)` của Android:
    /// TRÁI = chip người + tiêu chí + khung xương + bảng số liệu;
    /// PHẢI = quay lại, ảnh mẫu, đổi tỉ lệ khung, bật lưới.
    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            // --- Cột trái ---
            VStack(alignment: .leading, spacing: 8) {
                // Bấm chip này để mở bảng số liệu đo (Android: `showDebug`).
                Button { hienSoLieu.toggle() } label: {
                    Text(vm.state.personDetected ? "● Thấy mẫu" : "○ Chưa thấy mẫu")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(vm.state.personDetected ? Ds.success : Ds.dangerText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Ds.overlayScrim)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                CriteriaProgress(criteria: vm.state.criteria, matchPercent: vm.state.matchPercent)
                    .frame(width: 150)
                CriteriaChecklist(criteria: vm.state.criteria)

                Button { hienKhungXuong.toggle() } label: {
                    Text(hienKhungXuong ? "Ẩn khung xương" : "Hiện khung xương")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Ds.overlayScrim)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if hienSoLieu {
                    SoLieuPanel(state: vm.state)
                }
            }

            Spacer(minLength: 0)

            // --- Cột phải ---
            VStack(alignment: .trailing, spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Ds.overlayScrim)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                if let thumb = vm.state.templateThumb {
                    TemplateCard(thumb: thumb)
                }

                Button(action: onBack) {
                    Text("Đổi mẫu")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Ds.overlayScrim)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Đổi tỉ lệ giữa lúc quay thì ảnh ra lẫn hai khung — khoá lại.
                let doiDuocKhung = !vm.state.recording && vm.state.burstTaken == 0
                Button { datTiLe(tiLeHienTai.tiep()) } label: {
                    Text("Khung \(tiLeHienTai.nhan)")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Ds.overlayScrim)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!doiDuocKhung)
                .opacity(doiDuocKhung ? 1 : 0.5)

                Button { hienLuoi.toggle() } label: {
                    Text(hienLuoi ? "Lưới ✓" : "Lưới")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Ds.overlayScrim)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// Khối dưới — đúng thứ tự Android: thước zoom → số đo tạm → lỗi ảnh mẫu →
    /// (PermissionNotice | CuePill + câu chỉ dẫn) → hai công tắc → cụm nút chụp.
    private var bottomPanel: some View {
        VStack(spacing: 10) {
            Spacer()

            if vm.state.cameraReady, let c = controller {
                ThuocZoom(zoom: c.zoomRatio, range: c.zoomRange()) { z in
                    c.setZoom(z)
                }
            }

            debugPanel

            if let loi = vm.state.templateError {
                Text("⚠ \(loi)")
                    .font(.system(size: 12))
                    .foregroundColor(Ds.dangerText)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }

            if vm.state.cameraError != nil && !vm.state.cameraReady {
                permissionNotice
            } else {
                CuePill(prepWarning: vm.state.prepWarning,
                        personDetected: vm.state.personDetected,
                        cue: vm.state.cue,
                        readyToCapture: vm.state.readyToCapture,
                        hasCriteria: !vm.state.criteria.isEmpty,
                        cueForModel: vm.state.cueForModel,
                        readyToPose: vm.state.readyToPose,
                        countdown: vm.state.countdown,
                        onTapWarning: { resetZoom() })
                    .padding(.horizontal, 12)
                Text(vm.state.autoMode
                     ? "Tự động sẽ bỏ qua mục bị kẹt sau khoảng 6 giây."
                     : "Bạn có thể bấm chụp bất cứ lúc nào.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, -4)
            }

            // Cong tac hai che do. An di trong luc dang quay/dang chup de
            // nguoi dung doi che do giua chung.
            if !vm.state.recording && vm.state.burstTaken == 0 {
                VStack(spacing: 8) {
                    AutoSwitch(on: vm.state.autoMode) { vm.onAutoModeChanged($0) }
                    ModeSwitch(burst: vm.state.burstMode) { burst in
                        controller?.setMode(burst ? .burst : .video)
                        vm.onModeChanged(burst: burst)
                    }
                }
            }

            cameraControls
        }
        .padding(.bottom, 8)
    }

    private var permissionNotice: some View {
        HStack(spacing: 10) {
            Text(vm.state.cameraError ?? "Camera đang bị tắt")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Button("Mở Cài đặt") {
                moCaiDat()
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Ds.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Ds.overlayPanel)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Ds.overlayScrim)
        .clipShape(Capsule())
        .padding(.horizontal, 12)
    }

    private var cameraControls: some View {
        // Đang quay hoặc đang chụp liên tiếp thì KHOÁ hai nút phụ: rời màn giữa
        // chừng là mất đoạn đang quay, còn xoay camera là phải gắn lại toàn bộ
        // camera.
        let dangBan = vm.state.recording || vm.state.burstTaken > 0

        return VStack(spacing: 8) {
            if vm.state.recording {
                Text(String(format: "● %.1fs / %.0fs",
                            Double(vm.state.recordedMs) / 1000.0,
                            Double(CaptureUiState.MAX_RECORD_MS) / 1000.0))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Ds.recording)
            } else if vm.state.burstTaken > 0 {
                Text("● đã chụp \(vm.state.burstTaken)/\(BURST_COUNT)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Ds.recording)
            }

            // Ba ô CHIA ĐỀU nên nút chụp luôn nằm đúng giữa, hai nút phụ đối
            // xứng hai bên — đúng bố cục camera gốc của cả iOS lẫn Android.
            HStack(alignment: .center) {
                NutPhu(enabled: !dangBan, icon: "photo.on.rectangle",
                       action: onOpenLibrary)
                    .frame(maxWidth: .infinity)

                NutQuay(recording: vm.state.recording,
                        isEnabled: vm.readyToRecord,
                        canStop: vm.state.canStop,
                        burstTaken: vm.state.burstTaken,
                        onTap: {
                            vm.onCountdown(nil)
                            if vm.state.recording {
                                dungQuay()
                            } else if vm.state.burstMode {
                                batDauBurst()
                            } else {
                                batDauQuay()
                            }
                        })
                    .frame(maxWidth: .infinity)

                NutPhu(enabled: !dangBan,
                       icon: "arrow.triangle.2.circlepath.camera.fill",
                       action: xoayCamera)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)

            Text(huongDanNut)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    /// Dòng chỉ dẫn dưới nút chụp — chữ y hệt Android.
    private var huongDanNut: String {
        if vm.state.recording && !vm.state.canStop { return "Giữ máy yên…" }
        if vm.state.recording { return "Bấm để dừng và chọn ảnh" }
        if vm.state.burstTaken > 0 { return "Đang chụp — giữ máy yên…" }
        if vm.state.burstMode { return "Bấm để chụp \(BURST_COUNT) tấm liên tiếp" }
        return "Bấm để quay 15-30 giây"
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let d = vm.state.debugDo { Text(d) }
            if let g = vm.state.debugGocMay { Text(g) }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(Ds.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: Ds.rSmall))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func moCaiDat() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func resetZoom() {
        controller?.resetZoom()
        vm.onZoomChanged(1)
    }

    // -----------------------------------------------------------------
    // Quay / chụp liên tục
    // -----------------------------------------------------------------

    private func batDauQuay() {
        guard vm.readyToRecord, !vm.state.recording else { return }
        let dir = ShotStore.recordingsDir()
        let url = dir.appendingPathComponent("capture-\(Int64(Date().timeIntervalSince1970 * 1000)).mov")
        vm.onRecordingStarted()
        controller?.startRecording(outputFile: url) { [weak vm] done in
            vm?.onRecordingStopped()
            if let done {
                xuLyVideo(done)
            } else {
                vm?.onProcessingFailed("Quay video hỏng — thử lại.")
            }
        }
    }

    private func dungQuay() {
        guard vm.state.recording else { return }
        controller?.stopRecording()
    }

    /// Hẹn giờ quay — dừng nhẹ nhàng ở mốc MAX_RECORD_MS như `CameraX` auto-stop.
    private func dongHoQuay() async {
        let batDau = CaptureViewModel.monotonicMs()
        while !Task.isCancelled && vm.state.recording {
            let ms = CaptureViewModel.monotonicMs() - batDau
            vm.onRecordingTick(ms)
            if ms >= CaptureUiState.MAX_RECORD_MS {
                dungQuay()
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // Cập nhật lần cuối để timer hiện đúng mốc dừng.
        if vm.state.recording {
            vm.onRecordingTick(CaptureViewModel.monotonicMs() - batDau)
        }
    }

    private func batDauBurst() {
        guard vm.readyToRecord, !daHienBurst, let c = controller else { return }
        daHienBurst = true
        let dir = ShotStore.burstDir()
        vm.onBurstProgress(0)
        c.captureBurst(
            dir: dir,
            count: BURST_COUNT,
            intervalMs: BURST_INTERVAL_MS,
            onProgress: { [weak vm] n in
                Task { @MainActor in vm?.onBurstProgress(n) }
            },
            onDone: { [weak vm] files in
                Task { @MainActor in
                    vm?.onBurstProgress(0)
                    xuLyBurst(files)
                }
            }
        )
    }

    // -----------------------------------------------------------------
    // Chấm điểm sau khi quay / chụp
    // -----------------------------------------------------------------

    /// `onDone` của quay video chạy trên MainActor (CaptureController đã hop) nên
    /// bắt đầu post-processing ngay được.
    private func xuLyVideo(_ url: URL) {
        guard let profile = vm.templateProfile else {
            vm.onProcessingFailed("Ảnh mẫu đã hết — vào lại màn chụp rồi thử lại.")
            return
        }
        let tiLeLuu = vm.tiLeKhung
        let store = ShotStore.createSession()
        let dir = store.sessionDir

        vm.onProcessing(0.02, "Đang xử lý video…")
        Task.detached(priority: .userInitiated) { [weak vm] in
            let session = ShotSession(
                store: store,
                profile: profile,
                minVisibility: MIN_VIS,
                tiLeKhung: tiLeLuu
            )
            let nguon = VideoFrameSource(file: url, targetShortSide: NGAN_CANH_DIEM)
            // Nguồn THỨ HAI để cắt lại 5 ảnh cuối ở độ phân giải cao — ảnh scan
            // chỉ 480px, cắt từ đó ra là đưa cho người dùng tấm ảnh bé tí.
            let nguonCao = VideoFrameSource(file: url, targetShortSide: CUOI_CAO)
            guard nguon.isValid, nguonCao.isValid else {
                nguon.close()
                nguonCao.close()
                session.discard()
                Task { @MainActor in
                    vm?.onProcessingFailed("Không đọc được video đã quay — thử lại.")
                }
                return
            }
            let analyser = VideoPoseAnalyzer()
            guard analyser.isReady else {
                nguon.close()
                nguonCao.close()
                analyser.close()
                session.discard()
                Task { @MainActor in
                    vm?.onProcessingFailed("Không nạp được model để chấm điểm — thử lại.")
                }
                return
            }

            // Quét từng khung hình, giữ khung đẹp vào `ShotSession` (nó tự xoá file
            // bị đá ra nên không bao giờ phình đĩa).
            let buoc = SCORE_STEP_MS
            var ts: Int64 = 0
            while ts < nguon.durationMs {
                if let anh = nguon.frameAt(timeMs: ts) {
                    if let khung = analyser.analyze(image: anh, timestampMs: ts) {
                        _ = session.offer(anhGoc: anh, poseGoc: khung, timeMs: ts)
                    }
                }
                ts += buoc
                let p = Float(ts) / Float(nguon.durationMs)
                Task { @MainActor in
                    vm?.onProcessing(0.05 + 0.85 * min(max(p, 0), 1),
                                     "Đang phân tích video (\(ts / 1000)s / \(nguon.durationMs / 1000)s)…")
                }
            }
            analyser.close()

            // Lọc 5 khung tốt nhất, cắt lại từ nguồn phân giải cao tại đúng mốc thời
            // gian của từng khung đã giữ (`ShotSession.finish` gọi highRes(cho t)).
            _ = session.finish(keepCount: 5) { t in
                nguonCao.frameAt(timeMs: t, exact: true)
            }
            nguon.close()
            nguonCao.close()

            guard session.keptCount > 0 else {
                session.discard()
                Task { @MainActor in
                    vm?.onProcessingFailed("Không tìm thấy người trong lần chụp này.")
                }
                return
            }
            Task { @MainActor in
                vm?.onFinished(sessionDir: dir)
            }
        }
    }

    /// Loạt ảnh burst: mỗi tấm là ẢNH CHỤP THẬT full resolution (không phải khung
    /// video), nên không cần hậu kỳ video. Vẫn đi qua `ShotSession` để chấm điểm và
    /// chọn 5 ảnh bằng ĐÚNG phép đo của video.
    private func xuLyBurst(_ files: [URL]) {
        guard !files.isEmpty else {
            vm.onProcessingFailed("Không chụp được ảnh nào — thử lại.")
            daHienBurst = false
            return
        }
        guard let profile = vm.templateProfile else {
            vm.onProcessingFailed("Ảnh mẫu đã hết — vào lại màn chụp rồi thử lại.")
            daHienBurst = false
            return
        }
        let tiLeLuu = vm.tiLeKhung
        let store = ShotStore.createSession()
        let dir = store.sessionDir
        // Mốc thời gian tính TRƯỚC khi rời MainActor — `wallMs()` là static của
        // VM (MainActor), không gọi được từ luồng nền.
        var moc = CaptureViewModel.wallMs() - Int64(files.count)

        vm.onProcessing(0.02, "Đang chấm điểm từng ảnh…")
        Task.detached(priority: .userInitiated) { [weak vm] in
            let session = ShotSession(
                store: store,
                profile: profile,
                minVisibility: MIN_VIS,
                tiLeKhung: tiLeLuu
            )
            for (i, f) in files.enumerated() {
                if let anh = UprightBitmap.decode(file: f) {
                    moc += 10
                    if let khung = StillPoseAnalyzer.analyze(
                        image: anh, modelAsset: PoseDetector.MODEL_FULL
                    ), !khung.isEmpty {
                        _ = session.offer(anhGoc: anh, poseGoc: khung, timeMs: moc)
                    } else {
                        NSLog("CaptureScreen: bỏ ảnh không tìm thấy người — \(f.lastPathComponent)")
                    }
                } else {
                    NSLog("CaptureScreen: không giải mã được \(f.lastPathComponent)")
                }
                let p = Float(i + 1) / Float(files.count)
                Task { @MainActor in
                    vm?.onProcessing(0.05 + 0.85 * p, "Đang chấm điểm từng ảnh…")
                }
            }

            _ = session.finish(keepCount: 5, highRes: nil)
            guard session.keptCount > 0 else {
                session.discard()
                Task { @MainActor in
                    daHienBurst = false
                    vm?.onProcessingFailed("Không tìm thấy người trong loạt ảnh này.")
                }
                return
            }
            Task { @MainActor in
                daHienBurst = false
                vm?.onFinished(sessionDir: dir)
            }
        }
    }

    // -----------------------------------------------------------------
    // Chế độ tự đếm ngược
    // -----------------------------------------------------------------

    private func chuTrinhTuDong() async {
        while !Task.isCancelled && vm.state.autoMode {
            if !vm.state.autoMode { return }
            if !vm.readyToRecord {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            if !vm.state.personDetected {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            if vm.state.stableForMs < AUTO_STABLE_MS {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            // Đủ ổn định → đếm ngược rồi tự bấm.
            for i in stride(from: AUTO_COUNTDOWN_SEC, through: 1, by: -1) {
                vm.onCountdown(i)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || !vm.state.autoMode { break }
            }
            vm.onCountdown(nil)
            if vm.state.autoMode {
                if vm.state.burstMode {
                    batDauBurst()
                } else {
                    batDauQuay()
                }
            }
            // Tự bấm xong là tắt tự động — không quay liên tục.
            vm.onAutoModeChanged(false)
            return
        }
    }

    /// Vòng lặp ~30 lần/giây: đẩy số cảm biến + zoom vào VM như `sensorLoop` Android.
    private func vongLayCamBien() async {
        while !Task.isCancelled {
            let r = tilt.state
            if r.hasData {
                vm.onSensorReading(angularSpeed: r.angularSpeedDegPerSec,
                                   rollDeg: r.rollDeg,
                                   pitchDeg: r.cameraPitchDeg)
            } else {
                vm.onSensorReading(angularSpeed: 0)
            }
            if let c = controller {
                vm.onZoomChanged(c.zoomRatio)
                if let tl = vm.tiLeKhung {
                    vm.onVerticalFovChanged(c.verticalFovDeg(tiLeKhung: tl))
                }
            }
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
    }
}

// =========================================================================
// Các màn con
// =========================================================================

/// Màn "Đang phân tích ảnh mẫu…" — khớp `TemplateAnalyzingScreen` của Android.
private struct TemplateAnalyzingScreen: View {
    var thumb: UIImage?

    var body: some View {
        ZStack {
            Ds.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
                }
                Text("Đang phân tích ảnh mẫu…")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Ds.text)
                ProgressView()
                    .tint(Ds.primary)
            }
        }
    }
}

/// Màn "Đang xử lý ảnh" — khớp `ProcessingScreen` của Android (emoji ✨, câu to,
/// thanh tiến trình full-width ≈ 0,82 màn hình).
private struct ProcessingScreen: View {
    var progress: Double
    var note: String

    var body: some View {
        ZStack {
            Ds.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Text("✨")
                    .font(.system(size: 44))
                Text("Đang xử lý ảnh")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Ds.text)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ds.surfaceMuted)
                        Capsule()
                            .fill(Ds.primary)
                            .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 22)
                .padding(.horizontal, 28)
                Text(note)
                    .font(.system(size: 13))
                    .foregroundColor(Ds.textMuted)
                Spacer()
            }
        }
    }
}

// =========================================================================
// Bộ phận giao diện
// =========================================================================

/// Khung xương vẽ lên khung xem trước — từ `state.pose` (đã cắt theo tỉ lệ, cùng
/// vùng người dùng nhìn thấy). Khớp `SkeletonOverlay` của Android.
private struct KhungXươngOverlay: View {
    let state: CaptureUiState

    var body: some View {
        Canvas { ctx, size in
            let pts = state.pose.points
            let vis = state.pose.visibility
            guard pts.count == Lm.count, vis.count == Lm.count else { return }
            for (a, b) in Lm.bones {
                guard a < pts.count, b < pts.count else { continue }
                guard vis[a] >= 0.5, vis[b] >= 0.5 else { continue }
                let p1 = pts[a]
                let p2 = pts[b]
                // Điểm rơi ra ngoài vùng cắt thì bỏ — khớp `at(minVisibility:)`.
                guard p1.x >= 0, p1.x <= 1, p1.y >= 0, p1.y <= 1,
                      p2.x >= 0, p2.x <= 1, p2.y >= 0, p2.y <= 1 else { continue }
                var path = Path()
                path.move(to: CGPoint(x: p1.x * size.width, y: p1.y * size.height))
                path.addLine(to: CGPoint(x: p2.x * size.width, y: p2.y * size.height))
                ctx.stroke(path, with: .color(Color.green.opacity(0.85)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Lưới 3×3 — do người dùng bật/tắt bằng nút "Lưới" ở cột phải (Android:
/// `hienLuoi`), KHÔNG tự hiện theo `readyToPose`.
private struct LuoiBaPhan: View {
    var show: Bool

    var body: some View {
        if show {
            Canvas { ctx, size in
                let mau = Color.white.opacity(0.22)
                for i in 1...2 {
                    let x = size.width * CGFloat(i) / 3
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(mau), lineWidth: 1)
                }
                for i in 1...2 {
                    let y = size.height * CGFloat(i) / 3
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(mau), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Thước zoom có quai kéo — port `ThuocZoom` của Android:
///   - Vạch chia logarit quanh mức đang chọn: `x = giữa + 260·log2(z/current)`.
///   - Kéo ngang: `z = z·2^(−Δpx/260)` ─ con số 260 = số điểm một quãng bát độ.
///   - SwiftUI cung cấp `translation` CỘNG DỒN nên phải tự lấy đenta giữa hai sự
///     kiện, khớp `dragAmount` tăng dần của Compose.
private struct ThuocZoom: View {
    var zoom: Float
    var range: ClosedRange<Float>
    var onChanged: (Float) -> Void

    @State private var dangKeo = false
    @State private var zKeo: Float = 1
    @State private var lastX: CGFloat = 0

    private var lo: Float { range.lowerBound }
    private var hi: Float { range.upperBound }
    /// Mức đang hiện trên thước: mức đang kéo hay mức thật của máy.
    private var hienTai: Float { dangKeo ? zKeo : zoom }

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            Canvas { ctx, size in
                let mau = Color.white.opacity(dangKeo ? 0.9 : 0.4)
                var t = lo
                let buoc = max((hi - lo) / 24, 0.001)
                while t <= hi {
                    let x = half + CGFloat(log(Double(t / hienTai)) / log(2.0)) * 260
                    if x >= -24 && x <= size.width + 24 {
                        let chinh = abs(t - t.rounded()) < 0.0001
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x, y: size.height - (chinh ? 18 : 9)))
                        ctx.stroke(p, with: .color(mau), lineWidth: 1)
                    }
                    t += buoc
                }
            }
            .frame(height: 34)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dangKeo {
                            dangKeo = true
                            zKeo = zoom
                            lastX = v.translation.width
                        }
                        let delta = v.translation.width - lastX
                        lastX = v.translation.width
                        if delta != 0 {
                            zKeo = min(max(zKeo * Float(pow(2.0, -Double(delta) / 260.0)), lo), hi)
                            onChanged(zKeo)
                        }
                    }
                    .onEnded { _ in
                        dangKeo = false
                    }
            )
        }
        .frame(height: 34)
    }
}

/// Công tắc hai chế độ tự chụp — `AutoSwitch` của Android: chip "Tự bấm" /
/// "Tự động đếm 5s".
private struct AutoSwitch: View {
    var on: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ModeChip(label: "Tự bấm", selected: !on) { onChange(false) }
            ModeChip(label: "Tự động đếm 5s", selected: on) { onChange(true) }
        }
    }
}

/// Công tắc hai chế độ quay/chụp — `ModeSwitch` của Android. ẨN đi trong lúc
/// đang quay/đang chụp để người dùng không đổi chế độ giữa chừng.
private struct ModeSwitch: View {
    var burst: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ModeChip(label: "Quay video", selected: !burst) { onChange(false) }
            ModeChip(label: "Chụp liên tục", selected: burst) { onChange(true) }
        }
        .padding(3)
        .background(Ds.overlayScrim)
        .clipShape(Capsule())
    }
}

/// Một chip chế độ — `ModeChip` của Android: được chọn thì nền trắng chữ đậm.
private struct ModeChip: View {
    var label: String
    var selected: Bool
    var onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .bold : .regular))
                .foregroundColor(selected ? Ds.text : .white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Nút tròn phụ (thư viện / xoay camera) — `NutTronPhu` của Android. Tắt trong
/// lúc đang quay/đang chụp.
private struct NutPhu: View {
    var enabled: Bool
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Ds.overlayPanel)
                .clipShape(Circle())
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Bảng số liệu đo thô — công cụ đo đạc, ẩn mặc định (`DebugPanel` Android).
/// Mở bằng chip "Thấy mẫu" ở cột trái.
private struct SoLieuPanel: View {
    var state: CaptureUiState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            dong("Ảnh mẫu", state.templateFraming?.displayName ?? "?")
            dong("Điểm nhận được", "\(state.visiblePoints) / 33")
            dong("Góc xoay thân",
                 state.bodyYawDeg.map { String(format: "%.1f°", $0) } ?? "—")
            dong("Mỗi khung", "\(state.inferenceMs) ms")
        }
        .padding(8)
        .background(Ds.overlayPanel)
        .clipShape(RoundedRectangle(cornerRadius: Ds.rSmall))
        .frame(maxWidth: 220, alignment: .leading)
    }

    private func dong(_ ten: String, _ giaTri: String) -> some View {
        HStack {
            Text(ten)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(giaTri)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

/// NÚT QUAY/CHỤP GIỮA MÀN HÌNH — CHẠM để bật, CHẠM LẠI để dừng, đúng
/// `onToggle` của Android (KHÔNG phải giữ-ngón-tay như bản port trước).
private struct NutQuay: View {
    var recording: Bool
    var isEnabled: Bool
    var canStop: Bool
    var burstTaken: Int
    var onTap: () -> Void

    /// Vòng ngoài trắng mờ, lõi đổi màu theo trạng thái — khớp Android.
    private var mauLoi: Color {
        if !isEnabled { return Color.white.opacity(0.4) }
        if recording || burstTaken > 0 { return Ds.recording }
        return .white
    }

    /// Chạm được: máy sẵn sàng, và (đang quay thì phải qua được mốc dừng),
    /// và chưa chụp dở loạt burst.
    private var nhanDuoc: Bool {
        isEnabled && (!recording || canStop) && burstTaken == 0
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 76, height: 76)
            Circle()
                .fill(mauLoi)
                .frame(width: 60, height: 60)
        }
        .contentShape(Circle())
        .onTapGesture {
            if nhanDuoc { onTap() }
        }
    }
}