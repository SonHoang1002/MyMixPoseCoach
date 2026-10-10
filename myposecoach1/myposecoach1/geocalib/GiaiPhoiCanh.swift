import Foundation

/// Bộ giải phối cảnh Levenberg–Marquardt, port trực tiếp từ Android.
nonisolated enum GiaiPhoiCanh {
    struct Camera {
        let rollDeg: Double
        let pitchDeg: Double
        let vfovDeg: Double
    }

    static let BUOC_LUOI = 4
    private static let SO_VONG = 30
    private static let THANG_HUBER = 1e-2
    private static let EPS = 1e-4

    static func giai(
        up: [Float], upTinCay: [Float], viDo: [Float], viDoTinCay: [Float],
        h: Int, w: Int, buocLuoi: Int = BUOC_LUOI
    ) -> Camera? {
        guard up.count == 2 * h * w, upTinCay.count == h * w,
              viDo.count == h * w, viDoTinCay.count == h * w,
              h > 0, w > 0, buocLuoi > 0 else { return nil }
        let n = ((h + buocLuoi - 1) / buocLuoi) * ((w + buocLuoi - 1) / buocLuoi)
        var xs = [Double](), ys = [Double](), upx = [Double](), upy = [Double]()
        var cu = [Double](), sl = [Double](), cl = [Double]()
        for y in stride(from: 0, to: h, by: buocLuoi) {
            for x in stride(from: 0, to: w, by: buocLuoi) {
                let i = y * w + x
                xs.append(Double(x)); ys.append(Double(y))
                upx.append(Double(up[i])); upy.append(Double(up[h * w + i]))
                cu.append(Double(upTinCay[i])); sl.append(sin(Double(viDo[i])))
                cl.append(Double(viDoTinCay[i]))
            }
        }

        func duSo(_ t: [Double], _ outU: inout [Double], _ outL: inout [Double]) {
            let f = exp(t[2])
            let g0 = -sin(t[0]) * cos(t[1])
            let g1 = -cos(t[0]) * cos(t[1])
            let g2 = sin(t[1])
            for j in 0..<n {
                let u = (xs[j] - Double(w) / 2) / f
                let v = (ys[j] - Double(h) / 2) / f
                var ax = g0 - g2 * u, ay = g1 - g2 * v
                let m = sqrt(ax * ax + ay * ay) + 1e-12
                ax /= m; ay /= m
                outU[2 * j] = upx[j] - ax
                outU[2 * j + 1] = upy[j] - ay
                outL[j] = sl[j] - (u * g0 + v * g1 + g2) / sqrt(u * u + v * v + 1)
            }
        }

        var wu = [Double](repeating: 0, count: n)
        var wl = [Double](repeating: 0, count: n)
        func chiPhi(_ u: [Double], _ l: [Double], _ ghi: Bool) -> Double {
            var c1 = 0.0, c2 = 0.0
            for j in 0..<n {
                let xu = (u[2*j] * u[2*j] + u[2*j+1] * u[2*j+1]) / THANG_HUBER
                let xl = l[j] * l[j] / THANG_HUBER
                c1 += (xu <= 1 ? xu : 2 * sqrt(xu) - 1) * THANG_HUBER * cu[j]
                c2 += (xl <= 1 ? xl : 2 * sqrt(xl) - 1) * THANG_HUBER * cl[j]
                if ghi {
                    wu[j] = (xu <= 1 ? 1 : 1 / sqrt(xu)) * cu[j]
                    wl[j] = (xl <= 1 ? 1 : 1 / sqrt(xl)) * cl[j]
                }
            }
            return (c1 + c2) / Double(n)
        }

        var theta = [0.0, 0.0, log(0.7 * Double(max(h, w)))]
        var ru = [Double](repeating: 0, count: 2 * n)
        var rl = [Double](repeating: 0, count: n)
        duSo(theta, &ru, &rl)
        var cost = chiPhi(ru, rl, true)
        var lam = 0.1
        var ju = Array(repeating: [Double](repeating: 0, count: 2*n), count: 3)
        var jl = Array(repeating: [Double](repeating: 0, count: n), count: 3)
        var tu = [Double](repeating: 0, count: 2*n)
        var tl = [Double](repeating: 0, count: n)
        for _ in 0..<SO_VONG {
            for p in 0..<3 {
                var t2 = theta; t2[p] += EPS
                duSo(t2, &tu, &tl)
                for q in 0..<(2*n) { ju[p][q] = (tu[q] - ru[q]) / EPS }
                for q in 0..<n { jl[p][q] = (tl[q] - rl[q]) / EPS }
            }
            var hm = Array(repeating: [Double](repeating: 0, count: 3), count: 3)
            var gr = [Double](repeating: 0, count: 3)
            for j in 0..<n {
                for a in 0..<3 {
                    let ax = ju[a][2*j], ay = ju[a][2*j+1], al = jl[a][j]
                    gr[a] += wu[j] * (ax * ru[2*j] + ay * ru[2*j+1]) + wl[j] * al * rl[j]
                    for b in a..<3 {
                        hm[a][b] += wu[j] * (ax * ju[b][2*j] + ay * ju[b][2*j+1]) + wl[j] * al * jl[b][j]
                    }
                }
            }
            for a in 0..<3 { for b in 0..<a { hm[a][b] = hm[b][a] } }
            var damped = hm
            for a in 0..<3 { damped[a][a] += lam * hm[a][a] + 1e-9 }
            guard let d = giaiHe3(damped, gr.map { -$0 }) else { break }
            let t2 = zip(theta, d).map { $0.0 + $0.1 }
            duSo(t2, &tu, &tl)
            let newCost = chiPhi(tu, tl, false)
            if newCost < cost {
                theta = t2; ru = tu; rl = tl
                cost = chiPhi(ru, rl, true)
                lam = max(lam / 10, 1e-6)
                if d.map({ abs($0) }).max()! < 1e-6 { break }
            } else {
                lam = min(lam * 10, 1e2)
            }
        }
        let vfov = 2 * atan(Double(h) / 2 / exp(theta[2]))
        return Camera(rollDeg: theta[0] * 180 / .pi,
                      pitchDeg: theta[1] * 180 / .pi,
                      vfovDeg: vfov * 180 / .pi)
    }

    private static func giaiHe3(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = (0..<3).map { [a[$0][0], a[$0][1], a[$0][2], b[$0]] }
        for c in 0..<3 {
            let pivot = (c..<3).max { abs(m[$0][c]) < abs(m[$1][c]) }!
            guard abs(m[pivot][c]) >= 1e-15 else { return nil }
            m.swapAt(c, pivot)
            for r in 0..<3 where r != c {
                let k = m[r][c] / m[c][c]
                for q in c..<4 { m[r][q] -= k * m[c][q] }
            }
        }
        return (0..<3).map { m[$0][3] / m[$0][$0] }
    }

    /// Sinh bản đồ có đáp án biết trước để kiểm thử solver độc lập với ONNX.
    static func banDoTuCamera(
        rollDeg: Double, pitchDeg: Double, vfovDeg: Double, h: Int, w: Int
    ) -> (up: [Float], viDo: [Float]) {
        let r = rollDeg * .pi / 180, p = pitchDeg * .pi / 180
        let f = Double(h) / 2 / tan(vfovDeg * .pi / 360)
        let g0 = -sin(r) * cos(p), g1 = -cos(r) * cos(p), g2 = sin(p)
        var up = [Float](repeating: 0, count: 2*h*w)
        var lat = [Float](repeating: 0, count: h*w)
        for y in 0..<h { for x in 0..<w {
            let u = (Double(x) - Double(w)/2) / f, v = (Double(y) - Double(h)/2) / f
            var ax = g0 - g2*u, ay = g1 - g2*v
            let mag = sqrt(ax*ax + ay*ay); ax /= mag; ay /= mag
            let i = y*w+x
            up[i] = Float(ax); up[h*w+i] = Float(ay)
            lat[i] = Float(asin((u*g0 + v*g1 + g2) / sqrt(u*u + v*v + 1)))
        }}
        return (up, lat)
    }
}
