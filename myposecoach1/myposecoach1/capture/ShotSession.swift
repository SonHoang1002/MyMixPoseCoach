import Foundation
import UIKit

/// MỘT LẦN QUAY — nối tầng đo, phép chấm điểm, bộ giữ khung và kho ảnh lại với nhau.
///
/// Luồng mỗi khung hình trong lúc quay:
/// ```
///   khung camera ─→ đo (CÙNG hàm với ảnh mẫu) ─→ chấm điểm ─→ bộ giữ khung
///                                                                  │
///                          nhận ─→ lưu file mới + XOÁ file bị đá ra ┤
///                          loại ─→ không lưu gì cả ─────────────────┘
/// ```
///
/// Nhờ vậy **số file trên máy không bao giờ vượt sức chứa của bộ giữ**, kể cả khi
/// quay 30 giây liên tục.
///
/// ## Vì sao `nonisolated`
///
/// Bản Android chạy lớp này trong `withContext(Dispatchers.Default)` — quét 30 giây
/// video với vài trăm khung hình là việc nặng, đặt lên main thread là màn hình đứng
/// im nửa phút. Bản iOS giữ đúng quyết định đó: toàn bộ lớp là logic thuần (đo,
/// chấm, ghi file), không đụng UI, nên để chạy trên bất kỳ thread nào. Người gọi
/// tự lo việc bọc `Task.detached` hay `DispatchQueue.global()`.
nonisolated final class ShotSession {

    /// HỒ SƠ ẢNH MẪU.
    ///
    /// Để lộ ra ngoài (không `private`) vì engine hướng dẫn phải đọc **đúng hồ sơ
    /// này** — hai bên dùng chung một nguồn thì không thể xảy ra chuyện hướng dẫn
    /// chấm một kiểu còn chọn ảnh chấm một kiểu khác.
    let profile: TemplateProfile

    private let store: ShotStore
    private let minVisibility: Float
    private let buffer: BestShotBuffer

    /// Bộ nhận diện mặt. `nil` = bỏ qua góc mặt và mắt nhắm — hai mục đó tự bị
    /// loại khỏi cách tính, không trừ điểm.
    ///
    /// Nhận dưới dạng hàm thay vì một lớp `FaceAnalyzer` cụ thể: bản iOS chưa có
    /// bộ nhận diện mặt (cần Vision/ML Kit), và **không được chặn** việc chấm điểm
    /// chỉ vì thiếu nó — `nil` là trạng thái hợp lệ chứ không phải lỗi.
    private let faceAnalyze: ((UIImage) -> FaceInfo?)?

    /// Tỉ lệ khung người dùng chọn (ngang/dọc khi cầm dọc). Ảnh ra VÀ khung xương
    /// đem chấm đều cắt về tỉ lệ này — cùng vùng với khung xem trước. Xem `TiLeKhung`.
    private let tiLeKhung: Double?

    /// Dữ liệu giữ trong bộ nhớ cho từng khung đang được giữ.
    /// Tối đa bằng sức chứa bộ giữ.
    private struct Pending {
        let measurement: PoseMeasurement
        let sharpnessRaw: Double
        /// Điểm "không cắt ngang khớp", 0..1. Tính ngay lúc còn giữ khung hình.
        let crop: Double?
        /// Mắt có mở không, 0..1. Tính ngay vì sau đó ảnh không còn trong bộ nhớ.
        let eyesOpen: Double?
    }

    /// Ảnh mẫu này có bắt buộc phải đo góc MẶT ở từng khung không.
    ///
    /// Chỉ đúng với ảnh chân dung (CHEST/HEAD): ở đó góc mặt là nguồn đo hướng
    /// chính vì chính xác hơn góc thân (~3-5 độ so với ~8-10 độ).
    private let needFacePerFrame: Bool

    private var pending: [Int64: Pending] = [:]
    private var nextId: Int64 = 1

    /// Đã chốt danh sách chưa. Đã chốt thì [discard] không xoá nữa.
    private(set) var finished = false

    var sessionDir: URL { store.sessionDir }
    var keptCount: Int { buffer.size }

    init(
        store: ShotStore,
        profile: TemplateProfile,
        minVisibility: Float,
        buffer: BestShotBuffer = BestShotBuffer(),
        faceAnalyze: ((UIImage) -> FaceInfo?)? = nil,
        tiLeKhung: Double? = nil
    ) {
        self.store = store
        self.profile = profile
        self.minVisibility = minVisibility
        self.buffer = buffer
        self.faceAnalyze = faceAnalyze
        self.tiLeKhung = tiLeKhung
        self.needFacePerFrame = profile.framing.yawSource == .faceYaw
    }

    /// Tỉ lệ đích theo đúng chiều của ảnh (cầm ngang thì lật).
    private func tiLeCho(_ image: UIImage) -> Double? {
        guard let tiLeKhung else { return nil }
        let w = Int(image.size.width.rounded())
        let h = Int(image.size.height.rounded())
        return TiLeKhung.theoHuong(tiLeKhung, rong: w, cao: h)
    }

    /// Ngưỡng ĐẠT của một mục — để `ShotScorer` uốn thang điểm cho ăn khớp với
    /// dấu tích. Xem `ShotScorer.VUNG_DAT`.
    private func acceptCua(_ c: Criterion) -> Double? {
        GuidanceConfig.bandFor(
            criterion: c, framing: profile.framing, templateScale: profile.measurement.scale
        )?.accept
    }

    /// Đưa một khung hình vào xét.
    ///
    /// - Returns: `true` nếu khung được giữ lại (đã lưu ra file).
    func offer(anhGoc: UIImage, poseGoc: PoseFrame, timeMs: Int64) -> Bool {
        if finished { return false }
        if poseGoc.isEmpty { return false }

        // Cắt ảnh và khung xương về CÙNG một vùng — vùng người dùng thấy lúc chụp.
        // Tỉ lệ tính từ [UIImage.size] (đã áp cờ EXIF) chứ không từ pixel thô —
        // khung xương cũng nằm trong hệ nhìn thấy nên hai thứ phải cùng hệ.
        let tl = tiLeCho(anhGoc)
        let w = anhGoc.size.width
        let h = anhGoc.size.height
        let anh = store.cropToAspect(anhGoc, tl)
        let pose: PoseFrame
        if let tl {
            pose = poseGoc.croppedToAspect(targetAspect: tl, frameAspect: Double(w) / Double(h))
        } else {
            pose = poseGoc
        }

        // ⚠️ NHẬN DIỆN MẶT KHÔNG chạy ở đây nữa, trừ khi ảnh mẫu BẮT BUỘC cần.
        //
        // Trước đây nó chạy trên MỌI khung hình, kể cả khung sắp bị loại ngay ở
        // dòng dưới — mỗi lần là một lệnh chờ-đứng-máy tới 3 giây. Với 300 khung
        // hình của một đoạn 30 giây, riêng phần này đã chiếm hàng chục giây.
        //
        // Giờ chỉ chạy khi ảnh mẫu là CHÂN DUNG, vì lúc đó góc mặt là nguồn đo
        // hướng chính (`FramingClass.yawSource`) thì thiếu nó là chấm sai. Mọi
        // trường hợp còn lại, mắt-mở được chấm ở [finish] trên đúng 12 khung lọt
        // vào chung kết — vừa nhanh hơn ~25 lần, vừa CHÍNH XÁC HƠN: ở đây ảnh chỉ
        // ~480px nên khuôn mặt trong ảnh toàn thân quá nhỏ để nhận ra.
        let face = needFacePerFrame ? faceAnalyze?(anh) : nil

        // Bỏ góc máy suy từ ảnh: nó lẫn dáng đứng và ống kính, không so được với
        // nhãn góc của ảnh mẫu (FOOTGUNS 91). Cả lần quay đã được canh góc bằng
        // cảm biến từ trước, nên giữa các khung góc máy gần như không khác nhau.
        let measurement = Measurer.measure(
            pose, framing: profile.framing, minVisibility: minVisibility, face: face
        ).boGocMayTuAnh()

        // Chấm điểm KHÔNG kèm độ nét ở bước này — cố ý.
        //
        // Độ nét chỉ so được trong nội bộ một lần quay (xem [Sharpness]), mà lúc
        // đang quay thì chưa biết cả loạt sẽ ra sao. Nếu chuẩn hoá theo "cao nhất
        // tính tới lúc này" thì khung đầu tiên luôn được coi là nét nhất và chiếm
        // chỗ oan. Vậy nên: trong lúc quay xét theo hình học, lúc chốt mới đưa độ
        // nét vào để chấm lại toàn bộ.
        let score = ShotScorer.score(
            profile, candidate: measurement, stage: Stage.SELECTION, post: nil,
            acceptOf: acceptCua
        )

        let id = nextId
        nextId += 1
        let candidate = ShotCandidate(
            id: id,
            timeMs: timeMs,
            score: score.total,
            trustworthy: score.trustworthy,
            // Trải phẳng theo thứ tự nhóm CỐ ĐỊNH, nếu không hai khung cùng dáng
            // nhưng thứ tự nhóm khác nhau sẽ bị coi là khác dáng.
            poseSignature: PoseGroup.allCases.flatMap { measurement.poseAngles[$0] ?? [] }
        )

        guard case .accepted(let evicted) = buffer.offer(candidate) else { return false }

        if !store.save(id: id, image: anh) {
            // Ghi hỏng thì phải rút mục vừa thêm ra, nếu không màn kết quả sẽ có
            // một ô trỏ tới file không tồn tại.
            buffer.remove(id: id)
            return false
        }

        pending[id] = Pending(
            measurement: measurement,
            sharpnessRaw: Sharpness.of(anh),
            crop: CropQuality.of(pose, profile.framing, minVisibility),
            eyesOpen: face?.eyesOpen
        )

        for e in evicted {
            store.delete(id: e.id)
            pending.removeValue(forKey: e.id)
        }
        return true
    }

    /// Chốt lần quay: chấm lại có kèm độ nét, giữ [keepCount] khung tốt nhất, **xoá
    /// file của phần còn lại**, rồi ghi bảng kê cho màn kết quả đọc.
    ///
    /// - Parameter keepCount: số khung giữ lại.
    /// - Parameter highRes: lấy khung hình ở ĐỘ PHÂN GIẢI CAO tại một mốc thời gian.
    ///   `nil` = không lấy được, lúc đó vẫn chốt được nhưng thiếu các mục hậu kỳ.
    ///
    ///   Vì sao truyền vào dạng hàm thay vì để [ShotSession] tự mở video: lớp này
    ///   cố ý không biết gì về video — nó cũng phục vụ đường chụp liên tục, nơi
    ///   ảnh gốc đến từ máy ảnh chứ không từ file quay.
    func finish(
        keepCount: Int = 5,
        highRes: ((Int64) -> UIImage?)? = nil
    ) -> [ShotCandidate] {
        if finished { return store.readIndex() }

        let candidates = buffer.all()
        if candidates.isEmpty {
            finished = true
            store.writeIndex([])
            return []
        }

        // --- Vòng CHUNG KẾT: chỉ tối đa 12 khung, nên ở đây làm kỹ được ---
        //
        // Cắt lại ở độ phân giải cao NGAY BÂY GIỜ, trước khi xếp hạng, vì hai mục
        // hậu kỳ đều phải chấm trên chính tấm ảnh sẽ giao cho người dùng:
        //  - mắt nhắm: ảnh 480px không đủ để nhận ra khuôn mặt trong ảnh toàn thân
        //  - độ nét: đo trên ảnh đã thu nhỏ là đo độ nét của bản thu nhỏ
        var highResEyes: [Int64: Double?] = [:]
        var highResSharp: [Int64: Double] = [:]
        if let highRes {
            for c in candidates {
                guard let big0 = highRes(c.timeMs) else { continue }
                let big = store.cropToAspect(big0, tiLeCho(big0))
                _ = store.save(id: c.id, image: big)
                highResSharp[c.id] = Sharpness.of(big)
                if let faceAnalyze {
                    highResEyes[c.id] = faceAnalyze(big)?.eyesOpen
                }
            }
        }

        // Chuẩn hoá độ nét theo đúng loạt khung này, rồi chấm lại toàn bộ.
        let raws = candidates.map {
            highResSharp[$0.id] ?? pending[$0.id]?.sharpnessRaw ?? 0.0
        }
        let norms = Sharpness.normalize(raws)

        var rescored: [ShotCandidate] = []
        rescored.reserveCapacity(candidates.count)
        for (i, c) in candidates.enumerated() {
            guard let p = pending[c.id] else {
                rescored.append(c)
                continue
            }
            // Ưu tiên số đo trên ảnh độ phân giải cao; chỉ lùi về số đo trong lúc
            // quay khi không cắt lại được. `if let` gỡ MỘT tầng của `Double??`:
            // có khoá ⇒ lấy số đo cao (kể cả khi nó là `nil`), không có ⇒ giữ cũ.
            var eyesOpen = p.eyesOpen
            if let v = highResEyes[c.id] { eyesOpen = v }

            let s = ShotScorer.score(
                profile, candidate: p.measurement, stage: Stage.SELECTION,
                post: PostQuality(sharpness: norms[i], crop: p.crop, eyesOpen: eyesOpen),
                acceptOf: acceptCua
            )
            var c2 = c
            c2.score = s.total
            c2.trustworthy = s.trustworthy
            c2.parts = s.perCriterion
            rescored.append(c2)
        }
        rescored.sort(by: ShotCandidate.bestFirst)

        let kept = Array(rescored.prefix(keepCount))
        let keptIds = Set(kept.map { $0.id })

        // Xoá file của những khung không lọt vào danh sách cuối.
        for c in rescored where !keptIds.contains(c.id) {
            store.delete(id: c.id)
        }
        _ = buffer.keepOnly(ids: keptIds)
        pending = pending.filter { keptIds.contains($0.key) }

        store.writeIndex(kept)
        finished = true
        return kept
    }

    /// Bỏ cả lần quay. Xoá sạch, không để lại gì.
    func discard() {
        _ = buffer.clear()
        pending.removeAll()
        store.deleteSession()
        finished = true
    }
}
