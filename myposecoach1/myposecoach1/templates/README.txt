THU MUC ANH MAU CAI SAN TRONG APP
==================================

Tha file anh vao THU MUC NAY roi build lai la app tu co bo anh mau moi.

    app/app/src/main/assets/templates/

DINH DANG
---------
- Duoi file: .jpg  .jpeg  .png  .webp
- Ten file KHONG DAU tieng Viet, KHONG khoang trang.
  Dung gach ngang thay khoang trang: "co-gai-ao-trang.jpg"
- Ten file chinh la ten hien tren luoi chon anh mau
  ("co-gai-ao-trang.jpg"  ->  "co gai ao trang")

NHOM ANH MAU — DAT BANG TIEN TO TEN FILE
-----------------------------------------
Nhom quyet dinh CHE DO CHUP ma app tu bat khi ban chon anh do.

    selfie-<ten>.jpg   ->  Selfie        (camera TRUOC, cam tren tay)
    mirror-<ten>.jpg   ->  Mirror        (camera SAU chia vao GUONG)
    <ten>.jpg          ->  Photographer  (nguoi khac cam may)

Tien to bi cat khoi ten hien thi, nen "selfie-keo-co-ao.jpg" hien ra la
"keo co ao".

Hang loc o dau man hinh chi hien khi thu vien co tu HAI nhom tro len.

DAT NHOM SAI THI SAO?
- Anh guong ma khong co tien to "mirror-" -> app bat che do nguoi khac chup
  -> cau nhac ve tay chan se NHAM BEN (guong dao trai/phai).
- Van doi tay duoc bang hang nut tren man chup, nen khong phai loi chet nguoi.

NHAN GOC MAY — TU DAU TIEN SAU TIEN TO NHOM
--------------------------------------------
BAT BUOC CHO MOI ANH MAU (tu 16/09/2026). App KHONG TU SUY duoc may dat cao hay
thap tu anh: so doc tu khung xuong lan ca dang dung lan loai ong kinh (anh studio
chup thang doc ra nhu chup tu duoi len). Nguoi soan thu vien gan tay bang mot tu:

    tren   ->  may tren cao, chuc xuong      (vd: selfie-tren-tai-nghe.jpg)
    ngang  ->  may ngang tam                 (vd: selfie-ngang-keo-co-ao.jpg)
    duoi   ->  may thap, hat len             (vd: selfie-duoi-nen-troi-xanh.jpg)

Nhan bi cat khoi ten hien thi. Anh chup nguoi khac: nhan o DAU TEN
(vd: tren-kinh-ram.jpg, duoi-NGOI-ghe.jpg). Anh guong: mirror-ngang-....jpg
Khong gan nhan thi anh mau se KHONG co muc may cao/thap va ngua/chuc.

KIEU CHUP TU TREN CAO — TU THU HAI, CHI SAU "tren", CHI ANH NGUOI KHAC CHUP
------------------------------------------------------------------------
    gan   ->  dung gan, zoom 1x hoac 0.5x           (vd: tren-gan-kinh-ram.jpg)
    xa    ->  dung cho cao tu xa roi zoom           (vd: tren-xa-toc-hong.jpg)
Khong gan thi huong dan zoom/khoang cach dua ca hai lua chon "di bo hoac zoom".

SAU KHI THEM HOAC BO ANH — BAT BUOC LAM BUOC NAY
------------------------------------------------
Mo file:   app/app/src/main/java/com/example/posecoach/media/MediaLibrary.kt
Tim dong:  private const val SEED_MARKER = ".da-nap-anh-mau-v8"
Doi so cuoi:  v8 -> v9  (lan sau nua: v9 -> v10)

Khong doi so thi app CHI dung bo anh cu, vi no nho la "da nap roi".
Doi so xong, lan mo app ke tiep se:
  1. Xoa het anh mau CU do app cai san
  2. Chep bo MOI trong thu muc nay ra
  3. GIU NGUYEN anh nguoi dung tu chon tu may cua ho

CHON ANH THE NAO CHO APP DUNG DUOC
-----------------------------------
App phai NHIN THAY KHUNG XUONG trong anh thi moi dung lam mau duoc.
Anh khong dat se bi cong kiem tu choi ngay khi bam vao.

  - Nguoi chiem it nhat 1/4 chieu cao anh
  - Thay ro phan DAU (khong nhat thiet thay mat — doi mu, quay lung deu duoc)
  - Dang DUNG (ke ca tua tuong). Chua ho tro dang ngoi/nam
  - CHI MOT nguoi trong khung. Nhieu nguoi thi app chi bam mot nguoi
  - KHONG dung anh chup man hinh co giao dien app

ANH THAY DUOC CA CHAN thi tot hon han:
app chi kiem duoc zoom o anh toan than va anh ngang goi.
Anh chan dung khong kiem duoc zoom (xem FOOTGUNS muc 37).
