import Foundation

/// BỘ GIỮ KHUNG HÌNH TỐT NHẤT — chạy TRONG LÚC quay, không phải lọc sau khi quay.
///
/// Vì sao không lưu hết rồi lọc sau: quay 30 giây ở 10 khung/giây là 300 tấm ảnh.
/// Lưu hết ra máy rồi mới lọc thì vừa chậm, vừa để lại một đống rác nếu app bị
/// tắt giữa chừng. Ở đây **số file trên máy không bao giờ vượt quá [capacity]**,
/// và mỗi lần một khung bị đá ra thì file của nó bị xoá ngay.
///
/// Hai luật xếp chỗ:
///
///  1. **Cách nhau về thời gian** ([minGapMs]) — không có luật này thì 5 tấm được
///     chọn rất dễ nằm gọn trong nửa giây, khác nhau không đáng kể.
///  2. **Đủ căn cứ thắng thiếu căn cứ** — một khung chỉ đo được 1-2 mục vẫn có
///     thể ra điểm cao, nhưng đó là điểm cao của sự thiếu thông tin (xem
///     `ShotScore.trustworthy`). Khung đo được đủ mục luôn đứng trên.
///
/// Lớp này là logic thuần, không đụng gì tới nền tảng — nên kiểm thử tự động được.
nonisolated final class BestShotBuffer {

    /// Số khung giữ lại tối đa. Lấy nhiều hơn 5 để còn chỗ so cuối phiên.
    let capacity: Int

    /// Hai khung được giữ phải cách nhau ít nhất bấy nhiêu mili-giây.
    ///
    /// 0,9 giây theo bản iOS. Trước đây để 0,4 giây và đã thấy hậu quả thật trên
    /// máy: 5 tấm trả về gần như giống hệt nhau.
    let minGapMs: Int64

    /// ...HOẶC phải khác dáng đủ nhiều. 0..1, càng cao càng khắt khe.
    ///
    /// ⚠️ Là **HOẶC**, không phải VÀ. Mẫu đổi dáng hẳn trong vòng nửa giây thì đó
    /// là hai tấm ảnh khác nhau thật, giữ cả hai là đúng.
    let minPoseDistance: Double

    private var entries: [ShotCandidate] = []

    init(capacity: Int = 12, minGapMs: Int64 = 900, minPoseDistance: Double = 0.12) {
        precondition(capacity > 0, "capacity phải lớn hơn 0")
        precondition(minGapMs >= 0, "minGapMs không được âm")
        self.capacity = capacity
        self.minGapMs = minGapMs
        self.minPoseDistance = minPoseDistance
    }

    var size: Int { entries.count }

    /// Toàn bộ khung đang giữ, tốt nhất đứng trước.
    func all() -> [ShotCandidate] {
        entries.sorted(by: { ShotCandidate.bestFirst($0, $1) })
    }

    /// [n] khung tốt nhất. Đây là thứ đem ra cho người dùng chọn.
    func top(_ n: Int) -> [ShotCandidate] {
        Array(all().prefix(n))
    }

    /// Đưa một khung vào xét.
    ///
    /// - Returns: `.accepted(evicted:)` kèm danh sách khung bị đá ra — người gọi
    ///   **phải xoá file** của những khung đó. Hoặc `.rejected` nếu khung này
    ///   không đáng giữ, khi đó đừng lưu file nào cả.
    func offer(_ candidate: ShotCandidate) -> OfferResult {
        // Những khung đang giữ bị coi là "trùng lặp" với candidate: vừa quá gần về
        // thời gian, VỪA gần giống về dáng. Chỉ cần một trong hai điều kiện khác
        // biệt là hai tấm đã đáng giữ cả.
        //
        // Phải lấy TẤT CẢ chứ không chỉ cái gần nhất: thay một cái rồi vẫn có thể
        // còn cái khác nằm trong khoảng cấm, làm hỏng luật cách nhau.
        let near = entries.filter {
            abs($0.timeMs - candidate.timeMs) < minGapMs &&
                Self.poseDistance($0.poseSignature, candidate.poseSignature) < minPoseDistance
        }

        // Đã có khung tốt hơn ở ngay quanh đó rồi thì thôi.
        if near.contains(where: { !Self.isBetter(candidate, $0) }) { return .rejected }

        let remaining = entries.filter { e in !near.contains { $0.id == e.id } }

        if remaining.count < capacity {
            entries = remaining
            entries.append(candidate)
            return .accepted(evicted: near)
        }

        // Hết chỗ: phải hạ được khung yếu nhất mới được vào.
        //
        // ⚠️ Lấy khung yếu nhất bằng cách SẮP XẾP RỒI LẤY PHẦN TỬ CUỐI, cố ý dài
        // dòng. Cách ngắn `min(by:)` trông đúng nhưng SAI: bộ so sánh này xếp giảm
        // dần, nên "phần tử nhỏ nhất theo nó" chính là khung ĐIỂM CAO NHẤT. Viết
        // như vậy thì app âm thầm vứt đi tấm đẹp nhất và giữ lại tấm tệ nhất.
        guard let worst = remaining.sorted(by: { ShotCandidate.bestFirst($0, $1) }).last else {
            return .rejected
        }
        if !Self.isBetter(candidate, worst) { return .rejected }

        entries = remaining.filter { $0.id != worst.id }
        entries.append(candidate)
        return .accepted(evicted: near + [worst])
    }

    /// Bỏ một khung ra khỏi bộ giữ. Dùng khi lưu file hỏng — giữ lại một mục trỏ
    /// tới file không tồn tại thì màn kết quả sẽ hiện ô ảnh trống.
    @discardableResult
    func remove(id: Int64) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        return entries.count != before
    }

    /// Bỏ hết. Trả lại danh sách để người gọi xoá file.
    func clear() -> [ShotCandidate] {
        let out = entries
        entries.removeAll()
        return out
    }

    /// Bỏ những khung KHÔNG nằm trong danh sách giữ lại. Dùng lúc người dùng đã
    /// chọn xong ảnh — phần còn lại là rác, xoá đi.
    func keepOnly(ids: Set<Int64>) -> [ShotCandidate] {
        let dropped = entries.filter { !ids.contains($0.id) }
        entries.removeAll { !ids.contains($0.id) }
        return dropped
    }

    private static func isBetter(_ a: ShotCandidate, _ b: ShotCandidate) -> Bool {
        ShotCandidate.bestFirst(a, b)
    }

    /// Khoảng cách dáng giữa hai khung, 0..1. 0 = dáng y hệt.
    ///
    /// Trung bình chênh lệch góc các khớp, chia cho 180 để về thang 0..1.
    /// Không so được (thiếu dữ liệu, hoặc số khớp khác nhau) thì trả **0** —
    /// tức "coi như giống nhau". Cố ý chọn phía an toàn: không biết mà lại cho
    /// qua thì sinh ra hai tấm trùng nhau, còn không biết mà chặn thì chỉ mất
    /// một ứng viên.
    private static func poseDistance(_ a: [Double], _ b: [Double]) -> Double {
        if a.isEmpty || b.isEmpty || a.count != b.count { return 0.0 }
        var sum = 0.0
        for i in a.indices {
            var d = abs(a[i] - b[i]).truncatingRemainder(dividingBy: 360.0)
            if d > 180.0 { d = 360.0 - d }
            sum += d
        }
        return min(max(sum / Double(a.count) / 180.0, 0.0), 1.0)
    }
}

/// Một khung hình đang được giữ.
///
/// Cố ý KHÔNG chứa ảnh. Ảnh nằm ngoài máy dưới dạng file, tra theo [id] — nếu
/// ôm ảnh trong bộ nhớ thì 12 tấm ảnh độ phân giải camera đã ngốn hàng trăm MB.
nonisolated struct ShotCandidate: Equatable {

    /// Định danh duy nhất, cũng là tên file ảnh.
    let id: Int64

    /// Thời điểm trong phiên quay, mili-giây.
    let timeMs: Int64

    /// Điểm giống ảnh mẫu, 0..100.
    ///
    /// `var` chứ không phải `let`: lúc chốt phiên `ShotSession` phải **chấm lại**
    /// toàn bộ khung kèm độ nét, tức là sửa điểm của khung đã giữ.
    var score: Double

    /// Có đo được đủ mục để tin điểm này không. Cũng bị chấm lại lúc chốt phiên.
    var trustworthy: Bool

    /// Điểm từng mục 0..1, chỉ gồm mục ĐO ĐƯỢC.
    ///
    /// Có để người dùng (và người chỉnh ngưỡng) biết **mất điểm ở đâu**. Một con số
    /// tổng "47" không nói được gì: 47 vì sai hướng, hay vì đứng lệch tâm, hay vì
    /// đứng quá xa — ba chuyện khác hẳn nhau và cách sửa cũng khác hẳn.
    var parts: [String: Double] = [:]

    /// Góc các khớp đã trải phẳng, dùng để đo hai khung có KHÁC DÁNG không.
    ///
    /// Cần vì luật cách nhau là "cách 0,9 giây **HOẶC** khác dáng đủ nhiều" — mẫu
    /// đổi dáng hẳn trong nửa giây thì đó là hai tấm khác nhau thật.
    var poseSignature: [Double] = []

    /// THỨ TỰ "TỐT HƠN" DUY NHẤT CỦA DỰ ÁN: đủ căn cứ trước, rồi tới điểm cao.
    ///
    /// Đặt ở đây, không đặt trong [BestShotBuffer], vì có tới ba nơi cần xếp
    /// hạng: lúc chen chỗ trong khi quay, lúc chấm lại kèm độ nét khi quay xong,
    /// và lúc màn kết quả bày ảnh ra. Ba nơi mà mỗi nơi tự viết một phép so là cách
    /// chắc chắn nhất để sinh ra tình huống *"khung bị loại trong lúc quay lại chính
    /// là khung đáng lẽ đứng đầu"*.
    static func bestFirst(_ a: ShotCandidate, _ b: ShotCandidate) -> Bool {
        if a.trustworthy != b.trustworthy { return a.trustworthy }
        return a.score > b.score
    }
}

nonisolated enum OfferResult {
    /// Không đáng giữ — đừng lưu file.
    case rejected

    /// Đã nhận. Người gọi phải lưu file của khung mới và **xoá file** của `evicted`.
    case accepted(evicted: [ShotCandidate])
}
