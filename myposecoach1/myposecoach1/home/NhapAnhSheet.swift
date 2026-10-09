import SwiftUI

/// BẢNG GẮN NHÃN ẢNH VỪA NHẬP — hiện NGAY sau khi chọn ảnh từ máy.
///
/// PO: *"khi user nhập ảnh, mở bottom sheet, preview ảnh, và user chọn tag góc nào
/// thì sẽ hợp lý hơn là mở ảnh sau khi đã import thành template rồi hiện chọn tag"*.
///
/// Bản trước chép ảnh vào thư viện TRƯỚC, rồi mới hỏi kiểu chụp / góc máy lẫn trong
/// hộp thoại tiêu chí. Hai cái dở: ảnh chưa gắn nhãn đã nằm trong lưới (thoát giữa
/// chừng là thành ảnh mẫu thiếu thông tin), và hộp thoại vừa hỏi vừa báo cáo.
///
/// Giờ: xem ảnh → chọn nhãn → **"Lưu ảnh mẫu"** mới vào thư viện, và từ đó ảnh tự
/// nhập đi đúng đường của ảnh cài sẵn. Huỷ hoặc vuốt đóng thì xoá file tạm.
///
/// - Parameters:
///   - onLuu: file đã đổi tên theo nhãn + kết quả phân tích (để khỏi phân tích lại).
struct NhapAnhSheet: View {
    let file: URL
    let onHuy: () -> Void
    let onChonAnhKhac: () -> Void
    let onLuu: (URL, PhanTichAnhMau) -> Void

    /// Ảnh xem trước đã dựng đúng chiều.
    @State private var anh: UIImage? = nil
    @State private var kq: PhanTichAnhMau? = nil
    @State private var kieu: MediaLibrary.TemplateKind = .PHOTOGRAPHER
    @State private var goc: MediaLibrary.GocMayNhan? = nil
    @State private var kieuTren: KieuChupTren? = nil

    /// Câu hỏi thứ ba CHỈ hiện với ảnh người khác chụp từ trên cao — xem `KieuChupTren`.
    private var hoiKieuTren: Bool {
        kieu == .PHOTOGRAPHER && goc == .TREN
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Thêm ảnh mẫu")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Ds.text)
                Color.clear.frame(height: 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Ds.surfaceMuted)
                    if let anh {
                        Image(uiImage: anh)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                Color.clear.frame(height: 14)

                if let k = kq {
                    noiDung(k)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Đang phân tích ảnh…")
                            .font(.system(size: 13))
                            .foregroundColor(Ds.textMuted)
                    }
                }
            }
            .padding(.horizontal, Ds.pageH)
            .padding(.bottom, 24)
        }
        .background(Ds.surface)
        .tint(Ds.primary)
        .task(id: file) { await phanTich() }
        // Tương đương `ModalBottomSheet(skipPartiallyExpanded = true)` bên Android:
        // bảng mở hết chiều cao, có thanh kéo, nền màu surface.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Ds.surface)
    }

    /// Nạp ảnh xem trước và phân tích ảnh — CHẶNG, phải chạy off main thread vì
    /// `phanTichAnhMau` giải mã ảnh và chạy Vision.
    private func phanTich() async {
        // Ảnh điện thoại cỡ lớn; giải mã trên main là bảng đứng im.
        let preview = await Task.detached(priority: .userInitiated) {
            UprightBitmap.decode(file: file, shortSide: 720)
        }.value
        // Bảng đã bị đóng trong lúc chờ thì đừng ghi state vào view đã mất.
        guard !Task.isCancelled else { return }
        anh = preview

        let k = await Task.detached(priority: .userInitiated) {
            phanTichAnhMau(file: file)
        }.value
        guard !Task.isCancelled else { return }

        // Kiểu chụp ĐOÁN sẵn theo khung hình — ảnh chân dung gần như luôn là selfie —
        // nhưng hiện rõ trên nút để đổi được. Góc máy thì KHÔNG đoán (FOOTGUNS 88).
        if let f = k.framing, f == .chest || f == .head {
            kieu = .SELFIE
        } else {
            kieu = .PHOTOGRAPHER
        }
        kq = k
    }

    // MARK: - Nội dung dưới ảnh xem trước

    @ViewBuilder
    private func noiDung(_ k: PhanTichAnhMau) -> some View {
        switch k.verdict {
        case .Rejected(let reason, let hint):
            Text("Ảnh này chưa dùng được")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Ds.dangerText)
            Color.clear.frame(height: 4)
            Text(reason)
                .font(.system(size: 13))
                .foregroundColor(Ds.text)
            Text(hint)
                .font(.system(size: 13))
                .foregroundColor(Ds.textMuted)
            Color.clear.frame(height: 16)
            HStack(spacing: 10) {
                Button(action: onHuy) {
                    Text("Huỷ")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button(action: onChonAnhKhac) {
                    Text("Chọn ảnh khác")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .Accepted:
            chonNhan
            if hoiKieuTren {
                chonKieuTren
            }
            Color.clear.frame(height: 18)
            HStack(spacing: 10) {
                Button(action: onHuy) {
                    Text("Huỷ")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button {
                    let chot = MediaLibrary.ganNhan(
                        file,
                        kind: kieu,
                        goc: goc,
                        kieuTren: hoiKieuTren ? kieuTren : nil
                    )
                    onLuu(chot, k)
                } label: {
                    Text("Lưu ảnh mẫu")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                // Thiếu nhãn là ảnh chưa đi được đường nào — không cho lưu.
                .disabled(goc == nil || (hoiKieuTren && kieuTren == nil))
            }
        }
    }

    // MARK: - Hai nhãn cho ảnh tự nhập

    /// HAI NHÃN CHO ẢNH TỰ NHẬP: chụp kiểu gì, và máy đặt ở đâu.
    ///
    /// Ảnh cài sẵn mang hai thông tin này trong tên file. Thiếu kiểu chụp là mở sai
    /// camera, thiếu góc máy là ảnh selfie mất hai mục hướng dẫn. Xem `MediaLibrary.ganNhan`.
    ///
    /// Câu hỏi góc máy hiện với MỌI ảnh: suy góc máy từ khung xương lẫn dáng đứng và
    /// loại ống kính nên không tin được, kể cả ảnh toàn thân (FOOTGUNS 91).
    @ViewBuilder
    private var chonNhan: some View {
        Text("Ảnh này chụp kiểu gì?")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(Ds.text)
        Color.clear.frame(height: 6)
        HStack(spacing: 8) {
            NhapAnhChip(title: "Người khác chụp", selected: kieu == .PHOTOGRAPHER) {
                kieu = .PHOTOGRAPHER
            }
            NhapAnhChip(title: "Selfie", selected: kieu == .SELFIE) {
                kieu = .SELFIE
            }
            NhapAnhChip(title: "Qua gương", selected: kieu == .MIRROR) {
                kieu = .MIRROR
            }
        }

        Color.clear.frame(height: 14)
        Text("Máy đặt ở đâu khi chụp?")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(Ds.text)
        Text(
            "App không tự đoán chính xác được góc máy từ ảnh, nên cần bạn chọn để " +
                "hướng dẫn đúng việc nâng/hạ và chúc/hất máy. Nhìn ảnh theo gợi ý dưới mỗi mục."
        )
        .font(.system(size: 12))
        .foregroundColor(Ds.textMuted)
        Color.clear.frame(height: 6)

        // KHUNG QUY CHUẨN nhận biết góc máy bằng mắt — xem DIEM_YEU_GOC_MAY_SELFIE.md.
        // Người dùng chọn, app không đoán: đoán bằng mặt/cổ/vai chỉ trúng 59%.
        NhapAnhDongChon(
            chon: goc == .TREN,
            ten: "Trên cao, chúc xuống",
            goiY: "Thấy đỉnh đầu hoặc sàn nhà · cằm che gần hết cổ · mắt ngước lên nhìn máy"
        ) { goc = .TREN }
        NhapAnhDongChon(
            chon: goc == .NGANG,
            ten: "Ngang tầm mắt",
            goiY: "Nền là tường · mặt, cổ, vai cân đối · mắt nhìn thẳng"
        ) { goc = .NGANG }
        NhapAnhDongChon(
            chon: goc == .DUOI,
            ten: "Dưới thấp, hất lên",
            goiY: "Thấy trần nhà hoặc bầu trời · thấy dưới cằm · mắt liếc xuống nhìn máy"
        ) { goc = .DUOI }

        if goc == nil {
            Text("Chọn góc máy để lưu")
                .font(.system(size: 12))
                .foregroundColor(Ds.warning)
                .padding(.top, 4)
        }
    }

    // MARK: - Câu thứ ba: kiểu chụp từ trên cao

    /// Chỉ hiện với ảnh người khác chụp, góc trên cao. Xem `KieuChupTren`.
    @ViewBuilder
    private var chonKieuTren: some View {
        Color.clear.frame(height: 14)
        Text("Chụp từ trên cao kiểu nào?")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(Ds.text)
        Text(
            "Cùng chúc máy xuống nhưng đứng gần, dùng góc rộng hay đứng xa rồi zoom cho ra " +
                "ảnh khác hẳn. Nhìn độ to của đầu so với chân."
        )
        .font(.system(size: 12))
        .foregroundColor(Ds.textMuted)
        Color.clear.frame(height: 6)
        ForEach(KieuChupTren.allCases, id: \.self) { k in
            NhapAnhDongChon(chon: kieuTren == k, ten: k.nhan, goiY: k.goiY) {
                kieuTren = k
            }
        }
        if kieuTren == nil {
            Text("Chọn kiểu chụp để lưu")
                .font(.system(size: 12))
                .foregroundColor(Ds.warning)
                .padding(.top, 4)
        }
    }
}

// MARK: - Viên chọn nhãn

/// Một viên chọn cho ảnh tự nhập: nhãn chụp kiểu gì (ba lựa chọn ngắn).
private struct NhapAnhChip: View {
    let title: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(selected ? Ds.primary : Ds.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Ds.primary.opacity(0.14) : Ds.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dòng chọn có nút tròn

/// Một dòng chọn có nút tròn, tên và gợi ý nhận biết.
private struct NhapAnhDongChon: View {
    let chon: Bool
    let ten: String
    let goiY: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(chon ? Ds.primary : Ds.textMuted, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if chon {
                        Circle()
                            .fill(Ds.primary)
                            .frame(width: 10, height: 10)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ten)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Ds.text)
                    Text(goiY)
                        .font(.system(size: 12))
                        .foregroundColor(Ds.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chon ? Ds.primary.opacity(0.10) : Ds.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // Chừa 3dp giữa các dòng như Android — không có thì hai dòng dính nhau.
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hộp thoại cổng kiểm

/// HỘP THOẠI KẾT QUẢ CỔNG KIỂM.
///
/// Ở `internal` (không `private`) vì `HomeScreen` cũng dùng — đúng vị trí file như
/// bản Android đặt `GateDialog` cạnh màn hình gọi nó.
///
/// 🔴 Từ chối: chỉ có nút đóng — **không có đường vào màn camera**. Đây là điểm khác
/// cốt lõi so với bản iOS cũ.
/// 🟡 Nhận có cảnh báo: nói rõ tiêu chí nào sẽ bị bỏ qua, rồi cho người dùng tự quyết.
///
/// Vẽ bằng view thay vì `alert`: nội dung dài và phải cuộn được, mà alert của
/// SwiftUI không cuộn.
struct GateDialog: View {
    let verdict: TemplateVerdict

    /// Hồ sơ tiêu chí suy từ chính ảnh mẫu này. `nil` khi ảnh bị từ chối.
    let profile: TemplateProfile?
    let onDismiss: () -> Void
    var poseGuide: [String] = []
    var difficulty: PoseDescriber.Difficulty? = nil
    let onProceed: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            switch verdict {
            case .Rejected(let reason, let hint):
                khung {
                    Text("Ảnh này chưa dùng được")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Ds.text)
                    Color.clear.frame(height: 8)
                    Text(reason)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Ds.text)
                    Color.clear.frame(height: 8)
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundColor(Ds.textMuted)
                    Color.clear.frame(height: 10)
                    nutHanhDong {
                        dongNut("Chọn ảnh khác", action: onDismiss)
                    }
                }

            case .Accepted(let framing, let warnings):
                khung {
                    Text("Ảnh mẫu này sẽ chấm theo")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Ds.text)
                    Color.clear.frame(height: 10)
                    ScrollView {
                        noiDungNhan(framing: framing, warnings: warnings)
                    }
                    .frame(maxHeight: 420)
                    Color.clear.frame(height: 12)
                    nutHanhDong {
                        dongNut("Đóng", action: onDismiss)
                        dongNut("Bắt đầu chụp", action: onProceed)
                    }
                }
            }
        }
    }

    // MARK: - Khung hộp thoại

    private func khung<NoiDung: View>(@ViewBuilder _ content: () -> NoiDung) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(20)
            .frame(maxWidth: 360, alignment: .leading)
            .background(Ds.surface)
            .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
            .padding(.horizontal, 28)
    }

    /// Dải nút dưới cùng, bám mép phải như `AlertDialog` của Material.
    private func nutHanhDong<NoiDung: View>(@ViewBuilder _ content: () -> NoiDung) -> some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            content()
        }
    }

    private func dongNut(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Ds.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nội dung phần nhận

    @ViewBuilder
    private func noiDungNhan(framing: FramingClass, warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kiểu khung hình: \(framing.displayName)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Ds.text)

            if let d = difficulty {
                Color.clear.frame(height: 4)
                Text("Độ khó: \(d.label) — \(d.hint)")
                    .font(.system(size: 13))
                    .foregroundColor(mauDoKho(d))
            }

            // --- THỨ TỰ LÀM VIỆC — đọc cho mẫu nghe TRƯỚC khi bấm ---
            //
            // ⚠️ Đây là cách CHÍNH để tránh mẫu tạo dáng làm hỏng số đo, rẻ hơn hẳn
            // mọi chốt chặn kỹ thuật: bảo người ta đừng làm việc đó vào lúc đó.
            // Chốt chặn trong tầng đo chỉ còn là lưới an toàn.
            //
            // Phạm vi nhắc CỐ Ý HẸP: không một tiêu chí nào về máy đọc tới cánh tay,
            // nên dáng tay làm lúc nào cũng được. Chỉ chân di chuyển theo chiều SÂU
            // (đá về phía máy, bước tới) mới phá số đo.
            Color.clear.frame(height: 10)
            Text("Nói với mẫu trước khi chụp")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Ds.text)
            Text("• Đứng (hoặc ngồi) đúng tư thế nền, rồi GIỮ YÊN CHÂN — khoan đá chân hay bước về phía máy.")
                .font(.system(size: 13))
                .foregroundColor(Ds.text)
            Text("• Đợi người chụp canh xong góc, có báo rồi mới vào dáng. Dáng tay thì làm lúc nào cũng được.")
                .font(.system(size: 13))
                .foregroundColor(Ds.text)

            if !poseGuide.isEmpty {
                Color.clear.frame(height: 10)
                Text("Dáng cần làm")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Ds.text)
                // ⚠️ Mẫu KHÔNG nhìn được màn hình (đứng cách 2-4m, quay mặt về ống
                // kính). Nên phần này để người cầm máy ĐỌC TO LÊN trước khi chụp,
                // mẫu vào dáng gần đúng, lúc chụp chỉ còn chỉnh nhỏ.
                ForEach(poseGuide, id: \.self) { cau in
                    Text("• \(cau)")
                        .font(.system(size: 13))
                        .foregroundColor(Ds.text)
                }
            }

            Color.clear.frame(height: 10)
            if let p = profile {
                tieuChi(profile: p)
            }

            if !warnings.isEmpty {
                Color.clear.frame(height: 10)
                Text("Lưu ý")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Ds.text)
                ForEach(warnings, id: \.self) { w in
                    Text("• \(w)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xE65100))
                        .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Tiêu chí áp dụng cho riêng ảnh mẫu này

    @ViewBuilder
    private func tieuChi(profile p: TemplateProfile) -> some View {
        let dung = p.activeFor(Stage.GUIDANCE)
        Text("Hướng dẫn khi chụp (\(dung.count) tiêu chí)")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Ds.text)
        // Sắp theo vị trí khai báo trong enum — đúng thứ tự kiểm và thứ tự nhắc.
        // Để `Set` tự xáo thì mỗi lần mở hộp thoại là một thứ tự khác.
        ForEach(dung.sorted { $0.ordinal < $1.ordinal }, id: \.self) { c in
            // Riêng mục dáng: nói rõ chấm những nhóm khớp nào. Ảnh chân dung cận sẽ
            // KHÔNG có "chân" ở đây — đó là điểm mấu chốt.
            Text("✓ \(c.label)\(chiTietPose(c, profile: p))")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x2E7D32))
        }

        let hauKy = p.activeFor(Stage.SELECTION).subtracting(dung)
        if !hauKy.isEmpty {
            Color.clear.frame(height: 8)
            Text("Chấm thêm khi chọn ảnh")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Ds.text)
            ForEach(hauKy.sorted { $0.ordinal < $1.ordinal }, id: \.self) { c in
                Text("✓ \(c.label)")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x2E7D32))
            }
        }

        // Nói rõ mục nào KHÔNG áp dụng và vì sao. Im lặng bỏ qua thì người dùng
        // không hiểu vì sao app chẳng nhắc gì về mục đó.
        if !p.skipped.isEmpty {
            Color.clear.frame(height: 8)
            Text("Không áp dụng")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Ds.text)
            ForEach(p.skipped.sorted { $0.key.ordinal < $1.key.ordinal }, id: \.key) { c, why in
                Text("✕ \(c.label) — \(why)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x757575))
                    .padding(.bottom, 4)
            }
        }
    }

    /// Phần "(thân, tay…)" nối sau mục dáng — chỉ khi hồ sơ có nhóm khớp.
    private func chiTietPose(_ c: Criterion, profile p: TemplateProfile) -> String {
        guard c == .POSE, !p.poseGroups.isEmpty else { return "" }
        let thuTu = PoseGroup.allCases.filter { p.poseGroups.contains($0) }
        return "  (" + thuTu.map { $0.label }.joined(separator: ", ") + ")"
    }

    private func mauDoKho(_ d: PoseDescriber.Difficulty) -> Color {
        switch d {
        case .de: return Color(hex: 0x2E7D32)
        case .trungBinh: return Color(hex: 0xE65100)
        case .kho: return Color(hex: 0xC62828)
        }
    }
}
