import SwiftUI
import UIKit

/// THƯ VIỆN — mọi ảnh đã lọc, xem lại bất cứ lúc nào.
///
/// ⚠️ Ở đây chỉ có **ảnh kết quả**. Video thô và loạt ảnh gốc đã bị xoá ngay sau
/// khi lọc xong (xem `ResultLibrary.saveSession`) — đó là luật cứng, vì một đoạn
/// 30 giây Full HD nặng 60-100 MB và chỉ cần quên vài lần là máy người dùng đầy.
///
/// Port 1:1 từ `library/LibraryScreen.kt` — gồm cả màn xem album chi tiết
/// (bản Android đặt ngay trong file này dưới tên `AlbumViewer`).
struct LibraryScreen: View {

    @State private var albums: [ResultLibrary.Album] = []
    /// Ảnh thu nhỏ của TỪNG album, khoá theo tên thư mục — bản Android khoá theo
    /// `dir.name`, iOS tương ứng là `dir.lastPathComponent`.
    @State private var thumbs: [String: UIImage] = [:]
    @State private var open: ResultLibrary.Album? = nil
    @State private var confirmDelete: ResultLibrary.Album? = nil
    /// Tăng lên mỗi lần xoá xong để `LaunchedEffect`-tương đương nạp lại danh sách.
    @State private var reload = 0

    init() {}

    var body: some View {
        // Chụp lại TRƯỚC khi mở hộp thoại: SwiftUI có thể đặt `confirmDelete = nil`
        // trước khi bấm nút chạy, khi đó đọc state trực tiếp sẽ ra `nil` và lệnh
        // xoá bị bỏ qua âm thầm.
        let pendingDelete = confirmDelete

        ZStack {
            if albums.isEmpty {
                LibraryEmptyState()
            } else {
                LibraryGrid(
                    albums: albums,
                    thumbs: thumbs,
                    onOpen: { open = $0 }
                )
            }

            if let album = open {
                LibraryAlbumViewer(
                    album: album,
                    onDelete: { confirmDelete = album; open = nil },
                    onClose: { open = nil },
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Ds.bg.ignoresSafeArea() }
        // Tương đương `LaunchedEffect(reload)` bên Android: chạy lúc hiện màn và mỗi
        // lần số `reload` đổi (tức là sau mỗi lần xoá album).
        .task(id: reload) {
            await loadAlbums()
        }
        // Xác nhận xoá — đúng hai nút và đúng chữ của `AlertDialog` bên Android.
        .alert(
            "Xoá cả buổi chụp này?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("Xoá") {
                if let pendingDelete { ResultLibrary.delete(pendingDelete) }
                confirmDelete = nil
                reload += 1
            }
            Button("Giữ lại", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("\(pendingDelete?.count ?? 0) ảnh sẽ bị xoá hẳn, không lấy lại được.")
        }
    }

    /// Nạp danh sách album + ảnh thu nhỏ, **cả hai đều ngoài main thread**.
    ///
    /// Mạng lưới có thể tới vài chục album, mỗi album một lần giải mã ảnh — đặt lên
    /// main là lista giao diện trong lúc cuộn.
    private func loadAlbums() async {
        let list = await Task.detached(priority: .userInitiated) {
            ResultLibrary.albums()
        }.value
        albums = list

        let decoded = await Task.detached(priority: .userInitiated) { () -> [String: UIImage] in
            var out: [String: UIImage] = [:]
            for album in list {
                guard let first = album.photos.first,
                      let img = UprightBitmap.decode(file: first, shortSide: 400) else { continue }
                out[album.dir.lastPathComponent] = img
            }
            return out
        }.value
        thumbs = decoded
    }
}

// MARK: - Lưới album

/// Lưới 2 cột các buổi chụp — mỗi ô là ảnh đầu tiên của album + số lượng + ngày.
private struct LibraryGrid: View {
    let albums: [ResultLibrary.Album]
    let thumbs: [String: UIImage]
    let onOpen: (ResultLibrary.Album) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(albums, id: \.dir) { album in
                    LibraryAlbumCell(
                        album: album,
                        thumb: thumbs[album.dir.lastPathComponent],
                        onTap: { onOpen(album) }
                    )
                }
            }
            .padding(12)
        }
    }
}

/// Một ô trong lưới album.
private struct LibraryAlbumCell: View {
    let album: ResultLibrary.Album
    let thumb: UIImage?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Color.black)
                    // Ô phải LẤP ĐẦY bề ngang cột lưới, nếu không `LazyVGrid` đo chiều
                    // rộng cột theo nội dung từng ô và các ô lệch nhau. Tương đương
                    // `Modifier.fillMaxWidth()` của `LibraryScreen.kt` bên Android.
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay {
                        if let thumb {
                            // Crop như `ContentScale.Crop` bên Android: lấp khung,
                            // cắt phần thừa.
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipped()

                Text("\(album.count) ảnh")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(hex: 0xCC000000))
                    .clipShape(Capsule())
                    .padding(6)
            }

            Text(libraryTimeText(album.createdAtMs))
                .font(.system(size: 11))
                .foregroundColor(Ds.textMuted)
                .padding(8)
        }
        .background(Ds.surface)
        .clipShape(RoundedRectangle(cornerRadius: Ds.rSmall))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Màn xem album chi tiết

/// Xem cả một buổi chụp — bản Android là `AlbumViewer`, một `AlertDialog` lưới 2
/// cột cố định cao 420dp.
private struct LibraryAlbumViewer: View {
    let album: ResultLibrary.Album
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var photos: [UIImage] = []

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 12) {
                Text("\(album.count) ảnh — \(libraryTimeText(album.createdAtMs))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Ds.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { _, img in
                            Rectangle()
                                .fill(Color.black)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(0.75, contentMode: .fit)
                                .overlay {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: Ds.rSmall))
                        }
                    }
                }
                // Cao cố định như `Modifier.height(420.dp)` bên Android — hộp thoại
                // không được dài ra vô tận trên máy nhỏ.
                .frame(height: 420)

                HStack(spacing: 16) {
                    Button(action: onDelete) {
                        Text("Xoá buổi này")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Ds.text)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Text("Đóng")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Ds.primary)
                    }
                }
            }
            .padding(16)
            .background(Ds.surface)
            .clipShape(RoundedRectangle(cornerRadius: Ds.rCard))
            .padding(.horizontal, 24)
            .frame(maxWidth: 460)
        }
        // Ảnh trong album cũng giải mã ngoài main thread, cỡ 1080 như bản Android
        // (`decodeThumb(file, 1080)`): đủ nét để xem lại, không nạp ảnh gốc.
        .task(id: album.dir) {
            let urls = album.photos
            let decoded = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
                urls.compactMap { UprightBitmap.decode(file: $0, shortSide: 1080) }
            }.value
            photos = decoded
        }
    }
}

// MARK: - Trạng thái rỗng

private struct LibraryEmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Thư viện còn trống")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Ds.text)
            Text("Chụp xong một lần là ảnh đã lọc sẽ nằm ở đây")
                .font(.system(size: 13))
                .foregroundColor(Ds.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tiện ích

/// Ngày giờ của album — đúng định dạng `dd/MM HH:mm` của bản Android.
///
/// `en_US_POSIX` thay `Locale.US`: cùng kết quả, nhưng không phụ thuộc ngôn ngữ
/// máy — đúng bài học của bảng kê CSV trong `ShotStore` (máy tiếng Việt đổi dấu
/// thập phân của `%f` thành dấu phẩy).
private func libraryTimeText(_ ms: Int64) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "dd/MM HH:mm"
    return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
}
