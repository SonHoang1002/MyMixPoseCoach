import Foundation

/// Khoá dùng chung cho việc TẠO và HUỶ bộ nhận diện MediaPipe.
///
/// ⚠️ BẮT BUỘC. Xem FOOTGUNS.md mục 17.
///
/// Tạo một bộ nhận diện là dựng cả một đồ thị xử lý ở tầng C++ và ánh xạ file model
/// vào bộ nhớ. Làm việc đó **đồng thời từ nhiều luồng** khiến app sập bằng SIGBUS
/// ngay trong `Graph.nativeStartRunningGraph` — không có ngoại lệ nào, app chỉ tắt ngóm.
///
/// Màn camera vốn tạo HAI bộ cùng lúc (một cho ảnh mẫu, một cho video), nên chuyện
/// này không hiếm mà xảy ra ở mọi lần mở màn.
///
/// Khoá này **chỉ bọc lúc tạo và huỷ**, không bọc lúc chạy nhận diện — nếu bọc cả
/// lúc chạy thì camera sẽ phải đợi ảnh mẫu phân tích xong, gây giật.
nonisolated final class MediaPipeGuard {
    static let shared = MediaPipeGuard()

    private let lock = NSLock()

    func serialized<T>(_ block: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block()
    }
}
