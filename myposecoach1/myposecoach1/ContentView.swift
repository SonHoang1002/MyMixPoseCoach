import SwiftUI

/// Màn hình hiện tại của app — cùng cấu trúc `sealed interface Screen` của
/// `MainActivity.kt` bên Android.
enum Screen: Equatable {
    /// Hai tab chính.
    case templates
    case library
    case capture(template: URL)
    case result(template: URL, sessionDir: URL)

    var isTab: Bool {
        switch self {
        case .templates, .library: return true
        default: return false
        }
    }
}

/// ĐIỂM VÀO GIAO DIỆN — port từ `AppRoot()` trong `MainActivity.kt`.
///
/// Hai tab chính nằm trong một cây (Home / Library + TabBar); màn chụp và màn
/// kết quả thay thế cả cây — đúng như Android, không có Navigation library.
struct ContentView: View {
    @State private var screen: Screen = .templates

    var body: some View {
        Group {
            switch screen {
            case .templates, .library:
                VStack(spacing: 0) {
                    Group {
                        if screen == .templates {
                            HomeScreen(onPickTemplate: { file in
                                screen = .capture(template: file)
                            })
                        } else {
                            LibraryScreen()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    TabBar(current: screen) { screen = $0 }
                }

            case .capture(let template):
                CaptureScreen(
                    templateFile: template,
                    onBack: { screen = .templates },
                    // Kết thúc phiên quay → màn xem lại 5 ảnh.
                    onFinished: { dir in
                        screen = .result(template: template, sessionDir: dir)
                    },
                    // Nút thư viện bên trái nút chụp. Sang thẳng tab Thư viện.
                    onOpenLibrary: { screen = .library }
                )

            case .result(let template, let sessionDir):
                ResultScreen(
                    templateFile: template,
                    sessionDir: sessionDir,
                    // HAI lối ra, khác nhau về ý định của người dùng:
                    //  - "Lưu hết & chụp tiếp" -> quay thẳng lại camera, giữ nguyên ảnh mẫu
                    //  - "Giữ ảnh này" / nút quay lại -> sang Thư viện xem thành quả
                    onDone: { continueShooting in
                        screen = continueShooting
                            ? .capture(template: template)
                            : .library
                    }
                )
            }
        }
        .posecoachTheme()
        #if DEBUG
        .onAppear(perform: tuDongVaoManChup)
        #endif
    }

    #if DEBUG
    /// VÀO MÀN CHỤP NGAY khi app mở — CHỈ để test tự động, không có trong bản
    /// Release. Bấm tay qua Cổng kiểm mất vài giây và không reproducc được lỗi
    /// console; lệnh chạy được nguyên màn vào màn chụp:
    ///
    ///     xcrun devicectl device process launch --device <udid> \
    ///         com.hts.myposecoach1 posecoach.autoEnterCapture
    /// (Không viết dấu `-` trước tên: `devicectl` nuốt mất argument bắt đầu
    /// bằng gạch.)
    private func tuDongVaoManChup() {
        guard CommandLine.arguments.contains(where: { $0.hasSuffix("posecoach.autoEnterCapture") }),
              screen == .templates,
              let dau = MediaLibrary.templates().first
        else { return }
        screen = .capture(template: dau.file)
    }
    #endif
}

/// THANH HAI TAB dưới đáy — chỉ thấy ở màn hình tab, không thấy ở màn chụp.
private struct TabBar: View {
    let current: Screen
    let onSelect: (Screen) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab("Ảnh mẫu", selected: current == .templates) {
                onSelect(.templates)
            }
            tab("Thư viện", selected: current == .library) {
                onSelect(.library)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Ds.surface)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Ds.surface)
    }

    private func tab(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: selected ? .bold : .regular))
                .foregroundColor(selected ? Ds.text : Ds.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
