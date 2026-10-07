//
//  myposecoach1App.swift
//  myposecoach1
//
//  Created by sonmac on 6/10/26.
//

import SwiftUI

@main
struct myposecoach1App: App {
    init() {
        // Dọn rác của lần chạy trước. Phải gọi lúc MỞ app: lúc đóng thì app đã bị
        // hệ điều hành giết, code dọn không bao giờ chạy tới — đó chính là tình
        // huống sinh ra rác (xem `ShotStore`).
        ShotStore.sweepOrphans()
        ShotStore.sweepRecordings()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
