import Foundation
import UIKit
#if canImport(MLKitImageLabeling) && canImport(MLKitVision)
import MLKitImageLabeling
import MLKitVision
#endif

nonisolated struct KetQuaNhap {
    let phanTich: PhanTichAnhMau
    let geo: GeoCalibGocMay.KetQua?
    let kieu: MediaLibrary.TemplateKind
    let kieuChac: Bool
    let goc: MediaLibrary.GocMayNhan?
    let gocChac: Bool
    let kieuTren: KieuChupTren?

    var canKieuTren: Bool { kieu == .PHOTOGRAPHER && goc == .TREN }
    var duChac: Bool {
        guard case .Accepted = phanTich.verdict else { return false }
        return kieuChac && gocChac && goc != nil && (!canKieuTren || kieuTren != nil)
    }
}

/// Tự trả lời các câu hỏi nhập ảnh bằng cùng luật và ngưỡng của Android.
nonisolated func nhanDienNhap(file: URL) -> KetQuaNhap {
    let analysis = phanTichAnhMau(file: file)
    let image: UIImage? = {
        guard case .Accepted = analysis.verdict else { return nil }
        return UprightBitmap.decode(file: file)
    }()
    let labels = image.map(nhanMlKit) ?? [:]
    let geo = image.flatMap(GeoCalibGocMay.phanTich)
    let phone = labels["Mobile phone"] ?? 0
    let selfie = labels["Selfie"] ?? 0
    let outside = analysis.coTayNgoaiKhung
    let close = analysis.framing == .head || analysis.framing == .chest

    let kind: MediaLibrary.TemplateKind
    let kindCertain: Bool
    if phone >= 0.5 { kind = .MIRROR; kindCertain = true }
    else if selfie >= 0.6 { kind = .SELFIE; kindCertain = true }
    else if outside == 2 && analysis.framing != .full { kind = .SELFIE; kindCertain = true }
    else if outside == 0 && phone < 0.3 && selfie < 0.3 { kind = .PHOTOGRAPHER; kindCertain = true }
    else if outside == 1 && close { kind = .SELFIE; kindCertain = false }
    else if close { kind = .SELFIE; kindCertain = false }
    else { kind = .PHOTOGRAPHER; kindCertain = false }

    let angle: MediaLibrary.GocMayNhan? = geo.map {
        if $0.pitchDeg <= -15 { return .TREN }
        if $0.pitchDeg >= 15 { return .DUOI }
        return .NGANG
    }
    let angleCertain = geo.map { abs(abs($0.pitchDeg) - 15) >= 4 } ?? false
    let highKind = kind == .PHOTOGRAPHER && angle == .TREN
        ? DoanKieuTren.doan(vfovDeg: geo?.vfovDeg, taiChan: analysis.taiChan)
        : nil
    return KetQuaNhap(phanTich: analysis, geo: geo, kieu: kind, kieuChac: kindCertain,
                      goc: angle, gocChac: angleCertain, kieuTren: highKind)
}

private nonisolated func nhanMlKit(_ image: UIImage) -> [String: Float] {
#if canImport(MLKitImageLabeling) && canImport(MLKitVision)
    let options = ImageLabelerOptions()
    options.confidenceThreshold = 0.2
    let labeler = ImageLabeler.imageLabeler(options: options)
    let input = VisionImage(image: image)
    input.orientation = image.imageOrientation
    do {
        return Dictionary(uniqueKeysWithValues: try labeler.results(in: input).map { ($0.text, $0.confidence) })
    } catch {
        NSLog("NhanDienNhap: ML Kit Image Labeling thất bại — \(error)")
        return [:]
    }
#else
    return [:]
#endif
}
