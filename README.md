# CleanTube (iOS)

Ứng dụng iOS viết bằng **SwiftUI + WebKit** giúp xem YouTube gọn nhẹ với các tính năng:
- **Chặn quảng cáo** bằng `WKContentRuleList` chuẩn của Apple kết hợp bộ lọc giao diện.
- **Phát âm thanh khi tắt màn hình / chạy nền** (`UIBackgroundModes: audio`).
- **Thu nhỏ cửa sổ nổi (Picture-in-Picture / PiP)** chỉ với 1 chạm trên thanh công cụ.
- **Giao diện tối (Dark Mode)**, hỗ trợ kéo để làm mới và vuốt quay lại.

---

## Cách xuất ra file `CleanTube.ipa` miễn phí (không cần máy Mac)

Vì máy Windows không thể biên dịch trực tiếp file `.ipa`, project này đã tích hợp sẵn **GitHub Actions** (`.github/workflows/build-ipa.yml`) để build tự động trên máy Mac ảo miễn phí của GitHub.

### Bước 1: Tạo repository trên GitHub
1. Truy cập https://github.com/new và đăng nhập tài khoản GitHub (miễn phí).
2. Đặt tên repo là `CleanTube` (chọn **Public** hoặc **Private** đều được) rồi bấm **Create repository**.

### Bước 2: Đẩy mã nguồn lên GitHub
Mở PowerShell tại thư mục `CleanTube` và chạy:
```powershell
git init
git add .
git commit -m "Initial CleanTube iOS app"
git branch -M main
git remote add origin https://github.com/<TEN_TAI_KHOAN>/CleanTube.git
git push -u origin main
```

### Bước 3: Tải file `CleanTube.ipa`
1. Vào tab **Actions** trên repo GitHub của bạn.
2. Chọn workflow **Build Unsigned IPA** đang chạy (đợi khoảng 2–4 phút cho đến khi hiện dấu tích xanh).
3. Cuộn xuống mục **Artifacts**, bấm tải **CleanTube-IPA** về máy.
4. Giải nén file `.zip` vừa tải để lấy file **`CleanTube.ipa`**.

---

## Cách cài `CleanTube.ipa` lên iPhone

### Cách dùng Sideloadly (dễ nhất trên Windows)
1. Tải và cài **iTunes** (bản từ website Apple, không phải bản Microsoft Store) và **Sideloadly** trên Windows.
2. Cắm iPhone vào máy tính bằng cáp USB và bấm **Tin cậy máy tính này** trên iPhone.
3. Mở **Sideloadly**, kéo thả file `CleanTube.ipa` vào, nhập **Apple ID** của bạn rồi bấm **Start**.
4. Sau khi cài xong, trên iPhone mở:
   - **Cài đặt → Cài đặt chung → Quản lý VPN & Thiết bị** → chọn tài khoản Apple ID của bạn → bấm **Tin cậy (Trust)**.
   - Nếu dùng iOS 16+, bật **Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển (Developer Mode)** và khởi động lại máy.

> **Lưu ý:** Với Apple ID miễn phí, ứng dụng sideload có thời hạn 7 ngày và cần ký lại (hoặc cài qua **AltStore / SideStore** để tự động gia hạn qua Wi-Fi).
