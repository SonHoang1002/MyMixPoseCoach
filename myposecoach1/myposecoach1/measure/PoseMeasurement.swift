import Foundation

/**
 * TẦNG ĐO ĐẠC — "MỘT HÀM DUY NHẤT" (Bước 3).
 *
 * Quy một khung hình đã nhận diện thành vài con số mô tả **máy đang đặt ở đâu so
 * với mẫu**. Ảnh mẫu và khung hình camera đi qua ĐÚNG hàm này, ĐÚNG tham số
 * `framing` — khác nhau đúng ở chỗ truyền vào cái gì.
 *
 * ⚠️ BẤT BIẾN SỐ 1 CỦA DỰ ÁN. Bản iOS vi phạm ở tầng trên: `GuidanceEngine`
 * (hướng dẫn realtime) và `BestShotSelector` (chấm ảnh sau khi quay) là HAI bộ
 * đo song song, mỗi bên tự tính theo cách riêng. Hậu quả không phải "sai một
 * chút" mà là **sai theo kiểu không gỡ được**: mỗi bên tự nó đúng, chỉ có phép
 * trừ giữa hai bên là vô nghĩa — app hướng dẫn một đằng, chấm điểm một nẻo, mà
 * không có gì báo lỗi. Bản Android gộp làm một ngay từ đây.
 *
 * ⚠️ BẤT BIẾN SỐ 2. Tham số [framing] LUÔN là lớp khung hình suy từ **ẢNH MẪU**,
 * kể cả khi đang đo khung hình camera. Không bao giờ để camera tự chọn mốc đo —
 * xem [FramingClass] để biết vì sao (đó là "nguyên nhân thứ 8").
 */
/**
 * CẶP ĐOẠN dùng để suy ĐỘ MÉO PHỐI CẢNH, xếp theo ưu tiên giảm dần.
 *
 * ⚠️ Số của hai cặp KHÁC NHAU **không so được với nhau** — chúng ở hai thang khác
 * hẳn. Đó là lý do [PoseMeasurement.perspectiveIndex] giữ cả bản đồ chứ không giữ
 * một số: tầng so sánh chọn cặp mà **cả ảnh mẫu lẫn khung hình cùng có**.
 */
nonisolated enum PerspectiveSource {
    /**
     * Thân so với CẢ CHÂN (hông→cổ chân). Cặp mạnh nhất.
     *
     * Đo trên 13 ảnh có đáp án (1m / 2,5m / 4m): **tín hiệu trên nhiễu 4,67**,
     * giảm đơn điệu theo khoảng cách, và tách hoàn toàn 1m khỏi 4m (8/8 đúng).
     */
    case TORSO_ANKLE

    /**
     * Thân so với ĐÙI (hông→gối). Dùng khi khung hình cắt mất cổ chân.
     *
     * Yếu hơn — tín hiệu trên nhiễu **2,97** — vì đoạn ngắn hơn nên phần méo cũng
     * nhỏ hơn. Vẫn giữ vì nếu không có nó thì chỉ cần người cầm máy nhích lại gần
     * một chút, mất cổ chân là mục này tắt hẳn.
     */
    case TORSO_KNEE
}

/**
 * ĐƯỜNG ĐO đã dùng cho mục NGHIÊNG NGANG.
 *
 * Hai đường cùng đơn vị và cùng gốc 0 (người đứng thẳng, máy ngang), nên gần nhau
 * hơn hẳn hai đường của mục ngửa/chúc. Vẫn tách nhãn để giữ luật "chỉ so khi cùng
 * đường" — đã có FOOTGUNS 39 vì trộn nguồn một lần rồi.
 */
nonisolated enum RollSource {
    /** Trục thân (giữa vai → giữa hông). Dài, và **không đổi khi mẫu xoay người**. */
    case SPINE

    /** Đường nối hai vai. Dùng khi không thấy hông — ảnh chân dung, bán thân. */
    case SHOULDERS
}

/**
 * ĐƯỜNG ĐO đã dùng cho mục NGỬA/CHÚC.
 *
 * Hai đường đo cùng một hiện tượng (thân người trông như hình thang) nhưng
 * **không so được với nhau**: chúng khác thang đo và khác độ nhiễu tới 6,5 lần
 * (đo trên 19 ảnh có khoảng cách thật: chân 0,016 — mặt 0,104).
 *
 * ⚠️ Trước khi có nhãn này, ảnh mẫu đo bằng CHÂN bị đem trừ thẳng cho khung
 * camera đo bằng MẶT. Phép trừ vẫn ra số trông hợp lệ nên không ai thấy sai.
 */
nonisolated enum PitchSource {
    /**
     * GÓC MÁY THẬT so với phương ngang — đơn vị ĐỘ. Đường chính, xếp đầu.
     *
     * Âm = chúc xuống, dương = hất lên.
     *
     * ⚠️ HAI BÊN LẤY TỪ HAI NGUỒN KHÁC NHAU, và đó là chủ ý (14/09/2026):
     *
     * | | Lấy từ đâu |
     * |---|---|
     * | Ảnh mẫu | trục thân 3D suy từ ảnh, hoặc NHÃN GÓC trong tên file |
     * | Camera | **cảm biến trọng lực** — chính xác dưới 1° |
     *
     * Trước đây phía camera cũng suy từ trục thân. Video test 13/09/2026 cho thấy
     * phép suy đó **lệch có hệ thống** trên ảnh camera thật: cầm máy thẳng chụp
     * người đứng mà đọc ra −14° tới −23°, trong khi ảnh mẫu studio chụp thẳng
     * đọc +4°. Hai mục máy cao/thấp và ngửa/chúc vì thế đỏ suốt với đúng kiểu
     * ảnh cơ bản nhất. Còn ảnh chúc từ trên cao thì số đo camera co lại quanh
     * −31° tới −45° dù người chụp đã chúc rất mạnh — nên "chúc mãi không dừng".
     *
     * Cảm biến không có hai bệnh đó. Tài liệu gốc cũng thiết kế đúng như vậy:
     * *"live có IMU, template là JPEG trần phải SUY từ hình học ảnh"*.
     */
    case GOC_MAY

    /** Chân so với thân. Tỉ lệ không đơn vị — đường phụ, gần như không còn dùng tới. */
    case LEGS
}

nonisolated struct PoseMeasurement {
    /** Lớp khung hình đã dùng để đo. Luôn là lớp của ảnh mẫu. */
    var framing: FramingClass

    /**
     * MỤC 2 — XA/GẦN. Chiều cao của mốc đo, tính theo tỉ lệ chiều cao khung hình.
     * Lớn hơn = mẫu chiếm nhiều khung hơn = máy đang đứng GẦN hơn.
     * `null` khi mốc của lớp này không nhìn thấy.
     */
    var scale: Double?

    /**
     * MỤC 5 — LỆCH TRÁI/PHẢI. Vị trí ngang của mốc, 0 = mép trái, 1 = mép phải.
     */
    var centerX: Double?

    /**
     * MỤC 3 — MÁY CAO/THẤP. Vị trí dọc của mốc góc nhìn, 0 = mép trên, 1 = mép dưới.
     *
     * Nâng máy lên cao thì mẫu tụt xuống thấp trong khung — nên chính con số này
     * là dấu vết của độ cao đặt máy.
     */
    /**
     * ĐỘ NGHIÊNG CỦA TRỤC ỐNG KÍNH so với phương thẳng đứng — **mục 4**, đơn vị ĐỘ.
     *
     * Âm = máy chúc xuống. Dương = máy hất lên. 0 = trục ống kính nằm ngang.
     *
     * Suy từ trục thân trong khung xương 3D. Kiểm 12/09/2026: tương quan −0,700
     * với công thức `R` mà tài liệu gốc dùng cho mục này — tức cùng đo một đại
     * lượng. Nhưng ăn đứt `R` ở dáng ngồi: ảnh ngồi ghế chụp ngửa cho `R = 1,05`
     * (lẫn với ảnh đứng thẳng) trong khi phép này cho **+39,7°**, tách rõ. Đúng
     * chỗ tài liệu tự nhận là *"mắt xích yếu nhất"*.
     *
     * `null` khi không thấy hông — chân dung lùi về tín hiệu khuôn mặt trong
     * [pitchCue].
     */
    var tiltDeg: Double?

    /**
     * GÓC NHÌN TỪ MÁY TỚI MỐC TRÊN CƠ THỂ — **mục 3**, đơn vị ĐỘ.
     *
     *     elevation = tiltDeg + (0,5 − y_mốc) × vFOV
     *
     * Âm = tia chúc xuống, máy CAO hơn mốc. Dương = máy THẤP hơn.
     *
     * ⚠️ Đây là đại lượng KHÁC [tiltDeg], không thừa. Đo trên ảnh mẫu thật:
     * `NGOI-ghe-giua-dong` và `nam-nen-trang-tay-tui` có y_hông gần bằng nhau
     * (0,515 so với 0,556) nhưng độ nghiêng lệch **36°**. Hai phương trình độc
     * lập, cùng nhau xác định đủ cả độ cao máy lẫn độ chúc.
     */
    var elevationDeg: Double?

    /**
     * MỤC 1 — HƯỚNG MẪU đo bằng THÂN. Góc xoay quanh trục đứng, ĐỘ.
     * 0 = quay thẳng vào máy, ±180 = quay lưng.
     */
    var yawDeg: Double?

    /**
     * MỤC 1 — HƯỚNG MẪU đo bằng MẶT. `null` khi không thấy mặt.
     *
     * Chính xác hơn góc thân với ảnh chân dung (~3-5° so với ~8-10°), nên
     * `FramingClass.yawSource` chỉ định CHEST/HEAD ưu tiên nguồn này.
     *
     * ⚠️ Chỉ được dùng khi **CẢ ảnh mẫu LẪN khung hình** đều có — trộn hai nguồn
     * giữa hai bên là phá bất biến "cùng một hàm": số của bên này không so được
     * với số của bên kia, mà phép trừ vẫn ra kết quả trông hợp lệ.
     */
    var faceYawDeg: Double?

    /** HẬU KỲ — mắt có mở không, 0..1. Lấy mắt nhắm hơn trong hai mắt. */
    var eyesOpen: Double?

    /**
     * Chiều cao THẬT của đúng cái mốc mà [scale] đo trên ảnh, tính bằng MÉT.
     *
     * Ghép với [scale] và mức zoom thì ra khoảng cách máy-tới-mẫu — thứ duy nhất
     * cho phép nói "lùi lại 2 bước" thay vì "lùi lại một chút".
     * Xem `guidance.DistanceEstimator`.
     *
     * ⚠️ `null` với ảnh CHÂN DUNG: ở đó mốc đo là khung mặt, mà `worldLandmarks`
     * không cho chiều cao khuôn mặt một cách đáng tin. Không đoán bừa — câu nhắc
     * sẽ tự lùi về "một chút", kém chính xác nhưng không sai.
     */
    var anchorHeightMeters: Double?

    /**
     * MỤC 8 — NGHIÊNG NGANG. Góc trục thân so với phương thẳng đứng CỦA ẢNH, ĐỘ.
     *
     * Dương = thân nghiêng sang phải trong khung. 0 = dựng đứng.
     *
     * ⚠️ ĐO TỪ ẢNH, KHÔNG TỪ CẢM BIẾN — dù cảm biến trọng lực đo chính xác hơn
     * nhiều. Lý do: **ảnh mẫu là ảnh tĩnh, không có cảm biến**. Lấy cảm biến cho
     * khung camera rồi đem trừ cho số suy từ ảnh mẫu là phá bất biến "cùng một hàm",
     * và nó vỡ ở một ca rất thật: ảnh mẫu nghiêng vì MẪU NGẢ NGƯỜI, khung camera
     * cũng có mẫu ngả y hệt → đáng lẽ ĐẠT, nhưng cảm biến báo máy đang thẳng nên
     * app bắt xoay máy thêm, chủ thể thành nghiêng gấp đôi.
     *
     * Cảm biến vẫn được dùng — nhưng để **chọn nhắc ai** (máy hay mẫu), xem
     * `GuidanceEngine`. Nó là thông tin độc lập với ảnh nên gỡ được đúng chỗ mà
     * ảnh không tự gỡ được.
     */
    var rollDeg: [RollSource: Double]

    /**
     * MỤC 4 — MÁY NGỬA/CHÚC. **Chỉ số không đơn vị**, không phải số đo bằng độ.
     *
     * Dương = máy đang **hất lên** (chụp từ dưới), âm = máy đang **chúc xuống**
     * (chụp từ trên), 0 = ống kính ngang.
     *
     * ⚠️ CỐ Ý KHÔNG quy ra ĐỘ. Muốn ra độ thì phải biết tiêu cự và khoảng cách —
     * ảnh mẫu là ảnh tĩnh, không có thứ nào cả. Nhưng sản phẩm **không cần góc
     * tuyệt đối**: nó chỉ cần biết khung camera có méo GIỐNG ảnh mẫu không. Đo độ
     * méo ở cả hai bên rồi trừ nhau là đủ — đúng nguyên tắc "cùng một hàm".
     */
    var pitchCue: [PitchSource: Double]

    /**
     * MỤC 7 — ĐỘ MẠNH PHỐI CẢNH. **Chỉ số không đơn vị, MIỄN NHIỄM VỚI ZOOM.**
     *
     * Đây là đại lượng tách được hai thứ mà [scale] gộp làm một: *đứng gần* và
     * *zoom vào*. Xem [Measurer.measurePerspective] để biết công thức và vì sao nó
     * không phụ thuộc tiêu cự.
     *
     * Càng LỚN = máy càng gần chủ thể. Tiến về 0 khi đứng xa (ảnh "phẳng", bị nén).
     */
    var perspectiveIndex: [PerspectiveSource: Double]

    /**
     * MỤC 6 — DÁNG. Góc các khớp, ĐỘ, chỉ gồm nhóm khớp thuộc lớp khung hình này.
     *
     * Đo trên toạ độ 2 chiều CỦA ẢNH, cố ý: ta đang khớp "trông giống bức ảnh mẫu",
     * chứ không phải khớp tư thế trong không gian thật.
     */
    var poseAngles: [PoseGroup: [Double]]

    /**
     * Toạ độ dọc của mốc góc nhìn trên khung (mục 3). Một SỐ HẠNG, không phải
     * phép đo — giữ lại để phía camera ghép với độ nghiêng từ cảm biến, và để
     * nhãn góc trong tên file ảnh mẫu tính được mục 3 cả với ảnh chân dung.
     */
    var elevationAnchorY: Double? = nil

    /**
     * Chiều cao khung mặt trên khung hình — mốc cỡ mẫu DỰ PHÒNG.
     *
     * Dùng khi mốc chính của lớp khung hình (đầu→cổ chân) bị bỏ vì chân chĩa vào
     * ống kính — đúng ca ảnh chụp từ trên cao. Video test 13/09/2026: template
     * chúc từ trên xuống mất hẳn mục khung hình, và ảnh chụp ra **cụt mất đầu**.
     */
    var faceScale: Double? = nil

    /** Số mục đo được. Mục không đo được sẽ bị bỏ ra khi chấm điểm, KHÔNG bị trừ điểm. */
    var measuredCount: Int {
        let n = [scale, centerX, elevationDeg, yawDeg].compactMap { $0 }.count
        return n +
            (pitchCue.isEmpty ? 1 : 0) +
            (rollDeg.isEmpty ? 1 : 0) +
            (poseAngles.isEmpty ? 1 : 0)
    }
}

/**
 * Bỏ ba đại lượng góc máy SUY TỪ ẢNH: độ nghiêng, góc nhìn, và nguồn [PitchSource.GOC_MAY].
 *
 * Suy từ trục thân nên lẫn cả dáng đứng (ngả người, tay đút túi) lẫn loại ống kính
 * (ảnh studio ống dài chụp thẳng đọc ra +4°, điện thoại chụp thẳng đọc −16°). Góc máy
 * thật chỉ lấy từ NHÃN (ảnh mẫu) và CẢM BIẾN (camera). Xem FOOTGUNS 91.
 */
nonisolated extension PoseMeasurement {
    func boGocMayTuAnh() -> PoseMeasurement {
        var m = self
        m.tiltDeg = nil
        m.elevationDeg = nil
        var pitch = pitchCue
        pitch.removeValue(forKey: .GOC_MAY)
        m.pitchCue = pitch
        return m
    }
}

nonisolated enum Measurer {

    /**
     * GÓC MỞ DỌC GIẢ ĐỊNH CHO ẢNH MẪU, độ.
     *
     * Ảnh mẫu là JPEG trần: không tiêu cự, không EXIF (đo 12/09/2026: 0/13 ảnh
     * mẫu cài sẵn còn EXIF máy ảnh). Phải đoán.
     *
     * 65° là góc dọc của ống kính chính điện thoại phổ thông ở khung 4:3
     * (tương đương ~26mm). Ảnh mẫu tải từ mạng gần như luôn chụp bằng điện thoại.
     *
     * ⚠️ Đoán sai bao nhiêu thì hại bấy nhiêu — nhưng có chặn trên: số hạng
     * `(0,5 − y) × vFOV` tỉ lệ với khoảng cách từ mốc tới GIỮA khung. Mốc nằm
     * giữa khung thì đoán sai bao nhiêu cũng không ảnh hưởng.
     */
    static let VFOV_ANH_MAU = 65.0

    /** Trục thân ngắn hơn bấy nhiêu lần bề ngang vai trên ảnh thì coi là co rút. */
    static let THAN_TOI_THIEU_THEO_VAI = 1.0

    /**
     * Mốc đo lệch khỏi tâm khung quá mức này thì mục 3 không tin được nữa.
     *
     * 0,15 chọn từ bảng sai số trong `measureElevationDeg`: nhân với sai số vFOV
     * ±20° ra 3°, tức nửa ngưỡng đạt của lớp toàn thân. Quá mức đó thì phần đoán
     * lấn át phần đo.
     */
    static let MOC_LECH_TAM_TOI_DA = 0.15

    /**
     * Góc chĩa vào ống kính tối đa mà một đoạn cơ thể còn dùng để đo được, ĐỘ.
     *
     * Đo từ 19 ảnh có khoảng cách bằng thước: đoạn hông→gót của người ĐỨNG bình
     * thường nằm trong 9,1°-25,8° (trung bình 18,8°, lệch chuẩn 5,1°). Mẫu đá chân
     * về phía máy thì vượt 60°. 40° nằm giữa, cách mỗi bên một quãng rộng.
     */
    static let MAX_OUT_OF_PLANE_DEG = 40.0

    /**
     * Đo một khung hình.
     *
     * @param frame khung hình đã nhận diện (ảnh mẫu hoặc khung camera — cùng đường)
     * @param framing lớp khung hình **của ảnh mẫu**, áp nguyên xi cho mọi khung
     * @param minVisibility ngưỡng tin cậy tối thiểu của từng điểm khớp
     */
    static func measure(
        _ frame: PoseFrame,
        framing: FramingClass,
        minVisibility: Float,
        /** Số liệu khuôn mặt, `null` khi chưa chạy hoặc không thấy mặt. */
        face: FaceInfo? = nil,
        /**
         * Góc mở DỌC của ống kính, độ. Cần cho mục 3.
         *
         * Camera thật đọc được từ phần cứng. Ảnh mẫu thì không có — dùng
         * [VFOV_ANH_MAU]. Sai số do đoán có chặn trên: mốc càng gần giữa khung
         * thì số hạng `(0,5 − y) × vFOV` càng nhỏ, ở y = 0,2 thì đoán lệch 10°
         * chỉ gây sai 3°.
         */
        vFovDeg: Double = Measurer.VFOV_ANH_MAU
    ) -> PoseMeasurement {
        if frame.isEmpty {
            return PoseMeasurement(
                framing: framing,
                scale: nil,
                centerX: nil,
                tiltDeg: nil,
                elevationDeg: nil,
                yawDeg: nil,
                faceYawDeg: nil,
                eyesOpen: nil,
                anchorHeightMeters: nil,
                rollDeg: [:],
                pitchCue: [:],
                perspectiveIndex: [:],
                poseAngles: [:]
            )
        }
        return PoseMeasurement(
            framing: framing,
            scale: measureScale(frame, framing.scaleAnchor, minVisibility),
            centerX: measureCenterX(frame, framing.centerAnchor, minVisibility),
            tiltDeg: measureTiltDeg(frame, minVisibility),
            elevationDeg: measureElevationDeg(frame, framing, minVisibility, vFovDeg),
            yawDeg: frame.bodyYawDeg(minVisibility: minVisibility),
            faceYawDeg: face?.yawDeg,
            eyesOpen: face?.eyesOpen,
            anchorHeightMeters: measureAnchorHeight(frame, framing, minVisibility),
            rollDeg: measureRoll(frame, minVisibility),
            pitchCue: measurePitchCue(frame, minVisibility),
            perspectiveIndex: measurePerspective(frame, minVisibility),
            poseAngles: measurePose(frame, framing.poseGroups, minVisibility),
            elevationAnchorY: anchorY(frame, framing.elevationAnchor, minVisibility),
            faceScale: faceBox(frame, minVisibility).flatMap { $0.height > 1e-4 ? $0.height : nil }
        )
    }

    // =================================================================
    // MỤC 2 — XA/GẦN
    // =================================================================

    /**
     * Chiều cao mốc đo, theo tỉ lệ chiều cao khung hình.
     *
     * Mốc thay đổi theo lớp khung hình — đó là toàn bộ lý do [FramingClass] tồn tại.
     * Ảnh chân dung đo bằng khung mặt, ảnh toàn thân đo bằng đầu→cổ chân. Trộn hai
     * mốc với nhau là hỏng.
     */
    private static func measureScale(
        _ f: PoseFrame,
        _ anchor: ScaleAnchor,
        _ v: Float
    ) -> Double? {
        if anchor == .faceHeight {
            guard let face = faceBox(f, v) else { return nil }
            let h = face.height
            return h > 1e-4 ? h : nil
        }

        guard let head = headPoint(f, v) else { return nil }

        // ⚠️ Mốc đo chạm tới CHÂN thì phải kiểm chân có chĩa vào ống kính không.
        // Mẫu đá chân về phía máy làm cổ chân tụt xuống trong khung → app tưởng
        // mẫu cao lên → tưởng máy lại gần. Bỏ ra còn hơn đo sai (quy tắc số 4).
        let legOk: Bool
        switch anchor {
        case .headToAnkle:
            legOk = segmentUsable(f, v, Lm.leftHip, Lm.rightHip, Lm.leftAnkle, Lm.rightAnkle)
        case .headToKnee:
            legOk = segmentUsable(f, v, Lm.leftHip, Lm.rightHip, Lm.leftKnee, Lm.rightKnee)
        default:
            legOk = true
        }
        if !legOk { return nil }

        let bottomY: Double?
        switch anchor {
        case .headToAnkle:
            bottomY = lowestY(f, v, Lm.leftAnkle, Lm.rightAnkle)
        case .headToKnee:
            bottomY = lowestY(f, v, Lm.leftKnee, Lm.rightKnee)
        case .headToHip:
            bottomY = f.root(minVisibility: v)?.y
        case .faceHeight:
            bottomY = nil // đã xử lý ở trên
        }
        guard let bottomY = bottomY else { return nil }

        // y hướng XUỐNG nên đáy phải lớn hơn đỉnh. Ngược lại là dữ liệu rác.
        let h = bottomY - head.y
        return h > 1e-4 ? h : nil
    }

    /**
     * Chiều cao THẬT của mốc đo, mét — phải khớp ĐÚNG mốc mà [measureScale] dùng.
     *
     * ⚠️ Lấy nhầm mốc là hỏng theo kiểu khó thấy: ảnh đo đầu→gối mà chiều cao thật
     * lại tính đầu→cổ chân thì khoảng cách ra sai ~35%, đủ để nói nhầm "2 bước"
     * thành "3 bước" mà không có gì báo.
     */
    private static func measureAnchorHeight(
        _ f: PoseFrame,
        _ framing: FramingClass,
        _ v: Float
    ) -> Double? {
        guard let head = f.world(Lm.nose, minVisibility: v) else { return nil }
        let bottom: (first: Double, second: Double, third: Double)?
        switch framing.scaleAnchor {
        case .headToAnkle:
            bottom = midWorldPoint(f, Lm.leftAnkle, Lm.rightAnkle, v)
        case .headToKnee:
            bottom = midWorldPoint(f, Lm.leftKnee, Lm.rightKnee, v)
        case .headToHip:
            bottom = midWorldPoint(f, Lm.leftHip, Lm.rightHip, v)
        // Chân dung: mốc là khung MẶT, mà worldLandmarks không cho chiều cao
        // khuôn mặt đáng tin. Trả null thay vì đoán.
        case .faceHeight:
            bottom = nil
        }
        guard let bottom = bottom else { return nil }
        let d = dist3((first: head.x, second: head.y, third: head.z), bottom)
        // Người cao dưới 0,5m hoặc trên 2,5m là dữ liệu rác, không phải người.
        return d >= 0.5 && d <= 2.5 ? d : nil
    }

    private static func midWorldPoint(
        _ f: PoseFrame,
        _ a: Int,
        _ b: Int,
        _ v: Float
    ) -> (first: Double, second: Double, third: Double)? {
        guard let A = f.world(a, minVisibility: v) else { return nil }
        guard let B = f.world(b, minVisibility: v) else { return nil }
        return (first: (A.x + B.x) / 2, second: (A.y + B.y) / 2, third: (A.z + B.z) / 2)
    }

    // =================================================================
    // MỤC 5 — LỆCH TRÁI/PHẢI
    // =================================================================

    private static func measureCenterX(
        _ f: PoseFrame,
        _ anchor: CenterAnchor,
        _ v: Float
    ) -> Double? {
        switch anchor {
        case .torsoCenter:
            let neck = f.neck(minVisibility: v)
            let root = f.root(minVisibility: v)
            if let neck = neck, let root = root { return (neck.x + root.x) / 2.0 }
            return neck?.x
        case .shoulderCenter:
            return f.neck(minVisibility: v)?.x
        case .faceCenter:
            guard let box = faceBox(f, v) else { return nil }
            return (box.left + box.right) / 2.0
        }
    }

    // =================================================================
    // MỤC 3 — MÁY CAO/THẤP
    // =================================================================

    /**
     * GÓC NÂNG CỦA MÁY so với chủ thể, tính bằng **ĐỘ**.
     *
     * Âm = máy đang ở trên, chúc xuống. Dương = máy ở dưới, ngửa lên. 0 = ngang tầm.
     *
     * ## Vì sao không đo bằng vị trí trong khung nữa
     *
     * Bản cũ trả về `y` của một mốc trên khung hình — tức là **bố cục**, không
     * phải độ cao máy. Hai cách cầm máy hoàn toàn khác nhau cho ra cùng một con
     * số: máy ngang ngực để thẳng, và máy giơ trên đầu chúc xuống, đều có thể
     * đặt hông mẫu ở `y = 0,62`.
     *
     * Đo ngày 12/09/2026 cho thấy nó còn tệ hơn thế — **nhạy với khoảng cách hơn
     * là với độ cao máy**:
     *
     * | | chỉ số cũ `y` | góc (hàm này) |
     * |---|---|---|
     * | Đổi góc máy ~55° | đổi **0,041** | đổi **55°** |
     * | Giữ nguyên góc, chỉ đi lại gần/xa | đổi **0,058** | đổi **6,3°** |
     * | Ngưỡng đạt khi đó | ~0,035 | |
     *
     * Tín hiệu 0,041 mà nhiễu 0,058 — tỉ lệ dưới 1. Đó là lời giải thích toán học
     * cho vòng lặp *"làm theo hướng dẫn mãi mà không bao giờ đạt"*: người dùng
     * chỉnh đúng thứ được bảo, nhưng chỉ cần nhích chân là con số nhảy nhiều hơn.
     *
     * ## Cách đo
     *
     * Lấy trục thân trong **khung xương 3D** (`worldLandmarks`) rồi tính góc giữa
     * nó và mặt phẳng ảnh. Miễn nhiễm với zoom, với khoảng cách, và với việc ảnh
     * mẫu đã bị **cắt cúp** — vì nó chỉ đọc quan hệ bên trong cơ thể.
     *
     * Kiểm trên 5 ảnh chụp cùng góc máy nhưng khác hẳn khoảng cách và zoom:
     * −19,4 / −17,6 / −16,4 / −20,4 / −14,1 độ. Và trên hai ảnh đối cực: ngồi ghế
     * chụp ngửa từ dưới **+39,7°**, chân dung chúc thẳng từ trên đầu **−52,8°**.
     *
     * ⚠️ **CHỈ DÙNG `worldLandmarks` CHO HƯỚNG, KHÔNG CHO KHOẢNG CÁCH** — xem
     * FOOTGUNS 64. Mô hình trả về hướng thật, nhưng độ sâu thì nó bịa ra một hằng
     * số giải phẫu đã học thuộc.
     *
     * ## Vì sao trả về `null` với ảnh chân dung
     *
     * Cần **thấy hông** để có trục thân. Không thấy hông thì đường duy nhất còn
     * lại là trục cổ→đầu, mà đã đo và loại: tương quan với trục thân chỉ **0,287**,
     * độ lệch chuẩn **23,9°**, có ca ngược hẳn dấu. Đầu gật tự do nên nó bám tư
     * thế đầu chứ không bám vị trí máy.
     *
     * Ảnh chân dung thì mục **ngửa/chúc** (đo từ khuôn mặt) gánh phần thông tin
     * góc — và với ảnh chân dung, góc giữa MẶT và ống kính mới đúng là thứ nhìn
     * thấy được. Không đo được thì bỏ ra, không đoán (quy tắc số 4).
     */
    private static func measureTiltDeg(_ f: PoseFrame, _ v: Float) -> Double? {
        // Đòi cả 2D lẫn 3D: `at()` lọc điểm nằm NGOÀI khung mà MediaPipe vẫn tự
        // tin bịa ra. Thiếu bước này thì hông ở ngoài khung vẫn cho ra một góc.
        if f.at(Lm.leftHip, minVisibility: v) == nil && f.at(Lm.rightHip, minVisibility: v) == nil {
            return nil
        }
        if f.at(Lm.leftShoulder, minVisibility: v) == nil && f.at(Lm.rightShoulder, minVisibility: v) == nil {
            return nil
        }

        let lh = f.world(Lm.leftHip, minVisibility: v)
        let rh = f.world(Lm.rightHip, minVisibility: v)
        let ls = f.world(Lm.leftShoulder, minVisibility: v)
        let rs = f.world(Lm.rightShoulder, minVisibility: v)
        guard let hip = midP3(lh, rh) else { return nil }
        guard let sh = midP3(ls, rs) else { return nil }

        let dy = sh.y - hip.y
        let dz = sh.z - hip.z
        // Trục thân quá ngắn trên ảnh thì góc nhiễu loạn — thà bỏ.
        if hypot(dy, dz) < 1e-3 { return nil }
        // y của MediaPipe hướng XUỐNG, nên -dy là "lên trên".
        return hieuChinhGocAnh(atan2(dz, -dy) * 180.0 / Double.pi)
    }

    /**
     * ĐỔI GÓC SUY TỪ ẢNH RA GÓC MÁY THẬT (15/09/2026).
     *
     * Số thô từ trục thân 3D **không phải** góc máy. Đo trên video
     * `test-media/9-selfie-goc/nguoi-khac-chup-goc.mp4` (78 cặp, mỗi khung có
     * cả số cảm biến lẫn số suy từ ảnh):
     *
     * | Số suy từ ảnh | Cảm biến thật |
     * |---|---|
     * | −50° | −49° |
     * | −20° | −14° |
     * | −8° | +5° |
     *
     * Chúc gắt thì hai số khớp, nhưng càng về ngang và ngửa thì ảnh càng **đọc
     * thấp hơn thật** — cầm máy thẳng mà ảnh ra −16°, ngửa +13° mà ảnh ra −1°.
     * Đây chính là lỗi "cầm thẳng mà bảo hạ máy": ảnh mẫu đọc theo ảnh, camera
     * đọc theo cảm biến, hai thang lệch nhau 10-18°.
     *
     * Nội suy gãy khúc qua ba mốc trên. Ngoài khoảng đã đo thì giữ độ dốc 1 — không
     * ngoại suy độ dốc của đoạn giữa ra chỗ chưa có số liệu.
     *
     * Sai số trung bình (kiểm bỏ-một-ra): chưa sửa **9,3°**, sau khi sửa **5,6°**.
     * ⚠️ Mới đo trên một người, một máy. Ngửa quá +15° chưa có số liệu.
     */
    internal static func hieuChinhGocAnh(_ tho: Double) -> Double {
        let x = MOC_GOC_ANH
        let y = MOC_GOC_THAT
        if tho <= x[0] { return y[0] + (tho - x[0]) }
        if tho >= x[x.count - 1] { return y[y.count - 1] + (tho - x[x.count - 1]) }
        let i = x.firstIndex(where: { $0 > tho })!
        let t = (tho - x[i - 1]) / (x[i] - x[i - 1])
        return y[i - 1] + t * (y[i] - y[i - 1])
    }

    private static let MOC_GOC_ANH = [-50.0, -20.0, -8.0]
    private static let MOC_GOC_THAT = [-49.0, -14.0, 5.0]

    /**
     * Mục 3 — góc nhìn từ máy tới mốc. Xem [PoseMeasurement.elevationDeg].
     *
     * Cần [measureTiltDeg] chạy được, tức là **phải thấy hông**. Ảnh chân dung
     * không có trục thân nên mục này bị bỏ (quy tắc số 4). Đã thử lấy trục
     * cổ→đầu thay thế và loại: tương quan 0,287, độ lệch chuẩn 23,9° — đầu gật
     * tự do nên nó bám tư thế đầu chứ không bám máy (FOOTGUNS 66).
     */
    private static func measureElevationDeg(
        _ f: PoseFrame,
        _ framing: FramingClass,
        _ v: Float,
        _ vFovDeg: Double
    ) -> Double? {
        guard let tilt = measureTiltDeg(f, v) else { return nil }
        guard let y = anchorY(f, framing.elevationAnchor, v) else { return nil }
        return gocNhin(tilt, anchorY: y, vFovDeg: vFovDeg)
    }

    /**
     * Góc nhìn từ máy tới mốc, dùng chung cho ảnh mẫu và camera.
     *
     * Tách riêng vì phía camera không lấy độ nghiêng từ ảnh mà từ CẢM BIẾN, còn
     * ảnh mẫu có thể lấy từ NHÃN GÓC trong tên file. Cả hai vẫn phải đi qua đúng
     * một công thức và đúng một chốt chặn mốc-xa-tâm.
     */
    static func gocNhin(_ tiltDeg: Double?, anchorY: Double?, vFovDeg: Double) -> Double? {
        guard let tiltDeg = tiltDeg, let anchorY = anchorY else { return nil }
        let y = anchorY
        let tilt = tiltDeg

        // ⚠️ MỐC NẰM XA TÂM KHUNG THÌ BỎ MỤC NÀY — phép đoán vFOV không đỡ nổi.
        //
        // Số hạng `(0,5 − y) × vFOV` tỉ lệ thẳng với khoảng cách từ mốc tới giữa
        // khung. Ảnh mẫu không có thông số ống kính (0/13 ảnh mẫu còn EXIF) nên
        // vFOV là số ĐOÁN, sai số thực tế cỡ ±20°. Tính ra sai số của mục này:
        //
        // | |0,5 − y| | sai nếu vFOV lệch 20° |
        // |---|---|
        // | 0,056 (`nam-nen-trang-tay-tui`) | 1,1° |
        // | 0,143 (`quay-lung-cong-vien`)   | 2,9° |
        // | 0,224 (`kinh-ram-tai-nghe`)     | **4,5°** |
        // | 0,263 (`NGOI-goc-cay`)          | **5,3°** |
        //
        // Ngưỡng đạt của mục này là 6° (3-4° với chân dung). Hai dòng cuối gần
        // bằng cả ngưỡng — tức con số đưa ra là đoán chứ không phải đo. Thà bỏ
        // mục đó và chia lại trọng số (quy tắc số 4) còn hơn nhắc người dùng đi
        // theo một con số bịa.
        if abs(0.5 - y) > MOC_LECH_TAM_TOI_DA { return nil }

        return tilt + (0.5 - y) * vFovDeg
    }

    /** Toạ độ dọc của mốc trên khung. Một số hạng của mục 3, không phải phép đo. */
    private static func anchorY(_ f: PoseFrame, _ anchor: ElevationAnchor, _ v: Float) -> Double? {
        switch anchor {
        case .midHip:
            return f.root(minVisibility: v)?.y
        case .midTorso:
            let neck = f.neck(minVisibility: v)
            let root = f.root(minVisibility: v)
            if let neck = neck, let root = root { return (neck.y + root.y) / 2.0 }
            return nil
        case .eyeLine:
            let le = f.at(Lm.leftEye, minVisibility: v)
            let re = f.at(Lm.rightEye, minVisibility: v)
            if let le = le, let re = re { return (le.y + re.y) / 2.0 }
            return le?.y ?? re?.y ?? f.at(Lm.nose, minVisibility: v)?.y
        }
    }

    private static func midP3(_ a: P3?, _ b: P3?) -> P3? {
        if let a = a, let b = b {
            return P3(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: (a.z + b.z) / 2)
        }
        return a ?? b
    }

    // =================================================================
    // MỤC 4 — MÁY NGỬA/CHÚC, suy từ ĐỘ MÉO PHỐI CẢNH
    // =================================================================

    /**
     * Độ méo phối cảnh của khung hình. Dương = hất lên, âm = chúc xuống.
     *
     * **Nguyên lý.** Bộ phận nào gần ống kính hơn thì trông to hơn. Chúc máy xuống
     * thì đầu và vai gần hơn → phần trên trông to ra, chân xa hơn → trông ngắn lại,
     * cả người trông lùn đi. Hất máy lên thì ngược lại: to nhất từ bàn chân, nhỏ
     * dần lên đỉnh đầu, cả người trông dài ra.
     *
     * **Cách đo.** MediaPipe cho hai bộ toạ độ cùng lúc:
     *  - toạ độ TRÊN ẢNH — đã bị phối cảnh làm méo
     *  - toạ độ THẬT trong không gian (`worldLandmarks`) — không méo
     *
     * Chia hai cái cho nhau thì phần "thật" triệt tiêu, chỉ còn lại đúng độ méo:
     * ```
     *     chỉ số = ln( (chân/thân trên ảnh) / (chân/thân ngoài đời) )
     * ```
     * Lớn hơn 0 = chân trông dài hơn thực tế = **hất lên**.
     *
     * **Vì sao phải chia cho tỉ lệ thật thay vì dùng thẳng tỉ lệ trên ảnh:** mẫu
     * trong ảnh mẫu và mẫu đứng trước camera là **hai người khác nhau**, chân dài
     * ngắn khác nhau. Chia cho tỉ lệ thật của chính người đó thì khác biệt cơ thể
     * tự triệt tiêu, chỉ còn lại phần do góc máy.
     *
     * ⚠️ CHƯA KIỂM CHỨNG TRÊN MÁY THẬT. Phép này dựa trên giả định `worldLandmarks`
     * **không mang theo phối cảnh** — nó là kết quả model ước lượng, không phải đo
     * đạc. Nếu model đã bù sẵn một phần phối cảnh thì chỉ số bị nén lại. Đây là con
     * số phải kiểm trong buổi đo: đặt máy ngang / chúc 20° / hất 20° trên cùng một
     * người, xem chỉ số có tách ra thành ba cụm rõ ràng không.
     */
    /**
     * GÓC CHĨA VÀO ỐNG KÍNH của một đoạn cơ thể, ĐỘ.
     *
     * 0° = đoạn nằm song song mặt phẳng ảnh (đo chuẩn nhất).
     * 90° = đoạn chĩa thẳng vào ống kính — chiều dài của nó **trên ảnh co về 0**,
     * mà mọi công thức phối cảnh đều CHIA cho chiều dài đó.
     *
     * ⚠️ VÌ SAO PHẢI CÓ: mẫu đá chân hoặc bước về phía máy thì đoạn hông→gót gần
     * như trùng trục ống kính. Số đo nhảy vọt, mà nguyên nhân là **dáng của mẫu**
     * chứ không phải máy đi đâu cả. App sẽ bảo người cầm máy "lùi lại 2 bước" trong
     * khi họ đứng yên — đổ oan cho máy vì lỗi của dáng.
     *
     * Ngưỡng [MAX_OUT_OF_PLANE_DEG] đo từ 19 ảnh có khoảng cách thật: người đứng
     * bình thường cho 9-26° (trung bình 18,8°, lệch chuẩn 5,1°). 40° nằm giữa
     * khoảng đó và ca chĩa thẳng, cách cả hai bên một quãng rộng.
     */
    private static func outOfPlaneDeg(
        _ a: (first: Double, second: Double, third: Double),
        _ b: (first: Double, second: Double, third: Double)
    ) -> Double {
        let flat = hypot(b.first - a.first, b.second - a.second)
        let depth = abs(b.third - a.third)
        if flat < 1e-9 { return 90.0 }
        return atan2(depth, flat) * 180.0 / Double.pi
    }

    /** Đoạn nối hai trung điểm có đo được không, hay đang chĩa vào ống kính. */
    private static func segmentUsable(
        _ f: PoseFrame,
        _ v: Float,
        _ aL: Int,
        _ aR: Int,
        _ bL: Int,
        _ bR: Int
    ) -> Bool {
        guard let A = midWorld3(f, aL, aR, v) else { return false }
        guard let B = midWorld3(f, bL, bR, v) else { return false }
        return outOfPlaneDeg(A, B) <= MAX_OUT_OF_PLANE_DEG
    }

    /**
     * Đo độ méo hình thang của thân người — trả **cả hai đường đo** khi đo được.
     *
     * Cố ý không dừng ở đường đầu tiên: tầng so sánh cần đường mà **cả ảnh mẫu lẫn
     * khung camera cùng có**, mà bên nào có gì thì không biết trước.
     */
    // =================================================================
    // MỤC 8 — NGHIÊNG NGANG
    // =================================================================

    /**
     * Góc nghiêng của thân người trong ảnh, ĐỘ. Dương = nghiêng sang phải.
     *
     * Trả **cả hai đường đo** khi đo được, cùng lý do như mục ngửa/chúc: tầng so
     * sánh cần đường mà cả ảnh mẫu lẫn khung camera cùng có.
     *
     * Vì sao ưu tiên TRỤC THÂN hơn ĐƯỜNG VAI: mẫu quay nghiêng người thì hai vai
     * chồng lên nhau trên ảnh, đường nối chúng ngắn lại và góc của nó thành nhiễu
     * thuần tuý. Trục thân giữ nguyên độ dài dù mẫu xoay bao nhiêu.
     */
    private static func measureRoll(_ f: PoseFrame, _ v: Float) -> [RollSource: Double] {
        var out: [RollSource: Double] = [:]
        let neck = f.neck(minVisibility: v)
        let root = f.root(minVisibility: v)
        let lsTruoc = f.at(Lm.leftShoulder, minVisibility: v)
        let rsTruoc = f.at(Lm.rightShoulder, minVisibility: v)
        // ⚠️ THÂN BỊ CO RÚT THÌ BỎ ĐƯỜNG TRỤC THÂN (14/09/2026).
        //
        // Chụp từ trên cao chúc xuống, cổ và hông gần như chồng lên nhau trên
        // ảnh. Đoạn thẳng ngắn cỡ đó thì lệch vài điểm ảnh là góc nhảy hàng chục
        // độ. Video test: đúng ảnh chúc từ trên cao thì mục máy nghiêng đỏ suốt
        // dù người chụp cầm máy thẳng.
        //
        // Người đứng bình thường có thân dài hơn bề ngang vai trên ảnh. Ngắn
        // hơn cả bề ngang vai là đã co rút mạnh — lúc đó chỉ tin đường vai.
        let thanCoRut: Bool
        if let neck = neck, let root = root, let lsTruoc = lsTruoc, let rsTruoc = rsTruoc {
            thanCoRut = hypot(neck.x - root.x, neck.y - root.y) <
                THAN_TOI_THIEU_THEO_VAI * hypot(rsTruoc.x - lsTruoc.x, rsTruoc.y - lsTruoc.y)
        } else {
            thanCoRut = false
        }
        if let neck = neck, let root = root, !thanCoRut {
            // Lấy vector HƯỚNG LÊN (hông → cổ) để dấu đọc thuận: đầu ngả sang
            // phải thì cổ nằm bên phải hông, dx dương.
            let dx = neck.x - root.x
            // y hướng XUỐNG nên hông luôn có y lớn hơn cổ — dy luôn dương.
            let dy = root.y - neck.y
            if hypot(dx, dy) > 1e-4 {
                out[.SPINE] = atan2(dx, dy) * 180.0 / Double.pi
            }
        }

        let ls = f.at(Lm.leftShoulder, minVisibility: v)
        let rs = f.at(Lm.rightShoulder, minVisibility: v)
        if let ls = ls, let rs = rs {
            let dx = rs.x - ls.x
            let dy = rs.y - ls.y
            // Hai vai chồng nhau (mẫu quay nghiêng) thì góc vô nghĩa — bỏ.
            if hypot(dx, dy) > MIN_SHOULDER_SPAN {
                // ⚠️ PHẢI QUY VỀ DẢI ±90°, ĐỪNG BỎ BƯỚC NÀY.
                //
                // MediaPipe đặt tên khớp theo GIẢI PHẪU: `LEFT_SHOULDER` là vai
                // trái CỦA NGƯỜI ĐÓ. Mẫu quay mặt vào máy thì vai trái của họ
                // nằm bên PHẢI ảnh, nên vector trái→phải chỉ ngược chiều trục x
                // và `atan2` trả về ~180° thay vì ~0°.
                //
                // Đo thật trên 5 ảnh ở `test-media/5-chan-dung-zoom/`: người
                // đứng thẳng cho ra **177-180°**, trong khi trục thân cho 0,5-2,8°.
                // Hai đường đo lệch nhau ~178° — trộn chúng là sai hoàn toàn.
                //
                // Đường vai là một ĐOẠN THẲNG, không có chiều: quay 180° vẫn là
                // chính nó. Nên gấp về ±90° là đúng bản chất, không phải mẹo.
                let raw = atan2(dy, dx) * 180.0 / Double.pi
                let folded: Double
                if raw > 90.0 {
                    folded = raw - 180.0
                } else if raw <= -90.0 {
                    folded = raw + 180.0
                } else {
                    folded = raw
                }
                out[.SHOULDERS] = folded
            }
        }
        return out
    }

    /**
     * Bề ngang tối thiểu của đường vai trên ảnh để góc của nó còn nghĩa.
     *
     * Dưới mức này là mẫu đang quay nghiêng gần như hoàn toàn: hai vai chồng lên
     * nhau, một sai số vài điểm ảnh làm góc nhảy hàng chục độ.
     */
    private static let MIN_SHOULDER_SPAN = 0.03

    private static func measurePitchCue(_ f: PoseFrame, _ v: Float) -> [PitchSource: Double] {
        var out: [PitchSource: Double] = [:]
        // Cách 0 — TRỤC THÂN 3D, ra thẳng ĐỘ. Đặt đầu vì `pitchDeviation`
        // duyệt theo thứ tự khai báo, nên đây thành đường ưu tiên.
        if let tilt = measureTiltDeg(f, v) { out[.GOC_MAY] = tilt }
        // Cách 1 — CHÂN so với THÂN. Mạnh, nhưng bỏ khi chân chĩa vào ống kính.
        if segmentUsable(f, v, Lm.leftHip, Lm.rightHip, Lm.leftAnkle, Lm.rightAnkle) {
            if let legs = legsOverTorso(f, v) { out[.LEGS] = legs }
        }
        return out
    }

    /** Cách 1 — dựa vào chân. Chính xác hơn vì hai đoạn cách xa nhau theo chiều sâu. */
    private static func legsOverTorso(_ f: PoseFrame, _ v: Float) -> Double? {
        guard let neck2 = f.neck(minVisibility: v) else { return nil }
        guard let root2 = f.root(minVisibility: v) else { return nil }
        guard let ankle2 = lowestY(f, v, Lm.leftAnkle, Lm.rightAnkle) else { return nil }

        let torso2 = abs(root2.y - neck2.y)
        let legs2 = abs(ankle2 - root2.y)
        if torso2 < 1e-4 || legs2 < 1e-4 { return nil }

        guard let neckW = midWorld(f, Lm.leftShoulder, Lm.rightShoulder, v) else { return nil }
        guard let rootW = midWorld(f, Lm.leftHip, Lm.rightHip, v) else { return nil }
        guard let ankleW = [f.world(Lm.leftAnkle, minVisibility: v)?.y, f.world(Lm.rightAnkle, minVisibility: v)?.y]
            .compactMap({ $0 }).max() else { return nil }

        let torso3 = abs(rootW.second - neckW.second)
        let legs3 = abs(ankleW - rootW.second)
        if torso3 < 1e-4 || legs3 < 1e-4 { return nil }

        return log((legs2 / torso2) / (legs3 / torso3))
    }

    /**
     * Cách 2 — dựa vào khung mặt so với vai.
     *
     * Chúc máy xuống thì đầu gần ống kính hơn vai → mặt trông to ra so với vai.
     * Nên phải **ĐẢO DẤU** để cùng quy ước với cách 1 (dương = hất lên).
     */
    private static func midWorld(_ f: PoseFrame, _ a: Int, _ b: Int, _ v: Float) -> (first: Double, second: Double)? {
        guard let pa = f.world(a, minVisibility: v) else { return nil }
        guard let pb = f.world(b, minVisibility: v) else { return nil }
        return (first: (pa.x + pb.x) / 2.0, second: (pa.y + pb.y) / 2.0)
    }

    // =================================================================
    // MỤC 7 — ĐỘ MẠNH PHỐI CẢNH (tách ĐỨNG GẦN khỏi ZOOM VÀO)
    // =================================================================

    /**
     * ĐỘ MÉO PHỐI CẢNH — chỉ số không đơn vị, **miễn nhiễm với zoom**.
     *
     * ## Vấn đề nó giải
     *
     * [scale] đo kích thước biểu kiến, mà đại lượng đó sinh ra từ HAI ẩn số:
     * ```
     *     kích thước biểu kiến  s = f × S / d      (f = tiêu cự, d = khoảng cách)
     * ```
     * Một phương trình hai ẩn ⇒ *đi lại gần* và *đứng yên rồi zoom vào* cho ra
     * **cùng một `scale`**, trong khi hai tấm ảnh khác hẳn nhau.
     *
     * ## Nguyên lý
     *
     * **Phối cảnh chỉ phụ thuộc VỊ TRÍ đặt máy, không phụ thuộc tiêu cự.** Zoom là
     * phép phóng to ĐỀU nên không đổi bất kỳ TỈ LỆ nào bên trong ảnh; đi lại gần
     * thì đổi, vì bộ phận gần ống kính hơn to lên nhanh hơn bộ phận xa.
     *
     * ## Vì sao chọn THÂN so với CHÂN
     *
     * Máy cầm ngang ngực thì **chân là phần lệch xa tầm máy nhất**, nên co ngắn
     * mạnh nhất khi đứng gần. Đứng xa thì chân duỗi ra trông dài hơn.
     *
     * Đã thử cặp **mắt–tai** trước đó và **TRƯỢT**: độ sâu chỉ ~5cm, lại nằm trên
     * cái đầu vốn xoay tự do, nên nó bám theo *tư thế đầu* (tương quan −0,44) hơn
     * là theo *khoảng cách máy* (−0,17). Xem FOOTGUNS mục 37.
     *
     * ## Vì sao phải chia cho tỉ lệ THẬT
     *
     * ```
     *     P = ln[ (thân/chân)ᵗʳêⁿ ᵃⁿʰ  ÷  (thân/chân)ⁿᵍᵒàⁱ đờⁱ ]
     * ```
     * Ảnh mẫu và người đứng trước camera là **hai người khác nhau**, chân dài ngắn
     * khác nhau. Chia cho tỉ lệ thật của chính người đó (`worldLandmarks`) thì khác
     * biệt cơ thể tự triệt tiêu, chỉ còn lại phần do khoảng cách. Đây là chi tiết
     * quyết định: bỏ bước chuẩn hoá thì chỉ số tụt từ **4,67 xuống 2,68**.
     *
     * ## Đã đo được gì
     *
     * 13 ảnh cùng một người, khoảng cách đo bằng thước:
     * ```
     *     1,0m →  0,244  0,248  0,255
     *     2,5m →  0,148  0,179  0,227  0,233  0,234
     *     4,0m →  0,069  0,074  0,107  0,135  0,195
     * ```
     * Giảm đơn điệu, đúng chiều vật lý. **Bắt được chênh lệch từ ~2,5 lần trở lên**
     * (đủ cho ca "đứng gần góc rộng" so với "đứng xa zoom vào"), **không** phân biệt
     * nổi mức ±30%.
     *
     * ⚠️ Chỉ đo được khi thấy chân. Ảnh bán thân và chân dung trả bản đồ rỗng —
     * hồ sơ ảnh mẫu sẽ bỏ mục này và nói rõ lý do.
     *
     * ⚠️⚠️ **ĐÃ THỬ MỞ RỘNG CHO NỬA THÂN TRÊN VÀ THẤT BẠI — ĐỪNG THỬ LẠI.**
     * Đo trên bộ ảnh riêng ở `test-media/5-chan-dung-zoom/` (khung chủ thể bằng
     * nhau, khoảng cách 0,85m → 6m): 5 mốc chỉ dùng thân và đầu, tín hiệu/nhiễu
     * cao nhất **1,54** trong khi cần **≥ 3**. Nguyên nhân là VẬT LÝ: muốn biết xa
     * hay gần thì cần hai bộ phận cách nhau về CHIỀU SÂU, mà đầu và thân gần như
     * cùng một khoảng cách tới ống kính. Xem FOOTGUNS 37.
     * PO chốt 05/09/2026: không làm.
     */
    private static func measurePerspective(_ f: PoseFrame, _ v: Float) -> [PerspectiveSource: Double] {
        var out: [PerspectiveSource: Double] = [:]
        // Tính CẢ HAI cặp khi đo được, không dừng ở cặp đầu tiên: tầng so sánh
        // cần cặp mà cả hai bên cùng có, mà bên nào thấy gì thì không biết trước.
        // ⚠️ Chân chĩa vào ống kính thì BỎ HẲN, không đoán. Xem [outOfPlaneDeg].
        if segmentUsable(f, v, Lm.leftHip, Lm.rightHip, Lm.leftAnkle, Lm.rightAnkle) {
            if let value = torsoOverLower(f, v, Lm.leftAnkle, Lm.rightAnkle) {
                out[.TORSO_ANKLE] = value
            }
        }
        if segmentUsable(f, v, Lm.leftHip, Lm.rightHip, Lm.leftKnee, Lm.rightKnee) {
            if let value = torsoOverLower(f, v, Lm.leftKnee, Lm.rightKnee) {
                out[.TORSO_KNEE] = value
            }
        }
        return out
    }

    /**
     * Thân (vai→hông) so với đoạn dưới (hông→[lowerL]/[lowerR]), đã chia cho tỉ lệ
     * thật để khử khác biệt cơ thể.
     */
    private static func torsoOverLower(
        _ f: PoseFrame,
        _ v: Float,
        _ lowerL: Int,
        _ lowerR: Int
    ) -> Double? {
        guard let neck = f.neck(minVisibility: v) else { return nil }
        guard let root = f.root(minVisibility: v) else { return nil }
        guard let lowI = midPoint(f, lowerL, lowerR, v) else { return nil }

        let torsoImg = hypot(root.x - neck.x, root.y - neck.y)
        let lowerImg = hypot(lowI.first - root.x, lowI.second - root.y)
        if torsoImg < 1e-5 || lowerImg < 1e-5 { return nil }

        guard let neckW = midWorld3(f, Lm.leftShoulder, Lm.rightShoulder, v) else { return nil }
        guard let rootW = midWorld3(f, Lm.leftHip, Lm.rightHip, v) else { return nil }
        guard let lowW = midWorld3(f, lowerL, lowerR, v) else { return nil }

        let torsoW = dist3(neckW, rootW)
        let lowerW = dist3(rootW, lowW)
        if torsoW < 1e-6 || lowerW < 1e-6 { return nil }

        return log((torsoImg / lowerImg) / (torsoW / lowerW))
    }

    /** Trung điểm hai mốc TRÊN ẢNH. */
    private static func midPoint(
        _ f: PoseFrame,
        _ a: Int,
        _ b: Int,
        _ v: Float
    ) -> (first: Double, second: Double)? {
        guard let A = f.at(a, minVisibility: v) else { return nil }
        guard let B = f.at(b, minVisibility: v) else { return nil }
        return (first: (A.x + B.x) / 2.0, second: (A.y + B.y) / 2.0)
    }

    /** Trung điểm hai mốc trong KHÔNG GIAN THẬT. */
    private static func midWorld3(
        _ f: PoseFrame,
        _ a: Int,
        _ b: Int,
        _ v: Float
    ) -> (first: Double, second: Double, third: Double)? {
        guard let A = f.world(a, minVisibility: v) else { return nil }
        guard let B = f.world(b, minVisibility: v) else { return nil }
        return (first: (A.x + B.x) / 2, second: (A.y + B.y) / 2, third: (A.z + B.z) / 2)
    }

    private static func dist3(
        _ a: (first: Double, second: Double, third: Double),
        _ b: (first: Double, second: Double, third: Double)
    ) -> Double {
        return sqrt(
            (a.first - b.first) * (a.first - b.first) +
                (a.second - b.second) * (a.second - b.second) +
                (a.third - b.third) * (a.third - b.third)
        )
    }

    // =================================================================
    // MỤC 6 — DÁNG (trọng số nhẹ nhất, không bao giờ chặn việc chụp)
    // =================================================================

    /**
     * Góc các khớp theo từng nhóm. CHỈ đo nhóm nằm trong lớp khung hình —
     * ảnh chân dung cận thì không bao giờ chấm về chân.
     *
     * Nhóm nào không đủ điểm để tính thì **vắng mặt khỏi map**, không điền 0.
     * Vắng mặt = "không đo được" = bị bỏ ra khi chấm; điền 0 = "đo được và bằng 0"
     * = bị chấm sai. Hai chuyện khác hẳn nhau.
     */
    /**
     * Cánh tay này có dùng để chấm dáng được không.
     *
     * ⚠️ SINH RA CHO SELFIE: tay cầm máy **luôn chĩa thẳng vào ống kính**, và đó
     * không phải một lựa chọn dáng mà là ràng buộc vật lý — không ai đổi được.
     * Để nguyên thì app mãi mãi báo "dáng tay chưa khớp".
     *
     * Không cần đoán tay nào đang cầm máy: hình học tự trả lời. Dùng đúng phép đo
     * và đúng ngưỡng đã dùng cho chân ([MAX_OUT_OF_PLANE_DEG]), vì lý do y hệt —
     * đoạn chĩa vào ống kính thì hình chiếu của nó co về 0 và mọi góc suy từ đó
     * đều vô nghĩa.
     *
     * Có ích cả ngoài selfie: ảnh phá cách kiểu chìa tay ra trước ống kính cũng
     * được lọc bằng chính luật này.
     */
    private static func armUsable(_ f: PoseFrame, _ v: Float, left: Bool) -> Bool {
        let sh = left ? Lm.leftShoulder : Lm.rightShoulder
        let el = left ? Lm.leftElbow : Lm.rightElbow
        let wr = left ? Lm.leftWrist : Lm.rightWrist
        guard let S = f.world(sh, minVisibility: v) else { return false }
        guard let E = f.world(el, minVisibility: v) else { return false }
        func tilt(_ a: P3, _ b: P3) -> Double {
            let flat = hypot(b.x - a.x, b.y - a.y)
            if flat < 1e-9 { return 90.0 }
            return atan2(abs(b.z - a.z), flat) * 180.0 / Double.pi
        }
        if tilt(S, E) > MAX_OUT_OF_PLANE_DEG { return false }
        guard let W = f.world(wr, minVisibility: v) else { return true }   // không thấy cổ tay thì chỉ xét cánh trên
        return tilt(E, W) <= MAX_OUT_OF_PLANE_DEG
    }

    private static func measurePose(
        _ f: PoseFrame,
        _ groups: Set<PoseGroup>,
        _ v: Float
    ) -> [PoseGroup: [Double]] {
        var out: [PoseGroup: [Double]] = [:]

        for g in groups {
            let angles: [Double]
            switch g {
            case .spine:
                angles = [segmentAngle(f.neck(minVisibility: v), f.root(minVisibility: v))].compactMap { $0 }
            case .head:
                angles = [segmentAngle(f.neck(minVisibility: v), f.at(Lm.nose, minVisibility: v))].compactMap { $0 }
            // ⚠️ LUÔN TRẢ ĐÚNG 4 PHẦN TỬ, dùng NaN cho khớp không đo được.
            //
            // Trước đây dùng `listOfNotNull`: thiếu một khớp là danh sách ngắn
            // đi, hai bên khác số phần tử, và `poseDiff` bỏ HẲN cả nhóm tay —
            // che một cổ tay là mất luôn phép so cánh tay còn lại.
            //
            // Giữ đúng vị trí thì mỗi bên tự bỏ khớp của mình, bên kia không
            // bị vạ lây. Cần cho selfie: tay cầm máy luôn phải bỏ, nhưng tay
            // còn lại mới là dáng thật sự.
            case .arms:
                angles = [
                    armUsable(f, v, left: true)
                        ? jointAngle(f, Lm.leftShoulder, Lm.leftElbow, Lm.leftWrist, v) : nil,
                    armUsable(f, v, left: false)
                        ? jointAngle(f, Lm.rightShoulder, Lm.rightElbow, Lm.rightWrist, v) : nil,
                    armUsable(f, v, left: true)
                        ? segmentAngle(f.at(Lm.leftShoulder, minVisibility: v), f.at(Lm.leftElbow, minVisibility: v)) : nil,
                    armUsable(f, v, left: false)
                        ? segmentAngle(f.at(Lm.rightShoulder, minVisibility: v), f.at(Lm.rightElbow, minVisibility: v)) : nil,
                ].map { $0 ?? Double.nan }
            case .legs:
                angles = [
                    jointAngle(f, Lm.leftHip, Lm.leftKnee, Lm.leftAnkle, v),
                    jointAngle(f, Lm.rightHip, Lm.rightKnee, Lm.rightAnkle, v),
                ].compactMap { $0 }
            }
            if !angles.isEmpty { out[g] = angles }
        }
        return out
    }

    // =================================================================
    // Mốc dùng chung
    // =================================================================

    /**
     * Điểm mốc ĐẦU. MediaPipe không có điểm "đỉnh đầu", nên lấy trung điểm hai tai
     * (hoặc mũi nếu không thấy tai).
     *
     * Đây KHÔNG phải đỉnh đầu thật, và không cần phải là. Cái cần là **ảnh mẫu và
     * khung camera dùng chung một định nghĩa** — vì kết quả cuối cùng là phép trừ
     * giữa hai bên, sai số chung triệt tiêu nhau.
     */
    private static func headPoint(_ f: PoseFrame, _ v: Float) -> P2? {
        let le = f.at(Lm.leftEar, minVisibility: v)
        let re = f.at(Lm.rightEar, minVisibility: v)
        if let le = le, let re = re { return (le + re) / 2.0 }
        return f.at(Lm.nose, minVisibility: v) ?? le ?? re
    }

    /** Khung bao phần MẶT (11 điểm đầu: mũi, mắt, tai, miệng). */
    private static func faceBox(_ f: PoseFrame, _ v: Float) -> Box? {
        var minX = Double.infinity
        var maxX = -Double.infinity
        var minY = Double.infinity
        var maxY = -Double.infinity
        var found = false
        for i in Lm.nose...Lm.mouthRight {
            guard let p = f.at(i, minVisibility: v) else { continue }
            found = true
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return found ? Box(left: minX, top: minY, right: maxX, bottom: maxY) : nil
    }

    /** Toạ độ y THẤP NHẤT (số lớn nhất, vì y hướng xuống) trong các điểm cho trước. */
    private static func lowestY(_ f: PoseFrame, _ v: Float, _ idx: Int...) -> Double? {
        return idx.compactMap { f.at($0, minVisibility: v)?.y }.max()
    }

    /**
     * Góc của đoạn thẳng a→b so với phương thẳng đứng hướng xuống, ĐỘ, -180..180.
     * 0 = b nằm ngay bên dưới a.
     */
    private static func segmentAngle(_ a: P2?, _ b: P2?) -> Double? {
        if a == nil || b == nil { return nil }
        let dx = b!.x - a!.x
        let dy = b!.y - a!.y
        if hypot(dx, dy) < 1e-6 { return nil }
        return atan2(dx, dy) * 180.0 / Double.pi
    }

    /** Góc mở tại khớp giữa (ví dụ khuỷu tay), ĐỘ, 0..180. 180 = duỗi thẳng. */
    private static func jointAngle(
        _ f: PoseFrame,
        _ aIdx: Int,
        _ bIdx: Int,
        _ cIdx: Int,
        _ v: Float
    ) -> Double? {
        guard let a = f.at(aIdx, minVisibility: v) else { return nil }
        guard let b = f.at(bIdx, minVisibility: v) else { return nil }
        guard let c = f.at(cIdx, minVisibility: v) else { return nil }
        let v1x = a.x - b.x
        let v1y = a.y - b.y
        let v2x = c.x - b.x
        let v2y = c.y - b.y
        let n1 = hypot(v1x, v1y)
        let n2 = hypot(v2x, v2y)
        if n1 < 1e-6 || n2 < 1e-6 { return nil }
        let cos = min(max((v1x * v2x + v1y * v2y) / (n1 * n2), -1.0), 1.0)
        return acos(cos) * 180.0 / Double.pi
    }
}
