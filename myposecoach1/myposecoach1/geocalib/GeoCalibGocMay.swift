import CoreGraphics
import Foundation
import OnnxRuntimeBindings
import UIKit

/// Đo góc máy từ nền ảnh bằng đúng model ONNX int8 và tiền xử lý của Android.
nonisolated enum GeoCalibGocMay {
    struct KetQua {
        let pitchDeg: Double
        let rollDeg: Double
        let vfovDeg: Double
        let thoiGianMs: Int64
    }

    private final class Engine: @unchecked Sendable {
        let env: ORTEnv
        let session: ORTSession
        let inputName: String
        let outputNames: [String]
        init() throws {
            guard let model = Bundle.main.path(
                forResource: "geocalib-mang-int8", ofType: "onnx", inDirectory: "geocalib"
            ) ?? Bundle.main.path(forResource: "geocalib-mang-int8", ofType: "onnx") else {
                throw NSError(domain: "GeoCalib", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Thiếu model GeoCalib trong bundle"])
            }
            env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            session = try ORTSession(env: env, modelPath: model, sessionOptions: options)
            guard let input = try session.inputNames().first else {
                throw NSError(domain: "GeoCalib", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Model không có input"])
            }
            inputName = input
            outputNames = try session.outputNames()
            guard outputNames.count == 4 else {
                throw NSError(domain: "GeoCalib", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Model phải có 4 output"])
            }
        }
    }

    private static let lock = NSLock()
    private static var engine: Engine?
    private static var broken = false
    private static let CANH_NGAN = 320
    private static let BOI_SO = 32

    static func phanTich(_ image: UIImage) -> KetQua? {
        let start = Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        lock.lock()
        defer { lock.unlock() }
        if engine == nil && !broken {
            do { engine = try Engine() }
            catch {
                broken = true
                NSLog("GeoCalib: không nạp được model — \(error)")
            }
        }
        guard let engine, let (chw, h, w) = tienXuLy(image) else { return nil }
        do {
            let inputData = chw.withUnsafeBytes { Data($0) }
            let tensor = try ORTValue(
                tensorData: NSMutableData(data: inputData),
                elementType: .float,
                shape: [NSNumber(value: 1), NSNumber(value: 3),
                        NSNumber(value: h), NSNumber(value: w)]
            )
            let outputs = try engine.session.run(
                withInputs: [engine.inputName: tensor],
                outputNames: Set(engine.outputNames),
                runOptions: nil
            )
            let arrays: [[Float]] = try engine.outputNames.map { name in
                guard let value = outputs[name] else {
                    throw NSError(domain: "GeoCalib", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "Thiếu output \(name)"])
                }
                let data = try value.tensorData() as Data
                return data.withUnsafeBytes { raw in
                    Array(raw.bindMemory(to: Float.self))
                }
            }
            guard let camera = GiaiPhoiCanh.giai(
                up: arrays[0], upTinCay: arrays[1], viDo: arrays[2], viDoTinCay: arrays[3],
                h: h, w: w
            ) else { return nil }
            let elapsed = Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) - start
            return KetQua(pitchDeg: camera.pitchDeg, rollDeg: camera.rollDeg,
                          vfovDeg: camera.vfovDeg, thoiGianMs: elapsed)
        } catch {
            NSLog("GeoCalib: inference thất bại — \(error)")
            return nil
        }
    }

    /// Cạnh ngắn 320, thu nhỏ theo nấc 1/2, crop giữa về bội 32, RGB CHW 0...1.
    private static func tienXuLy(_ image: UIImage) -> (chw: [Float], h: Int, w: Int)? {
        guard var cg = image.cgImage else { return nil }
        let ow = cg.width, oh = cg.height
        guard min(ow, oh) >= BOI_SO else { return nil }
        let scale = Double(CANH_NGAN) / Double(min(ow, oh))
        let nw = Int((Double(ow) * scale).rounded())
        let nh = Int((Double(oh) * scale).rounded())
        while cg.width / 2 >= nw && cg.height / 2 >= nh {
            guard let next = resized(cg, width: cg.width / 2, height: cg.height / 2) else { return nil }
            cg = next
        }
        if cg.width != nw || cg.height != nh {
            guard let next = resized(cg, width: nw, height: nh) else { return nil }
            cg = next
        }
        let w = (nw / BOI_SO) * BOI_SO, h = (nh / BOI_SO) * BOI_SO
        let x0 = (nw - w) / 2, y0 = (nh - h) / 2
        guard let cropped = cg.cropping(to: CGRect(x: x0, y: y0, width: w, height: h)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let color = CGColorSpaceCreateDeviceRGB()
        let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: color,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            // CGContext có gốc dưới-trái; đảo trục để giữ thứ tự hàng trên→dưới như Android.
            context.translateBy(x: 0, y: CGFloat(h)); context.scaleBy(x: 1, y: -1)
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        let count = w * h
        var chw = [Float](repeating: 0, count: 3 * count)
        for i in 0..<count {
            chw[i] = Float(rgba[4*i]) / 255
            chw[count+i] = Float(rgba[4*i+1]) / 255
            chw[2*count+i] = Float(rgba[4*i+2]) / 255
        }
        return (chw, h, w)
    }

    private static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
