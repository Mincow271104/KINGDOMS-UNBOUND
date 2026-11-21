# KINGDOMS UNBOUND — Hướng Dẫn Kiểm Thử & Manual Smoke-Test Checklist

Tài liệu này cung cấp hướng dẫn từng bước dành cho người chơi và kiểm thử viên (không yêu cầu kiến thức lập trình) để xác minh toàn bộ các tính năng cốt lõi của KINGDOMS UNBOUND.

---

## 1. Khởi Động & Menu Chính (Main Menu)

### 1.1 Khởi Động Trò Chơi
- **Lệnh chạy:**
  ```powershell
  & "E:\GODOT ENGINE\Godot_v4.7-stable_win64.exe" --path "E:\KINGDOMS UNBOUND\kingdoms-unbound"
  ```
- **Kỳ vọng:** Màn hình chính mở lên mượt mà với tiêu đề **KINGDOMS UNBOUND**, phụ đề đồ họa pixel art 2D isometric, và các nút tùy chọn tiếng Việt:
  - `Thế Giới Mới`
  - `📂 Tải Thế Giới` (Sáng lên nếu đã có bản lưu trước đó, hoặc xám nếu chưa có)
  - `Cài Đặt`
  - `Thoát`

### 1.2 Tạo Thế Giới Mới (New World)
1. Nhấn nút **Thế Giới Mới**.
2. Một hộp thoại xuất hiện:
   - **Tên thế giới:** Đặt tên bất kỳ (mặc định: `Đại Việt Thịnh Vượng`).
   - **Hạt giống (Seed):** Nhập số nguyên tùy ý (hoặc nhấn nút `🎲 Hạt Giống Ngẫu Nhiên`).
   - **Độ khó:** Chọn giữa 3 mức: *Dễ*, *Tiêu Chuẩn (GDD v1.0)*, hoặc *Thử Thách*.
3. Nhấn **Bắt Đầu Xây Dựng**.
- **Kỳ vọng:** Trò chơi tải thế giới isometric 64×64 dạng lưới kim cương 32×16 px, camera tự động tập trung vào khu vực quảng trường trung tâm.

---

## 2. Phím Tắt & Thao Tác Điều Khiển (Controls)

| Phím / Thao Tác | Hành Động | Kết Quả Kỳ Vọng |
|---|---|---|
| `W`, `A`, `S`, `D` hoặc Phím Mũi Tên | Di chuyển góc nhìn (Camera Pan) | Camera lướt mượt mà quanh bản đồ, bị giới hạn tại biên bản đồ 64×64 |
| `Cuộn Chuột (Scroll Wheel)` | Thu phóng (Zoom) | Phóng to / thu nhỏ góc nhìn mượt mà |
| `Chuột Trái (Left Click)` vào ô đất | Chọn ô / Kiểm tra thông tin | Thanh đáy hiển thị tọa độ ô, loại địa hình và công trình |
| `Chuột Trái (Left Click)` vào Cư dân | Mở bảng thông tin cư dân | Bảng điều tra cư dân mở ra bên phải hiển thị tên, vai trò, công việc, chỉ số (Đói, Mệt, Máu, Tinh thần) |
| `Chuột Trái (Left Click)` khi đang chọn xây | Đặt công trình | Công trình được dựng lên với hiệu ứng âm thanh đóng búa thỏa mãn |
| `Chuột Phải (Right Click)` | Hủy lệnh xây dựng | Hủy bóng mờ công trình, quay lại chế độ bình thường |
| `Space` | Tạm dừng / Tiếp tục | Đồng hồ dừng/chạy, cư dân dừng di chuyển an toàn |
| `1`, `2`, `3` | Tốc độ mô phỏng 1×, 2×, 3× | Thời gian trôi theo đúng cấp độ nhân |
| `Esc` | Bật / Tắt Menu Tạm Dừng (Pause Menu) | Mở menu tạm dừng với các tùy chọn Lưu / Tải / Cài đặt |
| `T` | Mở Viện Nghiên Cứu Hoàng Gia | Bảng cây công nghệ 4 nhánh mở ra |
| `Y` | Mở Ngoại Giao & Giao Thương | Bảng quan hệ bang giao và thương đoàn mở ra |

---

## 3. Vòng Lặp Xây Dựng & Kinh Tế (City Building & Logistics)

1. **Khởi đầu vương quốc:**
   - Vương quốc bắt đầu với: 1 Tòa Thị Chính (3×3), 4 Nhà Dân (2×2), 1 Trang Trại (2×2), 1 Kho Thóc (2×2), 1 Trại Đốn Gỗ (2×2).
   - Dân số khởi đầu: **24 cư dân** (5 Nông dân, 4 Tiều phu, 3 Thợ xây, 3 Người vận chuyển, 9 Dân tự do).
2. **Xây dựng thêm công trình:**
   - Nhấn nút **Xây Dựng** trên thanh công cụ HUD.
   - Chọn một công trình (ví dụ: `Nhà Ở`, `Trại Đốn Gỗ`, `Kho Thóc`, `Viện Nghiên Cứu`).
   - Di chuyển chuột trên bản đồ:
     - Ô hợp lệ: Khung bóng mờ hiển thị **màu xanh lá**.
     - Ô bị chặn (dưới nước, vướng công trình khác, hoặc thiếu tài nguyên): Khung bóng mờ hiển thị **màu đỏ**.
   - Nhấn Chuột Trái để hoàn tất xây dựng. Tài nguyên được khấu trừ 1 lần duy nhất một cách nguyên tử.
3. **Chu trình vận chuyển vật lý (Physical Hauling):**
   - Quan sát Nông trại và Trại đốn gỗ: Khi đầy hàng trong kho đệm, người vận chuyển (Hauler) sẽ đi bộ từ kho đệm về Kho Thóc hoặc Tòa Thị Chính. Hàng hóa không bao giờ dịch chuyển tức thời.

---

## 4. Nghiên Cứu, Khám Phá & Sự Kiện (Research & Exploration)

1. **Viện Nghiên Cứu Hoàng Gia (Phím `T`):**
   - Mở giao diện nghiên cứu, quan sát 4 nhánh công nghệ: *Nông Nghiệp*, *Khai Khoáng*, *Quân Sự*, *Hành Chính*.
   - Nhấn **Nghiên Cứu** một công nghệ khả dụng (ví dụ: *Nông Nghiệp Thủy Lợi*). Điểm nghiên cứu sẽ tăng dần mỗi giờ.
2. **Sương mù chiến tranh (Fog of War) & Điểm Khám Phá (POI):**
   - Khi cư dân di chuyển, vùng sương mù xung quanh tự động sáng lên.
   - Khi cư dân tiếp cận các tàn tích bí ẩn (Cổ Tháp, Hang Khoáng Sản), phần thưởng khám phá (Vàng, Công nghệ, Tài nguyên) sẽ được trao 1 lần duy nhất.
3. **Sự kiện ngẫu nhiên:**
   - Các sự kiện thời tiết, lễ hội hoặc biến cố sẽ hiển thị banner thông báo trên đỉnh màn hình với các hiệu ứng thay đổi tài nguyên rõ ràng.

---

## 5. Ngoại Giao & Thương Mại (Diplomacy & Trade)

1. **Bảng Ngoại Giao (Phím `Y`):**
   - Quan sát 3 phe phái:
     - `Cổ Thành Thiết Giáp` (Quân phiệt phương Bắc, Thái độ: Trung lập)
     - `Thương Hội Vân Đồn` (Thương đoàn phương Nam, Thái độ: Thân thiện)
     - `Bản Làng Rừng Xanh` (Bộ tộc bản địa, Thái độ: Trung lập)
   - Thử gửi Quà Tặng Hoàng Gia để gia tăng thiện cảm (+15 điểm).
2. **Thương Đoàn Hoàng Gia (Royal Trade Caravan):**
   - Thương đoàn định kỳ ghé thăm mỗi 5 ngày.
   - Có thể mua lương thực, gỗ, đá, công cụ bằng vàng hoặc bán tài nguyên dư thừa. Giao dịch diễn ra nguyên tử, không thể phát sinh trùng lặp.

---

## 6. Điều Kiện Thắng (Victory) & Sụp Đổ (Collapse)

1. **Chiến Thắng Thịnh Vượng (Prosperity Victory):**
   - Đạt đủ các tiêu chí: Dân số $\ge 30$, Lương thực $\ge 500$, Ngân khố $\ge 1000$, Ổn định $\ge 80\%$, Tinh thần $\ge 75\%$, Công nghệ $\ge 3$.
   - Giữ vững toàn bộ tiêu chí liên tục trong **5 ngày (120 giờ)**.
   - Khi đếm đủ 120 giờ: Hộp thoại **👑 CHIẾN THẮNG THỊNH VƯỢNG!** xuất hiện với âm thanh khải hoàn và bảng thống kê tổng kết.
2. **Kịch Bản Sụp Đổ (Collapse):**
   - Nếu toàn bộ cư dân chết đói (Dân số = 0), hoặc Tòa Thị Chính bị phá hủy quá 3 ngày: Hộp thoại **💀 VƯƠNG QUỐC SỤP ĐỔ!** xuất hiện giải thích nguyên nhân rõ ràng.
   - *Lưu ý:* Bản lưu không bị xóa, người chơi có thể tải lại hoặc tiếp tục quan sát.

---

## 7. Lưu & Tải Trò Chơi (Save & Load)

1. **Lưu Thủ Công:**
   - Nhấn `Esc` mở Menu Tạm Dừng $\to$ Nhấn **💾 Lưu Thế Giới**.
   - Thông báo xanh xuất hiện: `✅ Đã lưu thế giới thành công!`.
2. **Tự Động Lưu (Autosave):**
   - Mỗi khi qua nửa đêm (00:00), hệ thống tự động lưu vào đĩa an toàn với thông báo `Tự Động Lưu (Ngày X)`.
3. **Tải Lại Trong Game:**
   - Nhấn `Esc` $\to$ Nhấn **📂 Tải Bản Lưu**.
   - Thế giới được khôi phục nguyên vẹn 100% (tài nguyên, công trình, vị trí và công việc cư dân, công nghệ, sương mù).
4. **Tải Từ Menu Chính:**
   - Thoát về Menu Chính $\to$ Nhấn **📂 Tải Thế Giới**.
   - Game tải lại bản lưu gần nhất và tiếp tục chơi mượt mà.

---

## 8. Hướng Dẫn Đóng Gói Bản Phát Hành (Windows Release Export)

### Xuất Bản Bằng Dòng Lệnh:
```powershell
# Tạo thư mục đầu ra
New-Item -ItemType Directory -Force -Path "build"

# Đóng gói bản Release x64 cho Windows
& "E:\GODOT ENGINE\Godot_v4.7-stable_win64_console.exe" --headless --export-release "Windows Desktop" build/KingdomsUnbound.exe
```

*Ghi chú môi trường:* Cấu hình xuất bản đã được chuẩn hóa tại `export_presets.cfg`. Nếu máy tính chưa tải gói `export_templates` của Godot 4.7, người dùng có thể tải thông qua Godot GUI: `Menu Quản Lý` $\to$ `Quản lý Export Templates` $\to$ `Tải về và cài đặt`. Game có thể khởi chạy trực tiếp đầy đủ 100% tính năng bằng lệnh `Godot_v4.7-stable_win64.exe --path "E:\KINGDOMS UNBOUND\kingdoms-unbound"`.

---

## 9. RC2 Live Gameplay Acceptance Checklist (Packages 2F, 2G, 2H, 2I)

Phiên kiểm thử thực chiến (Live Acceptance Run) kéo dài 35 ngày mô phỏng trong trò chơi với hạt giống cố định `12345` (Độ khó Tiêu chuẩn GDD v1.0, Thế giới `RC2_Acceptance_Realm`):

| Hạng mục kiểm thử | Thao tác thực chiến | Kết quả ghi nhận thực tế | Trạng thái |
|---|---|---|:---:|
| **Khởi Động & Sinh Thế Giới** | Nhập seed `12345`, tên thế giới `RC2_Acceptance_Realm`, độ khó Tiêu chuẩn | Thế giới isometric 64×64 kết xuất hoàn hảo, 24 cư dân khởi đầu (5 Nông dân, 4 Tiều phu, 3 Thợ xây, 3 Vận chuyển, 9 Nhàn rỗi), camera định vị chính xác tại quảng trường `(32, 32)` | **PASS** |
| **Package 2F: Điều Tra Công Trình & Nơi Làm Việc** | Chọn Nhà Ở (26, 25), Nông Trại (36, 35), Kho Lương (36, 30); mở Building Inspector | Hiển thị chính xác tên tiếng Việt, tọa độ, kích thước, thanh máu (100 HP), cấp độ Cấp 1/3. Nông trại hiển thị kho đệm 50/50 Lương thực, trạng thái bão hòa, danh sách 5 nông dân | **PASS** |
| **Package 2F: Tái Phân Bổ Việc Làm & Phá Dỡ An Toàn** | Đổi việc citizen_1 từ nông dân sang tiều phu; xây Tường rào (40, 40) rồi phá dỡ | Cư dân chuyển đổi vai trò ngay lập tức. Phá dỡ tường rào hoàn trả đúng 50% nguyên vật liệu (`2 Gỗ, 1 Đá`), bảo tồn toàn bộ công trình, việc làm và tài nguyên khác | **PASS** |
| **Package 2I: Nâng Cấp Nhà Ở Cấp 1 $\to$ 2** | Kiểm tra chi phí (`19 Gỗ, 8 Đá`, thời gian 4.0h); bấm Nâng cấp qua HUD | Thợ xây nhận việc, lao động thực tế. Sức chứa nhà ở tăng từ 6 lên 8 (tổng sức chứa định cư từ 24 lên 26). Không tồn tại job rác sau hoàn tất | **PASS** |
| **Package 2I: Nâng Cấp Nông Trại Cấp 1 $\to$ 2** | Kiểm tra chi phí (`23 Gỗ, 4 Đá`, thời gian 5.0h); thợ xây thi công hoàn tất | Hệ số sản lượng nông trại tăng từ `1.00×` lên chính xác `1.15×`. Nông dân tiếp tục làm việc bình thường | **PASS** |
| **Package 2I: Nâng Cấp Kho Lương Cấp 1 $\to$ 2** | Kiểm tra chi phí (`30 Gỗ, 19 Đá`, thời gian 6.0h); thi công hoàn tất | Sức chứa kho tăng chuẩn xác: Lương thực/Gỗ/Đá tăng $+125$ (1500 $\to$ 1625), Quặng/Kim loại tăng $+75$ (900 $\to$ 975) | **PASS** |
| **Package 2I & Save/Load: Giữ Tiến Độ Nâng Cấp** | Lưu game khi nâng cấp đang diễn ra, tải lại qua SaveManager, hoàn tất sau tải | Tiến độ, chi phí, cấp mục tiêu được bảo lưu nguyên vẹn; job thợ xây khôi phục chuẩn xác, không trùng lặp, không trôi dung lượng | **PASS** |
| **Package 2H: Định Giá Thị Trường Động** | Quan sát thương đoàn ngày 28 và ngày 33; kiểm tra báo giá Mua/Bán theo cung-cầu | Báo giá hiển thị chi tiết độ co giãn (áp lực địa phương vs thương đoàn). Bán 10 Gỗ giá 2 Vàng/đơn vị; Mua 10 Đá giá 4 Vàng/đơn vị. Giao dịch nguyên tử, khớp báo giá, cập nhật độ co giãn sau giao dịch | **PASS** |
| **Package 2G: Kiểm Soát Lãnh Thổ & Tiền Đồn** | Khảo sát 3 tiền đồn trên bản đồ (`outpost_neutral_tribe`, `outpost_rival_merchant`, `outpost_rival_military`) | Hiển thị cờ, máu (200-300 HP), đồn trú (2-4 lính). Chiếm đóng thực tế trong 15-35 ngày: **CHƯA ĐẠT (NOT VERIFIED)** do yêu cầu xây Doanh trại, tuyển đại quân, hành quân viễn chinh và tuyên chiến toàn diện | **NOT VERIFIED (Documented)** |
| **Kinh Tế & Vòng Lặp Sinh Tồn (35 Ngày)** | Vận hành qua Xuân, Hạ, Thu, Đông; kiểm tra tiêu thụ lương thực, nhập cư | Dân số tăng lên 26 người (nhập cư thành công), 0 người chết, kho lương dồi dào (699 đơn vị), không bao giờ có tài nguyên âm hay rò rỉ dung lượng | **PASS** |

