# KINGDOMS UNBOUND
## GAME DESIGN DOCUMENT & TECHNICAL IMPLEMENTATION SPECIFICATION
**Version:** 1.0 — MVP Development Blueprint  
**Genre:** 2D Isometric / Dimetric Pixel Art Kingdom Simulation / Colony Management (Three-Quarter Top-Down Perspective, NOT Flat Overhead)  
**Target:** PC, single-player, offline-first  
**Primary language of design:** Vietnamese  
**Recommended engine:** Godot 4.x, 2D, GDScript  
**Development method:** AI-assisted vibe coding, incremental implementation and automated testing

---

# PHẦN I — TẦM NHÌN SẢN PHẨM

## 1.1. Ý tưởng cốt lõi

Xây dựng một game mô phỏng vương quốc bằng đồ họa 2D pixel art với góc nhìn 2D isometric / dimetric 2:1 (three-quarter top-down), tuyệt đối KHÔNG sử dụng góc nhìn phẳng thẳng đứng từ trên xuống (flat overhead 90°). Phong cách thị giác bám sát hình ảnh chuẩn tham chiếu (`docs/reference/kingdom_visual_reference.png`):
- Các ô đất có hình thoi (diamond-shaped ground tiles).
- Các công trình thể hiện rõ mặt mái nghiêng và các mặt tường tiền diện (front-facing facades hướng Tây Nam và Đông Nam).
- Phối cảnh 3/4 đồng bộ tuyệt đối trên toàn bộ thế giới: nhà cửa, cây cối, đá tài nguyên, tường thành và cư dân.
- Phân tầng chiều sâu theo trục Y (depth/Y-sorting) chính xác để các đối tượng tự nhiên che khuất hoặc hiển thị phía trước/phía sau nhau khi di chuyển.
- Đồ họa pixel art sắc nét với bộ lọc phóng đại Nearest-Neighbor và tỉ lệ kích thước cân đối, hài hòa.

Người chơi bắt đầu với một khu định cư nhỏ, một nhóm dân cư và lượng tài nguyên hạn chế. Qua quá trình quản lý, người chơi phát triển kinh tế, xây dựng công trình, nghiên cứu công nghệ, khám phá bản đồ, thiết lập quan hệ với các thế lực khác và bảo vệ vương quốc khỏi khủng hoảng.

Điểm khác biệt chính của game là sự kết hợp giữa:

1. Mô phỏng dân cư có nhu cầu, đặc điểm, kỹ năng và vòng đời đơn giản.
2. Quản lý kinh tế và chuỗi sản xuất có nguyên nhân, kết quả rõ ràng.
3. Hệ thống tự động hóa cho phép người chơi tạo quy tắc điều hành dân cư.
4. Thế giới hữu hạn được tạo ngẫu nhiên, có tài nguyên và thế lực phát triển theo thời gian.
5. Nhiều con đường chiến thắng, cùng nguy cơ suy thoái và sụp đổ.
6. Tiến trình giữa các thế giới thông qua Legacy Fund, chỉ dùng cho nội dung trang trí.

Game phải tạo được cảm giác rằng mỗi vương quốc là một câu chuyện riêng. Một trận hạn hán có thể khiến người chơi thay đổi kế hoạch sản xuất; một mỏ mới có thể thúc đẩy nghiên cứu; một đồng minh có thể giúp vương quốc sống sót sau chiến tranh.

## 1.2. Trải nghiệm người chơi mong muốn

Người chơi phải có thể:

- Nhìn vào bản đồ và hiểu tình hình vương quốc.
- Quan sát dân cư làm việc, di chuyển và phản ứng với môi trường.
- Giao việc trực tiếp hoặc để hệ thống tự động hóa xử lý.
- Nhìn thấy tác động của các quyết định lên sản xuất, tài nguyên và tinh thần.
- Khám phá các địa điểm mới để mở khóa cơ hội.
- Đối mặt với khủng hoảng nhưng có cơ hội phục hồi.
- Xây dựng một vương quốc thịnh vượng, thống trị quân sự hoặc thành công bằng ngoại giao trong phiên bản đầy đủ.
- Lưu, tải và tiếp tục thế giới mà không mất hoặc nhân đôi tiến trình.

## 1.3. Nguyên tắc thiết kế

**Nguyên tắc 1 — Hệ thống phải có quan hệ nhân quả.**  
Nếu dân không sản xuất được thức ăn, giao diện phải cho biết nguyên nhân. Không được tạo ra thất bại không thể giải thích.

**Nguyên tắc 2 — Tự động hóa là một tính năng gameplay thật.**  
Dân phải thực thi quy tắc đã thiết lập, không chỉ hiển thị menu trang trí.

**Nguyên tắc 3 — Không tạo tài nguyên vô hạn từ hư không.**  
Mọi hoạt động kinh tế phải có nguồn vào, đầu ra, thời gian hoặc chi phí phù hợp.

**Nguyên tắc 4 — Mỗi quyết định quan trọng có đánh đổi.**  
Xây công trình, nghiên cứu, tuyển quân và giao dịch phải cạnh tranh nguồn lực.

**Nguyên tắc 5 — Prototype ưu tiên hoàn chỉnh hơn số lượng tính năng.**  
Một hệ thống đơn giản nhưng chơi được tốt hơn nhiều hệ thống chỉ có giao diện.

**Nguyên tắc 6 — Hiệu năng là yêu cầu thiết kế ngay từ đầu.**  
Không cập nhật mọi hệ thống ở mọi khung hình nếu không cần thiết.

---

# PHẦN II — PHẠM VI MVP

## 2.1. MVP là gì?

MVP là phiên bản nhỏ nhất nhưng có thể chơi hoàn chỉnh từ lúc tạo thế giới đến lúc chiến thắng hoặc sụp đổ.

MVP không phải bản demo chỉ có nhân vật di chuyển và giao diện tài nguyên.

### Các tính năng bắt buộc

1. Tạo bản đồ hữu hạn 64 × 64 ô.
2. Sinh địa hình, cây, đá, mỏ và các địa điểm khám phá.
3. Hiển thị bản đồ 2D isometric / dimetric pixel art với lưới ô hình thoi (diamond tiles), phân tầng chiều sâu (Y-sorting) chính xác, và công trình thể hiện rõ mặt mái cùng mặt tiền.
4. Quản lý 24 dân cư ban đầu.
5. Có hệ thống tài nguyên, sản xuất, tiêu thụ và kho chứa.
6. Có ít nhất 10 công trình cốt lõi.
7. Dân cư có thể di chuyển và thực hiện công việc thực tế.
8. Có giao việc thủ công và tự động hóa cơ bản.
9. Có hệ thống ngày, mùa, tốc độ game và tạm dừng.
10. Có cây công nghệ nhỏ.
11. Có khám phá và sự kiện thế giới.
12. Có thương nhân hoặc giao dịch đơn giản.
13. Có hai vương quốc đối thủ và một khu định cư trung lập.
14. Có mô phỏng chiến đấu đơn giản.
15. Có trạng thái khủng hoảng, suy thoái và sụp đổ.
16. Có điều kiện chiến thắng thịnh vượng.
17. Có lưu game và tải game.
18. Có màn hình tổng kết thế giới.
19. Có kiểm thử tự động cho các hệ thống quan trọng.
20. Có thể chơi hoàn chỉnh mà không cần kết nối dịch vụ AI bên ngoài.

## 2.2. Các tính năng chưa làm trong MVP

Không triển khai các tính năng sau cho đến khi vòng chơi cốt lõi hoạt động ổn định:

- Di truyền nhiều gene và mô phỏng sinh học phức tạp.
- Nhiều chủng tộc với hàng loạt thuộc tính riêng.
- Điều khiển chiến đấu từng binh sĩ.
- Chiến thuật đội hình nâng cao.
- Mạng lưới gián điệp nhiều tầng.
- AI tạo sinh điều khiển thế giới.
- Chế độ multiplayer.
- Hệ thống mod.
- Bản đồ vô hạn.
- Hệ thống kinh tế toàn cầu quá chi tiết.
- Hàng trăm công trình và công nghệ.
- Cửa hàng mỹ phẩm Legacy hoàn chỉnh.

Có thể chuẩn bị kiến trúc mở rộng, nhưng không được xây những hệ thống này trước khi MVP hoàn thành.

---

# PHẦN III — THẾ GIỚI VÀ BẢN ĐỒ

## 3.1. Quy mô bản đồ và Hệ thống chiếu hình Isometric

### Tách biệt giữa Lưới Logic và Hình chiếu Render
Game duy trì sự phân tách nghiêm ngặt giữa hai không gian tọa độ:
1. **Lưới Logic (Logical Simulation Grid):**
   - Kích thước cố định: **64 × 64 ô** (tọa độ nguyên `Vector2i(grid_x, grid_y)` với `0 <= grid_x, grid_y < 64`).
   - Toàn bộ thuật toán mô phỏng (A* pathfinding, khoảng cách di chuyển, kiểm tra chiếm dụng ô xây dựng, bán kính kho bãi, khai thác tài nguyên) hoạt động hoàn toàn trên lưới logic này.
   - Logic mô phỏng hoàn toàn không phụ thuộc vào pixel màn hình hay tỉ lệ thu phóng camera.
2. **Hình chiếu Hiển thị (Rendered Screen Projection):**
   - Sử dụng phối cảnh **2D Isometric / Dimetric tỉ lệ 2:1** (ba phần tư từ trên xuống — three-quarter top-down view; tuyệt đối không dùng flat overhead 90°).
   - Mỗi ô mặt đất được chiếu thành một **hình thoi (diamond tile)** có tỉ lệ cạnh bước 2 pixel ngang trên 1 pixel dọc (góc nghiêng trục xấp xỉ 26.565°).

### Đánh giá và Lựa chọn Kích thước Diamond Tile (32 × 16 pixel)
Ban đầu, mức tile cơ bản xung quanh 32 × 16 pixel được đánh giá kỹ lưỡng so với các phương án khả thi:
- **So với 16 × 8 pixel:** Một ô thoi 16 × 8 pixel chỉ có diện tích 64 px², quá chật hẹp để vẽ chất liệu địa hình (cỏ, đất xới, đá cuội, mặt nước) mà vẫn giữ được độ sắc nét và cái hồn pixel art. Nhân vật và chi tiết sẽ bị thu nhỏ quá mức hoặc dính răng cưa dày đặc.
- **So với 64 × 32 pixel:** Một ô thoi 64 × 32 pixel có diện tích gấp 4 lần (1024 px²), buộc toàn bộ sprite nhân vật phải cao từ 48–64 px và công trình phải cao 120–200 px. Điều này làm tăng đột biến khối lượng đồ họa, dung lượng bộ nhớ, và khiến khung hình PC thông thường (1080p / 720p) chỉ hiển thị được một góc rất nhỏ của vương quốc, làm suy giảm tầm nhìn chiến lược.
- **Lý do chốt kích thước 32 × 16 pixel:**
  - Hình thoi rộng **32 pixel**, cao **16 pixel** là kích thước chuẩn mực kinh điển của isometric pixel art 2:1.
  - Toàn bộ bản đồ 64 × 64 ô trải dài trên không gian màn hình là **2048 × 1024 pixel**. Ở độ phân giải PC chuẩn (1080p / 720p) với các mức zoom 1× đến 2.5×, người chơi vừa có thể phóng to để ngắm chi tiết cư dân làm việc, vừa có thể thu nhỏ để bao quát cả vương quốc một cách rõ ràng.
  - Cung cấp vừa đủ không gian điểm ảnh (256 px²) để thể hiện hoa văn địa hình đẹp mắt mà không làm bùng nổ gánh nặng vẽ asset.
  - Tỉ lệ bước 2:1 cho đường viền pixel sạch sẽ, hoàn hảo không bị gãy nét hay răng cưa lệch bậc.

### Nguyên tắc Tỉ lệ Sprite và Chiều cao Công trình (Không bóp méo Sprite)
- **Không ép hay bóp méo sprite vào kích thước ô:** Kích thước 32 × 16 pixel chỉ là diện tích tiếp xúc mặt đất (footprint). Các thực thể (cây cối, cư dân, công trình, đá, tường) có chiều cao thực tế vươn thẳng đứng lên phía trên theo trục `-Y` màn hình.
  - **Cư dân (Quy chuẩn mặc định):** Khung hình canvas mặc định là 24 × 32 pixel; hình nhân vật hiển thị thực tế cao xấp xỉ 22 – 26 pixel, rộng 12 – 16 pixel (không ép giãn kín khung nhằm chừa khoảng trống cho mũ, động tác nhấp nhô và công cụ cầm tay); điểm tiếp đất (foot pivot) đặt tại `Vector2(12, 30)` của khung hình, trùng với gốc tọa độ node để phân tầng Y-sorting chuẩn xác; footprint logic trên lưới là 1 × 1 ô. (Quy chuẩn này là mặc định đề xuất, có thể linh hoạt mở rộng kích thước khung khi có nhân vật đặc thù hợp lý).
  - Cây cối / Tài nguyên: cao từ 32–64 pixel; chân gốc đặt tại tâm ô tiếp đất.
  - Công trình: footprint chiếm diện tích hình thoi 1×1 ô (32×16 px), 2×2 ô (64×32 px), hoặc 3×3 ô (96×48 px); chiều cao vươn lên từ 32–96 pixel, thể hiện rõ phần mái và mặt tiền hướng Tây Nam / Đông Nam.

### Chuyển đổi Tọa độ và Chọn Ô (Coordinate Mapping & Cell Selection)
1. **Không gian Tọa độ:**
   - Tọa độ chuột màn hình (`get_global_mouse_position()`) phải được chuyển về tọa độ cục bộ của bản đồ thông qua `tile_map_layer.to_local(mouse_pos)` trước khi tính toán.
   - Lưới logic: Tọa độ số nguyên `Vector2i(grid_x, grid_y)` thuộc phạm vi $0 \le \text{grid\_x}, \text{grid\_y} < 64$.
2. **Từ Lưới Logic `(grid_x, grid_y)` sang Tọa độ Cục bộ `(local_x, local_y)`:**
   - `local_x = (grid_x - grid_y) * (TILE_WIDTH / 2) = (grid_x - grid_y) * 16.0`
   - `local_y = (grid_x + grid_y) * (TILE_HEIGHT / 2) = (grid_x + grid_y) * 8.0`
3. **Từ Tọa độ Cục bộ `(local_x, local_y)` sang Ô Lưới `(grid_x, grid_y)` (Công thức Nghịch đảo Chuẩn xác):**
   - Đặt tọa độ trục liên tục:
     $$u = \frac{\text{local\_x}}{32.0} + \frac{\text{local\_y}}{16.0}$$
     $$v = \frac{\text{local\_y}}{16.0} - \frac{\text{local\_x}}{32.0}$$
   - Để tâm ô $(0, 0)$ bao quát đúng hình thoi đối xứng và tránh lệch góc phần tư (quadrant shift), công thức làm tròn ô chuẩn xác là:
     - `grid_x = floor(u + 0.5) = floor((local_x / 32.0 + local_y / 16.0) + 0.5)`
     - `grid_y = floor(v + 0.5) = floor((local_y / 16.0 - local_x / 32.0) + 0.5)`
4. **API Native Godot 4 `TileMapLayer`:**
   - Khi cấu hình `TileMapLayer` với `tile_shape = TileSet.TILE_SHAPE_ISOMETRIC` và `tile_size = Vector2i(32, 16)`, Godot cung cấp sẵn các phương thức tối ưu C++:
     ```gdscript
     var local_mouse: Vector2 = tile_map_layer.to_local(get_global_mouse_position())
     var cell: Vector2i = tile_map_layer.local_to_map(local_mouse)
     var cell_center: Vector2 = tile_map_layer.map_to_local(cell)
     ```
5. **Kiểm tra Biên Bản đồ và Đồng bộ Con trỏ:**
   - Ô hợp lệ phải thỏa mãn: `0 <= cell.x < 64 and 0 <= cell.y < 64`.
   - Cả hệ thống highlight con trỏ chuột và hệ thống đặt công trình đều bắt buộc sử dụng chung kết quả ánh xạ `cell` này. Nếu `cell` nằm ngoài biên thế giới hoặc footprint công trình vượt ra ngoài biên, thao tác bị từ chối và khung highlight hiển thị trạng thái không hợp lệ.

### Phân tầng Chiều sâu (Depth / Y-Sorting)
- Hệ thống hiển thị sử dụng Godot `y_sort_enabled = true`.
- Gốc tọa độ (origin / pivot) của mọi node hiển thị (cư dân, cây cối, công trình) phải được đặt chính xác tại **điểm tiếp đất (chân sprite / tâm đáy footprint)**.
- Nhờ đó, khi một cư dân di chuyển về phía sau công trình (Y nhỏ hơn), công trình tự động che khuất cư dân; khi cư dân bước ra phía trước công trình (Y lớn hơn), cư dân tự động hiển thị đè lên mặt tiền công trình một cách tự nhiên.

### Camera, Hiển thị và Cấu hình Tập trung
- Camera 2D hỗ trợ di chuyển (Pan), phóng to/thu nhỏ (Zoom) mượt mà.
- Bắt buộc dùng phóng to Nearest-Neighbor (`TEXTURE_FILTER_NEAREST`) để giữ độ sắc nét nguyên bản của pixel art.
- Bản đồ hữu hạn (không mở rộng vô hạn khi chạm biên).
- Vùng chưa mở được che bởi Fog of War theo các ô thoi.
- Bản đồ sinh từ Seed để tái lập chính xác khi kiểm thử.
- Mọi thông số kích thước ô (32 × 16 px), hệ số chiếu và offset phải được lưu trữ trong Resource cấu hình tập trung, tuyệt đối không hardcode rải rác.

## 3.2. Các loại địa hình

MVP sử dụng các địa hình:

- Đồng cỏ.
- Rừng.
- Đồi.
- Núi.
- Sông hoặc hồ.
- Đất trống.
- Phế tích.
- Khu định cư trung lập.

Địa hình ảnh hưởng đến khả năng xây dựng, di chuyển, khai thác tài nguyên và chiến đấu.

Ví dụ:

- Rừng có nhiều gỗ.
- Đồi có thể chứa đá và quặng.
- Núi có thể chứa quặng hiếm nhưng khó tiếp cận.
- Đồng cỏ phù hợp với nông nghiệp.
- Sông và hồ có thể giới hạn đường đi hoặc tạo lợi thế phòng thủ.
- Phế tích có thể chứa tài nguyên hoặc công nghệ được khám phá.

## 3.3. Quy tắc tạo bản đồ

Bộ sinh bản đồ phải:

1. Đặt nhà chính ở vị trí hợp lệ.
2. Đảm bảo khu vực ban đầu có đủ tài nguyên cơ bản.
3. Không đặt nhà chính trên nước, núi hoặc ô không thể xây dựng.
4. Không tạo các cụm tài nguyên bắt buộc ở vị trí hoàn toàn không thể tiếp cận.
5. Đặt các điểm khám phá ở những vị trí có thể tiếp cận bằng đường đi.
6. Đảm bảo các thế lực ban đầu không xuất hiện chồng lấn.
7. Sinh seed và lưu seed vào trạng thái thế giới.
8. Có thể tạo lại bản đồ với cùng seed để hỗ trợ kiểm thử.

Nếu sinh bản đồ thất bại, hệ thống phải thử lại với seed khác hoặc dùng phương án dự phòng. Không được để game khởi động với bản đồ không thể chơi.

## 3.4. Fog of War

Mỗi ô bản đồ có một trạng thái:

- Chưa khám phá.
- Đã khám phá nhưng hiện không được quan sát.
- Đang được quan sát.

Thông tin tài nguyên và công trình của khu vực chưa khám phá không được hiển thị như thể người chơi đã biết.

Trong MVP, chỉ cần tầm nhìn đơn giản dựa trên khoảng cách từ dân, trạm gác hoặc đội trinh sát. Không cần mô phỏng ánh sáng hoặc tầm nhìn vật lý phức tạp.

---

# PHẦN IV — THỜI GIAN VÀ MÔ PHỎNG

## 4.1. Đồng hồ game

Thiết lập mặc định:

- Một ngày game = 180 giây thực ở tốc độ bình thường.
- Một mùa = 10 ngày game.
- Một năm = 40 ngày game.
- Tốc độ 1×, 2× và 3×.
- Có nút Pause.
- Khi Pause, mô phỏng không tiếp tục tạo thay đổi về kinh tế, dân cư, chiến đấu hoặc thời gian nghiên cứu.

Giao diện hiển thị ngày, mùa và năm.

Tất cả tốc độ phải được điều khiển bởi một hệ thống thời gian trung tâm. Không để từng hệ thống tự tạo đồng hồ riêng dẫn đến sai lệch.

## 4.2. Chu kỳ mô phỏng

Không xử lý toàn bộ kinh tế và AI ở mỗi frame.

Đề xuất lịch xử lý:

- Di chuyển và hoạt ảnh: cập nhật theo frame.
- Kiểm tra hành động của dân: theo chu kỳ ngắn hoặc sự kiện.
- Sản xuất và tiêu thụ: cập nhật một lần mỗi ngày game.
- Nghiên cứu: cập nhật theo thời gian mô phỏng.
- Quan hệ ngoại giao: cập nhật định kỳ, ví dụ mỗi ngày game.
- Sự kiện mùa: xử lý khi chuyển mùa.
- Sự kiện thế giới: theo lịch hoặc điều kiện.
- Tạo tổng kết và kiểm tra chiến thắng/thất bại: sau các sự kiện mô phỏng có liên quan.

Các chu kỳ phải có thể cấu hình và kiểm thử.

## 4.3. Chống mô phỏng trùng

Mỗi ngày game chỉ được thực hiện một lần cho từng tác vụ định kỳ. Khi tăng tốc, game không được bỏ qua hoặc nhân đôi ngày.

Việc Pause/Resume và lưu/tải phải không khiến:

- Dân bị tiêu thụ thức ăn hai lần trong một ngày.
- Sản xuất được cộng hai lần.
- Nghiên cứu tăng tiến độ nhiều hơn thời gian thực tế trong game.
- Phần thưởng được cấp lại.
- Một sự kiện xuất hiện lặp vô hạn.

---

# PHẦN V — TÀI NGUYÊN VÀ KINH TẾ

## 5.1. Tám tài nguyên chính

| Tài nguyên | Mục đích |
|---|---|
| Food — Thức ăn | Duy trì dân cư và quân đội |
| Wood — Gỗ | Nhà ở, công trình và một số trang bị |
| Stone — Đá | Công trình bền vững và phòng thủ |
| Ore — Quặng | Nguyên liệu luyện kim |
| Metal — Kim loại | Công cụ và trang bị |
| Tools — Công cụ | Nâng hiệu quả sản xuất |
| Magic Crystal — Pha lê ma thuật | Công nghệ đặc biệt và nghiên cứu |
| Herbs — Dược liệu | Chữa trị, giao dịch và một số công nghệ |

Tiền không phải tài nguyên thứ chín; tiền được quản lý trong Treasury.

Mỗi loại tài nguyên có:

- ID duy nhất.
- Tên hiển thị.
- Biểu tượng.
- Giá trị giao dịch cơ sở.
- Đơn vị lưu trữ.
- Quy tắc tiêu thụ hoặc sử dụng.
- Giới hạn lưu trữ nếu áp dụng.

Không được sử dụng chuỗi tên tài nguyên làm khóa dữ liệu chính. Dùng ID ổn định để tránh lỗi khi đổi ngôn ngữ hoặc tên hiển thị.

## 5.2. Tài nguyên ban đầu

Mặc định khi tạo thế giới:

| Tài nguyên | Số lượng |
|---|---:|
| Food | 120 |
| Wood | 120 |
| Stone | 70 |
| Ore | 20 |
| Metal | 5 |
| Tools | 12 |
| Magic Crystal | 0 |
| Herbs | 10 |
| Treasury | 250 |

Đây là bộ giá trị khởi tạo để playtest, có thể cân bằng sau nhưng phải được lưu trong một cấu hình trung tâm.

## 5.3. Công thức tiêu thụ thức ăn

Mỗi dân thường tiêu thụ 0,8 Food mỗi ngày game.

Với 24 dân, mức tiêu thụ cơ bản là:

24 × 0,8 = 19,2 Food/ngày.

Quân đội tiêu thụ thêm thức ăn theo số binh sĩ.

Nếu lượng Food khả dụng không đủ:

1. Hiển thị cảnh báo.
2. Ghi nhận mức thiếu hụt.
3. Tinh thần và hiệu quả lao động giảm theo mức độ.
4. Nếu thiếu hụt kéo dài, dân có thể rời đi hoặc sức khỏe suy giảm.
5. Chỉ chuyển sang khủng hoảng nghiêm trọng khi vượt ngưỡng được định nghĩa.

Không được giết dân ngay lập tức khi kho thức ăn giảm xuống 0.

## 5.4. Sản xuất nông nghiệp

Công thức sản xuất cơ bản:

Food Produced = Farmer Count × Base Production × Seasonal Modifier × Tool Modifier.

Giá trị mặc định:

- Sản lượng cơ bản: 5 Food/người/ngày.
- Mùa bình thường: hệ số 1,0.
- Mùa bất lợi: hệ số 0,5.
- Công cụ hoặc công nghệ có thể tăng sản lượng về sau.

Ví dụ: 5 nông dân ở điều kiện bình thường tạo ra 25 Food/ngày. Với 24 dân tiêu thụ 19,2 Food/ngày, vương quốc có lượng dư nhỏ để dự trữ.

Mức sản lượng thực tế phải được hiển thị trong giao diện, không được chỉ có công thức nội bộ.

## 5.5. Kho chứa

- Mỗi kho có sức chứa.
- Mọi thay đổi số lượng phải đi qua hệ thống quản lý tài nguyên.
- Tổng tài nguyên không được vượt giới hạn nếu game chưa hỗ trợ kho mở rộng.
- Khi kho đầy, hệ thống sản xuất phải dừng hoặc tìm kho khác phù hợp.
- Giao diện phải phân biệt tổng tài nguyên, tài nguyên đang được vận chuyển và tài nguyên đã được dành cho một công việc.
- Không cho phép hai công việc cùng tiêu thụ một đơn vị tài nguyên đã được đặt trước.

## 5.6. Ngân khố

Treasury được dùng cho:

- Lương.
- Xây dựng.
- Tuyển quân và duy trì quân đội.
- Giao dịch.
- Nghiên cứu cần tiền.
- Ngoại giao.
- Các sự kiện đặc biệt.

MVP chưa cần mô phỏng thuế quá phức tạp. Có thể dùng một nguồn thu cơ bản gắn với kinh tế hoạt động và giao dịch, nhưng phải có giới hạn, chi phí và nguồn gốc rõ ràng.

---

# PHẦN VI — DÂN CƯ

## 6.1. Số lượng và khởi tạo

Thế giới bắt đầu với 24 dân trưởng thành.

Các công trình ban đầu:

- 1 Town Hall.
- 4 Houses.
- 1 Farm.
- 1 Storehouse.
- 1 Woodcutter Camp.

Bố trí đủ gần nhau để người chơi có thể hiểu vòng kinh tế ban đầu. Khu vực xây dựng ban đầu phải có không gian để mở rộng.

## 6.2. Chỉ số dân cư

Mỗi dân có:

- ID duy nhất.
- Tên.
- Tuổi.
- Giai đoạn sống.
- Health.
- Hunger.
- Fatigue.
- Morale.
- Strength.
- Intelligence.
- Stamina.
- Magic Potential.
- Nghề nghiệp.
- Kỹ năng nghề.
- 1–2 đặc điểm tính cách.
- Trạng thái hiện tại.
- Công việc hiện tại.
- Vị trí bản đồ.
- Quan hệ gia đình cơ bản.

Các chỉ số cần có phạm vi xác định, ví dụ 0–100 với Hunger, Fatigue, Morale và Health.

Không để chỉ số có thể tăng vô hạn hoặc trở thành số âm nếu chưa được định nghĩa.

## 6.3. Nghề nghiệp trong MVP

Các nghề chính:

- Farmer.
- Woodcutter.
- Miner.
- Builder.
- Hauler.
- Researcher.
- Guard.
- Idle/Unassigned.

Không cần tạo một AI riêng hoàn toàn cho từng nghề. Các nghề dùng chung hệ thống công việc, với yêu cầu kỹ năng và loại mục tiêu khác nhau.

## 6.4. Phân công dân ban đầu

Bộ phân công mặc định:

| Nghề | Số dân |
|---|---:|
| Farmer | 5 |
| Woodcutter | 4 |
| Miner | 2 |
| Builder | 3 |
| Hauler | 3 |
| Researcher | 2 |
| Guard | 2 |
| Idle/Unassigned | 3 |
| **Tổng** | **24** |

Người chơi được quyền thay đổi phân công.

Không phải tất cả dân đều phải làm việc liên tục. Hệ thống phải tính đến nghỉ ngơi, nhu cầu thiết yếu và các tình huống khẩn cấp.

## 6.5. Kỹ năng nghề

Kỹ năng nghề tăng dần thông qua công việc thực tế.

Kỹ năng có thể ảnh hưởng đến:

- Sản lượng.
- Thời gian hoàn thành.
- Khả năng tránh lãng phí.
- Chất lượng công việc trong phiên bản mở rộng.

Trong MVP, chỉ cần một hệ số hiệu quả đơn giản, có giới hạn trên.

Không cho phép Intelligence hoặc một chỉ số duy nhất khiến dân trở nên giỏi nhất ở tất cả công việc.

## 6.6. Nhu cầu và nghỉ ngơi

Dân cần:

- Thức ăn.
- Nghỉ ngơi.
- Sức khỏe.
- Chỗ ở.
- Tinh thần.

MVP có thể mô phỏng Hunger, Fatigue, Health và Morale chi tiết hơn; chỗ ở được kiểm tra ở cấp độ công trình.

Nếu Fatigue quá cao, dân tự tìm thời gian nghỉ. Nếu Hunger quá cao, dân ưu tiên xử lý nhu cầu. Trong tình huống nguy hiểm, dân có thể bỏ công việc để bảo vệ bản thân.

## 6.7. Vòng đời

MVP chỉ cần:

- Trẻ em: chưa làm việc đầy đủ.
- Người trưởng thành: có thể làm việc.
- Người già: hiệu quả lao động giảm.
- Qua đời: giảm dân số và giải phóng chỗ ở.

Sinh con và nhập cư có thể dùng mô hình xác suất đơn giản dựa trên điều kiện nhà ở, thức ăn, sức khỏe và tinh thần.

Không triển khai di truyền nhiều gene trong MVP.

---

# PHẦN VII — HỆ THỐNG CÔNG TRÌNH

## 7.1. Danh sách công trình

| Công trình | Công dụng | Footprint (Lưới ô thoi) | Chi phí khởi điểm |
|---|---|---|---|
| Town Hall | Trung tâm quản trị | 3 × 3 ô (96 × 48 px base) | Có sẵn |
| House | Chỗ ở | 2 × 2 ô (64 × 32 px base) | 15 Wood, 5 Stone |
| Farm | Sản xuất thức ăn | 2 × 2 ô (64 × 32 px base) | 20 Wood |
| Woodcutter Camp | Khai thác gỗ | 2 × 2 ô (64 × 32 px base) | 15 Wood |
| Quarry | Khai thác đá | 2 × 2 ô (64 × 32 px base) | 15 Wood, 5 Tools |
| Mine | Khai thác quặng | 2 × 2 ô (64 × 32 px base) | 20 Wood, 10 Stone |
| Workshop | Chế tạo công cụ và kim loại | 2 × 2 ô (64 × 32 px base) | 20 Wood, 15 Stone, 5 Metal |
| Storehouse | Lưu trữ | 2 × 2 ô (64 × 32 px base) | 15 Wood, 10 Stone |
| Research Hall | Nghiên cứu công nghệ | 3 × 3 ô (96 × 48 px base) | 25 Wood, 10 Stone |
| Watchtower | Phát hiện nguy hiểm | 1 × 1 ô (32 × 16 px base) | 20 Wood, 15 Stone |
| Market | Giao dịch | 3 × 3 ô (96 × 48 px base) | 25 Wood, 10 Stone |
| Barracks | Tuyển quân | 3 × 3 ô (96 × 48 px base) | 25 Wood, 20 Stone, 5 Metal |

Các mức chi phí là giá trị ban đầu để kiểm thử. Mọi chi phí và footprint phải đặt trong dữ liệu cấu hình, không viết cứng trong logic xây dựng.

### Quy chuẩn Phối cảnh và Thị giác Công trình
Bám sát hình ảnh tham chiếu chuẩn (`docs/reference/kingdom_visual_reference.png`):
- **Góc nhìn ba phần tư (Three-quarter isometric):** Mọi công trình đều thể hiện rõ:
  - Mặt mái che (rooftop): Các bề mặt dốc nhìn từ trên hướng về Tây Bắc / Đông Bắc.
  - Các mặt tường tiền diện (front-facing facades): Hai mặt tường hướng về phía Tây Nam và Đông Nam hướng thẳng về phía người chơi.
  - Tường sau (hướng Tây Bắc và Đông Bắc) bị che khuất tự nhiên bởi phần mái, không hiển thị.
- **Chiều cao công trình (Không nén dẹp sprite):** Đáy công trình khớp hoàn hảo với footprint hình thoi trên mặt đất (1×1 = 32×16 px, 2×2 = 64×32 px, 3×3 = 96×48 px). Toàn bộ khối kiến trúc vươn lên theo trục thẳng đứng `-Y` (chiều cao đồ họa từ 32px đến 96px tùy quy mô công trình).
- **Điểm neo phân tầng chiều sâu (Y-Sort Anchor):** Gốc tọa độ của công trình được đặt tại đáy tâm của footprint tiếp đất (hoặc cạnh trước tiếp xúc mặt đất) để bảo đảm quy tắc Y-sorting chuẩn xác: cư dân bước phía sau nhà sẽ bị mái/tường che, cư dân bước phía trước nhà sẽ hiển thị nổi trên mặt tường.

## 7.2. Trạng thái công trình

Mỗi công trình có:

- ID.
- Loại.
- Vị trí logic trên lưới (`Vector2i`).
- Kích thước footprint (`Vector2i`).
- Trạng thái xây dựng.
- Độ bền nếu cần.
- Công suất.
- Sức chứa nếu có.
- Danh sách công việc.
- Người lao động được phân công.
- Tài nguyên đầu vào và đầu ra.
- Chi phí vận hành.

Trạng thái xây dựng:

- Planned.
- Under Construction.
- Active.
- Paused.
- Damaged.
- Destroyed.

Chỉ công trình Active mới thực hiện chức năng bình thường.

## 7.3. Quy tắc xây dựng

1. Kiểm tra vị trí hợp lệ.
2. Kiểm tra ô không bị chiếm.
3. Kiểm tra địa hình.
4. Kiểm tra tài nguyên.
5. Đặt trước tài nguyên.
6. Tạo công việc xây dựng.
7. Dân xây dựng theo thời gian và số lao động.
8. Khi hoàn thành, chuyển công trình sang Active.
9. Nếu hủy, hoàn lại phần tài nguyên theo quy tắc đã định.

MVP dùng quy tắc hoàn lại 50% nguyên liệu chưa được sử dụng khi hủy công trình đang xây dựng. Nếu công trình đã hoàn thành, việc phá hủy không hoàn trả toàn bộ nguyên liệu.

---

# PHẦN VIII — CÔNG VIỆC VÀ TỰ ĐỘNG HÓA

## 8.1. Hệ thống công việc chung

Mỗi công việc phải có:

- Job ID.
- Job Type.
- Priority.
- Target.
- Required Resources.
- Assigned Citizens.
- Progress.
- State.
- Cancellation Reason.
- Creation Time.

Trạng thái:

- Available.
- Reserved.
- In Progress.
- Completed.
- Failed.
- Cancelled.

Các nghề sử dụng cùng một hệ thống công việc. Không tạo logic hoàn toàn tách biệt cho mỗi công trình nếu có thể dùng chung.

## 8.2. Lệnh thủ công

Người chơi có thể chọn dân và ra lệnh:

- Di chuyển đến vị trí.
- Chặt cây.
- Khai thác đá.
- Khai thác quặng.
- Vận chuyển.
- Xây dựng.
- Canh gác.
- Khám phá.

Lệnh kết thúc khi hoàn thành, bị hủy, không còn mục tiêu hoặc không thể thực hiện.

Nếu lệnh thất bại, giao diện phải hiển thị nguyên nhân.

## 8.3. Thứ tự ưu tiên

1. An toàn khẩn cấp.
2. Nhu cầu thiết yếu cấp bách.
3. Lệnh thủ công còn hiệu lực.
4. Nghề nghiệp chính.
5. Công việc phụ.
6. Nghỉ ngơi hoặc chờ việc.

Nhu cầu thiết yếu bình thường không được liên tục phá lệnh thủ công. Chỉ tình huống cấp bách mới được quyền ngắt.

## 8.4. Tự động hóa cơ bản

MVP hỗ trợ các quy tắc:

- Nếu Food dưới ngưỡng → ưu tiên sản xuất hoặc vận chuyển Food.
- Nếu kho đầy → dừng chuyển tài nguyên vào kho đó.
- Nếu công trình cần nguyên liệu → tạo công việc vận chuyển.
- Nếu dân kiệt sức → cho nghỉ.
- Nếu nguy hiểm ở gần → chuyển sang trạng thái an toàn.
- Nếu không còn công việc hợp lệ → tìm việc theo nghề.
- Nếu không có việc phù hợp → chờ và hiển thị lý do.

Người chơi có thể bật/tắt quy tắc và chỉnh một số ngưỡng.

## 8.5. Flowchart nâng cao

Thiết kế giao diện node-based cho phiên bản mở rộng, nhưng MVP chỉ cần hỗ trợ một tập node giới hạn:

- Condition.
- Action.
- Branch.
- Wait.
- End.

Ví dụ:

IF Food < 60  
THEN ưu tiên vận chuyển Food  
ELSE IF Fatigue > 80  
THEN Rest  
ELSE làm nghề chính.

Không cần xây một ngôn ngữ lập trình tổng quát.

Phải phát hiện node không kết nối, nhánh thiếu đầu ra, vòng lặp vô hạn và giới hạn số bước thực thi mỗi chu kỳ.

---

# PHẦN IX — NGHIÊN CỨU VÀ KHÁM PHÁ

## 9.1. Các nhánh công nghệ

MVP có bốn nhánh:

1. Survival & Agriculture.
2. Production & Logistics.
3. Military & Defense.
4. Magic & Research.

Mỗi nhánh có khoảng 2–3 công nghệ, tổng cộng 8–12 công nghệ trong MVP.

## 9.2. Ví dụ công nghệ

| Công nghệ | Hiệu quả |
|---|---|
| Improved Farming | Tăng sản lượng nông nghiệp |
| Food Preservation | Giảm thất thoát thức ăn |
| Efficient Tools | Tăng hiệu quả một số công việc |
| Better Storage | Tăng sức chứa kho |
| Advanced Mining | Cải thiện khai thác |
| Defensive Structures | Tăng hiệu quả phòng thủ |
| Basic Magic | Mở khóa công dụng pha lê |
| Exploration Methods | Tăng hiệu quả khám phá |

## 9.3. Quy tắc nghiên cứu

Mỗi công nghệ có:

- Chi phí tài nguyên.
- Thời gian nghiên cứu.
- Điều kiện mở khóa.
- Hiệu quả cụ thể.
- Trạng thái nghiên cứu.

MVP chỉ cho phép nghiên cứu một công nghệ tại một thời điểm.

Người chơi có thể hủy nghiên cứu theo quy tắc hoàn trả đã định. Không được cộng tiến độ nghiên cứu khi game Pause.

## 9.4. Khám phá mở khóa

Một số công nghệ chỉ mở sau khi khám phá:

- Phế tích.
- Mỏ hiếm.
- Di tích cổ.
- Địa điểm đặc biệt.

Khám phá phải có phần thưởng xác định: tài nguyên, tri thức, địa điểm mới hoặc thông tin chiến lược.

Không tạo ra phần thưởng tùy ý mà không được lưu vào trạng thái thế giới.

---

# PHẦN X — THẾ LỰC, NGOẠI GIAO VÀ CHIẾN ĐẤU

## 10.1. Các thế lực ban đầu

Mỗi thế giới có:

- Vương quốc của người chơi.
- Hai vương quốc đối thủ.
- Một khu định cư trung lập.

Mỗi thế lực có:

- ID.
- Tên.
- Dân số.
- Tài nguyên chính.
- Sức mạnh quân sự.
- Mức ổn định.
- Quan hệ với các thế lực khác.
- Mục tiêu chiến lược.
- Trạng thái tồn tại.

## 10.2. Ngoại giao

MVP hỗ trợ:

- Giao thương.
- Hiệp ước không xâm phạm.
- Trao đổi tài nguyên.
- Liên minh phòng thủ đơn giản.
- Chiến tranh.
- Chấm dứt chiến tranh.

Quan hệ bị ảnh hưởng bởi giao dịch, chiến tranh, hiệp ước, sức mạnh và sự kiện.

Không cần dùng AI tạo sinh để quyết định ngoại giao. Dùng hệ thống luật và trạng thái có thể kiểm thử.

## 10.3. Thế lực mới

Trong MVP, chỉ cho phép tối đa một thế lực mới nổi ngoài các thế lực ban đầu.

Một khu định cư trung lập có thể phát triển thành thế lực mới nếu:

- Đạt ngưỡng dân số.
- Có tài nguyên thiết yếu.
- Duy trì sự ổn định.
- Có đủ thời gian phát triển.

Các điều kiện được kiểm tra định kỳ.

## 10.4. Chiến đấu

MVP dùng mô phỏng chiến đấu trừu tượng.

Kết quả phụ thuộc vào:

- Quân số.
- Trang bị.
- Kinh nghiệm.
- Công sự.
- Địa hình.
- Trinh sát.
- Tiếp tế.
- Yếu tố bất định có giới hạn.

Công thức phải được đặt trong một Battle Resolver riêng và có kiểm thử.

Không được quyết định thắng thua chỉ bằng quân số.

Sau trận chiến, hệ thống cập nhật:

- Thương vong.
- Tài nguyên bị mất.
- Lãnh thổ.
- Trạng thái quân đội.
- Quan hệ ngoại giao.
- Sự kiện liên quan.

Người chơi phải nhận được báo cáo giải thích các yếu tố chính ảnh hưởng đến kết quả.

## 10.5. Mất thủ đô

Mất thủ đô không tự động kết thúc game.

Nếu còn lực lượng, lãnh thổ, đồng minh hoặc khả năng tái lập chính quyền, vương quốc có thể tiếp tục.

Chỉ chuyển sang sụp đổ khi điều kiện duy trì chính quyền không còn khả thi và không có con đường phục hồi hợp lệ.

---

# PHẦN XI — THƯƠNG MẠI

## 11.1. Thương nhân

Thương nhân xuất hiện định kỳ với lượng hàng hữu hạn.

Mỗi thương nhân có:

- Hàng hóa.
- Số lượng.
- Giá mua.
- Giá bán.
- Thời điểm xuất hiện.
- Thời điểm rời đi.

Giá mua và giá bán phải khác nhau.

## 11.2. Giá cả

Giá giao dịch chịu ảnh hưởng bởi:

- Giá cơ sở.
- Cung và cầu.
- Mức độ khan hiếm.
- Rủi ro tuyến đường.
- Quan hệ ngoại giao.

Giá không được thay đổi ngẫu nhiên vô hạn hoặc tạo lợi nhuận chắc chắn không có rủi ro.

## 11.3. Kiểm tra giao dịch

Trước khi giao dịch, hệ thống phải kiểm tra:

- Kho có đủ hàng.
- Người chơi có đủ tiền.
- Kho có đủ sức chứa.
- Thương nhân còn hàng.
- Giao dịch chưa bị xử lý trước đó.

Tất cả thay đổi phải được thực hiện nguyên tử: giao dịch thành công hoàn toàn hoặc không có thay đổi.

---

# PHẦN XII — KHỦNG HOẢNG, SỤP ĐỔ VÀ CHIẾN THẮNG

## 12.1. Các trạng thái

### Crisis

Các chỉ số đang xuống thấp nhưng còn có thể phục hồi.

Ví dụ:

- Food sắp cạn.
- Treasury thấp.
- Dân có tinh thần thấp.
- Sản xuất đình trệ.

### Decline

Hậu quả đã xuất hiện.

Ví dụ:

- Dân rời đi.
- Công trình thiếu nguyên liệu.
- Quân đội thiếu tiếp tế.
- Mất lãnh thổ.

### Collapse

Vương quốc không còn khả năng duy trì chính quyền và không còn phương án phục hồi khả thi.

Thế giới kết thúc ván.

## 12.2. Quy tắc cảnh báo

Giao diện phải giải thích:

- Điều gì đang xảy ra.
- Nguyên nhân.
- Mức độ nghiêm trọng.
- Hành động khả thi.
- Hậu quả có thể xảy ra nếu không xử lý.

Không dùng cảnh báo chung chung như “Vương quốc đang nguy hiểm” mà không có thông tin bổ sung.

## 12.3. Chiến thắng thịnh vượng

MVP chỉ cần hoàn thiện con đường chiến thắng thịnh vượng.

Điều kiện ban đầu để kiểm thử:

- Dân số đạt ít nhất 30.
- Food dự trữ đạt mức an toàn.
- Treasury không âm và có thể thanh toán chi phí thiết yếu.
- Hoàn thành ít nhất ba công nghệ.
- Morale trung bình đạt ít nhất 65/100.
- Không có khủng hoảng nghiêm trọng.
- Tất cả điều kiện được duy trì liên tục trong 5 ngày game.

Các giá trị phải đặt trong cấu hình và có thể cân bằng sau playtest.

Chiến thắng không được kích hoạt chỉ bằng một lần đạt ngưỡng. Phải duy trì điều kiện trong khoảng thời gian quy định.

## 12.4. Sau chiến thắng

Người chơi được chọn:

- Tiếp tục thế giới.
- Kết thúc thế giới và xem tổng kết.

Không bắt buộc kết thúc khi đạt chiến thắng.

## 12.5. Sau sụp đổ

Hiển thị tổng kết gồm:

- Thời gian tồn tại.
- Dân số cao nhất.
- Công trình đã xây.
- Công nghệ đã mở.
- Tài nguyên đã sản xuất.
- Các sự kiện lớn.
- Nguyên nhân chính dẫn đến sụp đổ.
- Thành tích Legacy đủ điều kiện.

Không tự động xóa save. Người chơi có thể xem lại hoặc tải lại bản lưu trước đó, nhưng hệ thống thành tích phải chống việc nhận thưởng trùng.

---

# PHẦN XIII — LEGACY FUND

## 13.1. Mục đích

Legacy Fund là tiến trình ngoài thế giới hiện tại.

Legacy chỉ dùng cho:

- Skin.
- Giao diện.
- Hiệu ứng.
- Trang trí.
- Biểu tượng và huy hiệu.
- Mỹ phẩm vương quốc.

Không được dùng Legacy để mua:

- Tài nguyên.
- Quân đội.
- Công nghệ.
- Chỉ số nhân vật.
- Lợi thế gameplay.

## 13.2. Nguồn Legacy

Legacy đến từ:

- Thành tích hợp lệ.
- Phần tiền dư được chuyển từ ngân khố khi thế giới còn ổn định.

Tạo thế giới, tải game hoặc xóa game không tự cấp Legacy.

## 13.3. Chống khai thác lỗi

Mỗi thành tích phải có ID ổn định và trạng thái đã nhận.

Khi lưu hoặc tải game, hệ thống không được tạo thành tích mới chỉ vì sự kiện cũ được tải lại.

Trong MVP, có thể chỉ cần một hệ thống Legacy tối giản; chưa cần cửa hàng mỹ phẩm hoàn chỉnh.

---

# PHẦN XIV — GIAO DIỆN NGƯỜI DÙNG

## 14.1. Màn hình chính

Có:

- New World.
- Load World.
- Settings.
- Quit.

## 14.2. Màn hình tạo thế giới

Cho phép:

- Nhập tên thế giới.
- Chọn seed hoặc tạo ngẫu nhiên.
- Chọn độ khó.
- Xem mô tả độ khó.
- Bắt đầu thế giới.

Không yêu cầu Legacy để tạo thế giới.

## 14.3. HUD trong game

Hiển thị:

- Ngày, mùa, năm.
- Tốc độ mô phỏng.
- Food, Wood, Stone, Ore, Metal, Tools, Magic Crystal, Herbs.
- Treasury.
- Dân số.
- Mức cảnh báo.
- Nút Pause.
- Nút Save.
- Nút mở bảng quản lý.
- Khung chọn ô và tương tác chuột: Hiển thị con trỏ hình thoi (diamond highlight cursor) 32 × 16 pixel bám theo vị trí chuột trên lưới; khi xây dựng công trình, hiển thị footprint hình thoi tương ứng (1×1, 2×2, 3×3) với màu phản hồi (xanh: hợp lệ, đỏ: bị chiếm/không hợp lệ).

Không hiển thị mọi chỉ số dân cùng lúc trên màn hình chính.

## 14.4. Các bảng quản lý

### Citizen Panel

- Danh sách dân.
- Nghề.
- Nhu cầu.
- Kỹ năng.
- Công việc hiện tại.
- Lý do không làm việc.
- Nút giao việc.

### Building Panel

- Thông tin công trình.
- Chi phí.
- Trạng thái.
- Người lao động.
- Sản xuất.
- Nút nâng cấp nếu có.

### Economy Panel

- Tổng tài nguyên.
- Sản xuất mỗi ngày.
- Tiêu thụ mỗi ngày.
- Tài nguyên đang vận chuyển.
- Dự báo thiếu hụt.

### Automation Panel

- Quy tắc đang bật.
- Điều kiện.
- Hành động.
- Trạng thái.
- Lý do quy tắc chưa được thực thi.

### Research Panel

- Cây công nghệ.
- Chi phí.
- Thời gian.
- Điều kiện mở khóa.
- Tiến độ.

### Diplomacy Panel

- Các thế lực.
- Quan hệ.
- Hiệp ước.
- Giao dịch.
- Tình trạng chiến tranh.

## 14.5. Phản hồi giao diện

Mỗi hành động quan trọng cần phản hồi trực quan:

- Xây dựng thành công.
- Thiếu tài nguyên.
- Vị trí không hợp lệ.
- Không có đường đi.
- Kho đầy.
- Công việc bị hủy.
- Công nghệ đã mở.
- Sự kiện xảy ra.
- Vương quốc đang khủng hoảng.

Thông báo phải đủ rõ để người chơi không cần đọc log kỹ thuật.

---

# PHẦN XV — LƯU VÀ TẢI GAME

## 15.1. Dữ liệu phải được lưu

- World ID.
- World seed.
- Thời gian game.
- Độ khó.
- Địa hình.
- Fog of War.
- Tài nguyên.
- Treasury.
- Dân cư.
- Công trình.
- Công việc.
- Tự động hóa.
- Công nghệ.
- Thế lực.
- Ngoại giao.
- Quân đội.
- Sự kiện.
- Trạng thái chiến thắng/thất bại.
- Trạng thái thành tích liên quan.

## 15.2. Quy tắc lưu

- Có thể lưu ở menu tạm dừng.
- Có autosave định kỳ tùy cấu hình.
- Save có phiên bản dữ liệu.
- Khi tải, phải kiểm tra tính hợp lệ.
- Nếu save hỏng, hiển thị lỗi và không ghi đè lên file tốt hơn.
- Có thể tạo backup trước khi ghi đè.
- Lưu game không được cấp thêm tài nguyên hoặc phần thưởng.

## 15.3. Chống dữ liệu trùng

Tất cả thực thể có ID ổn định.

Không tạo dân mới, công trình mới hoặc thành tích mới chỉ vì hệ thống load lại dữ liệu.

Khi tải game, phải khôi phục trạng thái mô phỏng chứ không chạy lại quy trình tạo thế giới.

---

# PHẦN XVI — KIẾN TRÚC KỸ THUẬT

## 16.1. Công nghệ mặc định

- Godot 4.x.
- GDScript (ưu tiên typed GDScript).
- Game 2D Isometric / Dimetric (hình chiếu 2:1, diamond tile 32 × 16 pixel).
- TileMapLayer hoặc hệ thống hiển thị Tile 2D tương thích Godot 4.x hỗ trợ Isometric.
- Cơ chế phân tầng độ sâu trục Y: `y_sort_enabled = true` trên các node chứa thế giới và thực thể.
- Hiển thị pixel art chuẩn: Texture Filter Nearest (`TEXTURE_FILTER_NEAREST`), tắt mipmaps, kích hoạt 2D pixel snap.
- Dữ liệu cấu hình bằng Resource hoặc định dạng dữ liệu phù hợp.
- Git để quản lý phiên bản.
- Kiểm thử bằng các test scene hoặc framework test phù hợp.

Nếu repository đã có một engine và kiến trúc đang hoạt động, AI phải kiểm tra trước khi thay đổi. Không được tự ý viết lại toàn bộ dự án hoặc chuyển engine.

## 16.2. Phân chia module

Tổ chức logic thành các module độc lập:

### WorldGenerator

Sinh địa hình, tài nguyên, địa điểm và seed.

### WorldState

Lưu trạng thái chính của thế giới.

### TimeManager

Quản lý thời gian, tốc độ và Pause.

### ResourceManager

Quản lý tài nguyên, kho, tiêu thụ và giao dịch.

### CitizenManager

Quản lý dân, nhu cầu, nghề và vòng đời.

### JobSystem

Tạo, phân công, cập nhật và kết thúc công việc.

### NavigationSystem

Tìm đường trên bản đồ lưới.

### BuildingSystem

Đặt công trình, xây dựng và cập nhật trạng thái.

### AutomationSystem

Đánh giá điều kiện và thực thi quy tắc.

### ResearchSystem

Quản lý công nghệ, chi phí và tiến độ.

### DiplomacySystem

Quản lý quan hệ và hiệp ước.

### BattleResolver

Tính kết quả trận chiến.

### EventSystem

Quản lý sự kiện và điều kiện kích hoạt.

### SaveLoadSystem

Lưu, tải, kiểm tra và nâng cấp định dạng save.

### AchievementSystem

Theo dõi thành tích và Legacy.

### UI Layer

Hiển thị trạng thái và gửi lệnh đến các hệ thống.

### IsometricView / RenderLayer

Quản lý toàn bộ hiển thị 2D Isometric: ánh xạ chuyển đổi giữa lưới logic 64×64 (`Vector2i`) và tọa độ màn hình (`Vector2`), quản lý `TileMapLayer`, sprite công trình, cây cối, cư dân, con trỏ chuột hình thoi, cơ chế `y_sort_enabled` và camera pan/zoom.

## 16.3. Nguyên tắc kiến trúc

- **Tách biệt tuyệt đối giữa Mô phỏng Logic và Hiển thị Isometric:** Lưới thế giới trong mô phỏng là không gian số nguyên 64 × 64 ô (`Vector2i`). Mọi thuật toán (Job, Pathfinding, Building placement, Citizen movement logic) chỉ xử lý trên lưới logic này. Tầng hiển thị (`RenderLayer`) đóng vai trò là một hình chiếu đọc trạng thái và chuyển đổi sang không gian pixel 2:1 dimetric. Tuyệt đối không để logic mô phỏng phụ thuộc vào tọa độ pixel hay zoom camera.
- UI không trực tiếp tự thay đổi tài nguyên.
- UI gửi yêu cầu đến hệ thống tương ứng.
- Các hệ thống kiểm tra điều kiện trước khi cập nhật trạng thái.
- Không để nhiều module sở hữu bản sao độc lập của cùng một số lượng tài nguyên.
- Các quy tắc cân bằng phải nằm trong cấu hình dữ liệu.
- Các module phải có giao diện rõ ràng.
- Tránh tạo một script khổng lồ xử lý toàn bộ game.
- Tránh xây dựng framework quá phức tạp trước khi có gameplay.
- Không dùng dịch vụ mạng cho các hệ thống bắt buộc phải hoạt động offline.

## 16.4. Định danh và dữ liệu

Mỗi thực thể quan trọng phải có ID duy nhất.

Ví dụ:

- citizen_id.
- building_id.
- job_id.
- faction_id.
- world_id.
- event_id.
- achievement_id.

Không dùng vị trí trong danh sách làm ID lâu dài, vì danh sách có thể thay đổi khi xóa hoặc thêm thực thể.

## 16.5. Hiệu năng

Mục tiêu kiểm thử ban đầu:

- Bản đồ 64 × 64 ô.
- 24 dân lúc bắt đầu.
- Khoảng 100 dân trong prototype.
- Các thế lực ngoài màn hình được mô phỏng đơn giản.
- Các công việc và sự kiện cập nhật theo chu kỳ.
- Đường đi được tính lại khi cần, không tính lại liên tục nếu không có thay đổi.
- Không có tác vụ mạng trong vòng mô phỏng cốt lõi.

Mục tiêu khởi điểm là giữ trải nghiệm ổn định trên máy PC phổ thông. Chỉ đặt mục tiêu FPS cuối cùng sau khi đã đo trên môi trường chạy thực tế.

---

# PHẦN XVII — KIỂM THỬ VÀ TIÊU CHÍ NGHIỆM THU

## 17.1. Kiểm thử kinh tế

Phải xác nhận:

- Không tạo Food miễn phí.
- Tiêu thụ Food đúng một lần mỗi ngày.
- Không thể chi tiêu cùng một tài nguyên hai lần.
- Kho không vượt sức chứa.
- Giao dịch không thể thực hiện khi thiếu tiền.
- Công trình không thể xây khi thiếu nguyên liệu.
- Sản xuất dừng đúng cách khi kho đầy hoặc thiếu đầu vào.

## 17.2. Kiểm thử dân cư

- Dân nhận công việc hợp lệ.
- Dân có thể tìm đường.
- Dân không liên tục đổi việc vô hạn.
- Dân biết nghỉ khi kiệt sức.
- Dân phản ứng với nhu cầu thiết yếu.
- Dân giải thích được lý do không làm việc.
- Lệnh thủ công không làm hỏng trạng thái công việc.
- Dân không bị nhân đôi khi tải game.

## 17.3. Kiểm thử tự động hóa

- Quy tắc hoạt động khi điều kiện đúng.
- Quy tắc không chạy khi điều kiện sai.
- Vòng lặp bị phát hiện hoặc giới hạn.
- Quy tắc mâu thuẫn được cảnh báo.
- Không có công việc được thực thi hai lần chỉ vì cập nhật nhanh.
- Người chơi hiểu được tại sao quy tắc được hoặc không được kích hoạt.

## 17.4. Kiểm thử chiến thắng và sụp đổ

- Không thể chiến thắng khi thiếu điều kiện.
- Điều kiện phải được duy trì đủ thời gian.
- Sụp đổ chỉ xảy ra khi điều kiện thất bại hợp lệ.
- Sau chiến thắng có thể tiếp tục hoặc kết thúc thế giới.
- Sau sụp đổ có màn hình tổng kết.
- Không nhận thành tích hai lần sau khi tải lại save.

## 17.5. Kiểm thử lưu/tải

- Save rồi load phải giữ nguyên tài nguyên.
- Save rồi load phải giữ nguyên dân.
- Save rồi load phải giữ nguyên công trình.
- Save rồi load phải giữ nguyên công việc và tiến độ.
- Save rồi load không tạo thêm phần thưởng.
- Save hỏng không làm game crash mà không có thông báo.

## 17.6. Tiêu chí hoàn thành MVP

MVP chỉ được coi là hoàn thành khi người chơi có thể:

1. Tạo một thế giới.
2. Quản lý 24 dân.
3. Xây dựng công trình.
4. Sản xuất và tiêu thụ tài nguyên.
5. Giao việc thủ công.
6. Dùng tự động hóa cơ bản.
7. Nghiên cứu công nghệ.
8. Khám phá địa điểm.
9. Giao dịch.
10. Tương tác với ít nhất một thế lực khác.
11. Trải qua một thử thách có ảnh hưởng thực sự.
12. Chiến thắng thịnh vượng hoặc sụp đổ.
13. Xem tổng kết.
14. Lưu và tải mà không lỗi dữ liệu.
15. Trình diễn toàn bộ thế giới theo chuẩn 2D Isometric / Dimetric 2:1 (ô thoi 32 × 16 pixel), công trình có mái và mặt tiền, phân tầng Y-sorting chính xác và hiển thị pixel art sắc nét.

---

# PHẦN XVIII — KẾ HOẠCH TRIỂN KHAI CHO AI VIBE CODING

### 18.0. Mối quan hệ giữa Lộ trình GDD (Giai đoạn 0–8) và Kế hoạch Kỹ thuật trong Master Prompt (Phases 0–9)
Lộ trình trong GDD (Phần XVIII) thể hiện các giai đoạn thiết kế tính năng cấp cao (Design Roadmap). Trong khi đó, Master Prompt (`MASTER_PROMPT.md`) quy định 10 giai đoạn thực thi kỹ thuật chi tiết (Execution Phases 0–9) với các cổng nghiệm thu (exit gates) tuần tự nghiêm ngặt.

Mối tương quan giữa hai tài liệu được quy định rõ ràng như sau:

| Giai đoạn GDD (Design Roadmap) | Phase Master Prompt (Execution Phase) | Nội dung & Cổng nghiệm thu kỹ thuật |
|---|---|---|
| **Giai đoạn 0 — Kiểm tra repository** | **Phase 0 — Audit, scaffold, and reproducibility** | Kiểm tra engine, cấu hình conventions, sinh tài liệu kiến trúc/kế hoạch, xác thực baseline. |
| **Giai đoạn 1 — Nền tảng game** | **Phase 1 — Vertical slice: world, camera, time, UI** | Bản đồ isometric 64×64, ô thoi 32×16, camera, HUD, vượt qua **Visual-Validation Gate**. |
| **Giai đoạn 2 — Tài nguyên và công trình** | **Phase 2 — Authoritative resources, buildings, economy** | ResourceManager authoritative, đặt công trình, kho bãi, kiểm thử trừ nguyên liệu. |
| **Giai đoạn 3 — Dân cư và công việc** | **Phase 3 — Citizens, navigation, and real jobs** | 24 dân, quy chuẩn sprite 24×32 canvas (22–26px figure), tìm đường, JobSystem chung. |
| **Giai đoạn 4 — Tự động hóa** | **Phase 4 — Working logistics loop and basic automation** | Vận chuyển thực tế, quy tắc điều kiện/hành động, giải thích trạng thái dân. |
| **Giai đoạn 5 — Công nghệ và khám phá** | **Phase 5 — Research, exploration, fog of war, events** | Cây công nghệ, Fog of War, phế tích, phần thưởng persistent, world events. |
| **Giai đoạn 6 — Thế giới và xung đột** | **Phase 6 — Trading, factions, diplomacy, abstract battles** | Faction đối thủ, giao dịch nguyên tử, ngoại giao, BattleResolver tất định. |
| **Giai đoạn 7 — Chiến thắng, sụp đổ và save/load** | **Phase 7 — Population growth, crisis, victory, summaries**<br><br>**Phase 8 — Robust Save/Load & persistence hardening** | *Tách thành 2 phase kỹ thuật độc lập để bảo đảm an toàn dữ liệu:*<br>- **Phase 7:** Dân số ≥30, chu kỳ khủng hoảng, chiến thắng thịnh vượng giữ 5 ngày, tổng kết.<br>- **Phase 8:** Hệ thống Save/Load an toàn, schema versioning, chống dupe data, kiểm thử file hỏng. |
| **Giai đoạn 8 — Hoàn thiện và tối ưu** | **Phase 9 — Polish, asset integration, balance, release** | Hoàn thiện asset theo `docs/ASSET_STYLE_GUIDE.md` (yêu cầu Visual-Validation Gate), âm thanh, performance, Windows build. |

Hai hệ thống phân chia này hoàn toàn đồng nhất về mục tiêu: GDD giữ vai trò định hướng thiết kế và luật chơi, còn Master Prompt giữ vai trò kiểm soát quy trình lập trình và kiểm thử. Toàn bộ tính năng MVP, thứ tự phụ thuộc và tiêu chí nghiệm thu được bảo toàn tuyệt đối.

## Giai đoạn 0 — Kiểm tra repository

AI phải:

- Kiểm tra cấu trúc dự án hiện tại.
- Xác định engine và phiên bản.
- Kiểm tra scene, script và tài nguyên đã có.
- Báo cáo những phần đã hoạt động.
- Không ghi đè hoặc xóa dữ liệu hiện hữu nếu chưa cần thiết.
- Tạo kế hoạch triển khai dựa trên trạng thái thực tế.

**Tiêu chí hoàn thành:** dự án mở được và có kế hoạch rõ ràng.

## Giai đoạn 1 — Nền tảng game

Triển khai:

- Main menu.
- Tạo thế giới từ seed.
- Bản đồ thế giới 64 × 64 ô logic chiếu hình 2D Isometric (diamond tiles 32 × 16 pixel).
- Camera di chuyển và zoom (bộ lọc Nearest-Neighbor).
- Địa hình, cây cối, nhà chính và các công trình khởi đầu hiển thị phối cảnh 3/4 đúng Y-sorting.
- Con trỏ chuột hình thoi (hover/selection diamond highlight).
- Pause và tốc độ mô phỏng.
- **Cổng kiểm định thị giác (Visual-Validation Gate - Bắt buộc):** Tạo và xác nhận scene kiểm thử độc lập (`res://scenes/test/visual_validation_test.tscn`) gồm:
  1. Địa hình ô thoi 32 × 16 px (cỏ, nước, đường đất).
  2. Cây cối và đá tài nguyên phối cảnh isometric.
  3. Ít nhất một công trình hoàn chỉnh thể hiện rõ mặt mái và mặt tiền hướng Tây Nam / Đông Nam.
  4. Một cư dân di chuyển thực tế trên lưới.
  5. Khung highlight hình thoi bám chuột chính xác.
  6. Phân tầng Y-sorting hoàn hảo (cư dân đi ra sau và ra trước công trình/cây cối được che khuất/nổi lên đúng thực tế).

**Tiêu chí hoàn thành:** tạo được một thế giới mới, tương tác với bản đồ isometric và vượt qua Cổng kiểm định thị giác (Visual-Validation Gate).

## Giai đoạn 2 — Tài nguyên và công trình

Triển khai:

- ResourceManager.
- Kho chứa.
- Công trình.
- Đặt công trình.
- Chi phí xây dựng.
- Sản xuất và tiêu thụ.
- HUD tài nguyên.

**Tiêu chí hoàn thành:** công trình và tài nguyên hoạt động thực sự.

## Giai đoạn 3 — Dân cư và công việc

Triển khai:

- 24 dân.
- Di chuyển.
- Tìm đường.
- Phân công nghề.
- Công việc.
- Sản xuất.
- Vận chuyển.
- Nhu cầu cơ bản.

**Tiêu chí hoàn thành:** dân thực hiện công việc trên bản đồ và tạo ra thay đổi kinh tế thật.

## Giai đoạn 4 — Tự động hóa

Triển khai:

- Quy tắc điều kiện/hành động.
- Ưu tiên công việc.
- Giao việc thủ công.
- Xử lý kho đầy.
- Xử lý thiếu thức ăn.
- Trạng thái giải thích công việc.

**Tiêu chí hoàn thành:** dân có thể tự xử lý một số tình huống mà không cần người chơi liên tục ra lệnh.

## Giai đoạn 5 — Công nghệ và khám phá

Triển khai:

- Cây công nghệ.
- Chi phí và tiến độ.
- Phế tích.
- Tài nguyên đặc biệt.
- Fog of War.
- Phần thưởng khám phá.

**Tiêu chí hoàn thành:** khám phá và nghiên cứu làm thay đổi chiến lược.

## Giai đoạn 6 — Thế giới và xung đột

Triển khai:

- Hai vương quốc đối thủ.
- Khu định cư trung lập.
- Giao dịch.
- Quan hệ ngoại giao.
- Quân đội đơn giản.
- Battle Resolver.
- Sự kiện khủng hoảng.

**Tiêu chí hoàn thành:** thế giới có những thách thức không chỉ đến từ việc quản lý công trình.

## Giai đoạn 7 — Chiến thắng, sụp đổ và save/load

Triển khai:

- Điều kiện thịnh vượng.
- Trạng thái khủng hoảng.
- Sụp đổ.
- Tổng kết.
- Save/load.
- Legacy cơ bản.
- Chống nhận thưởng trùng.

**Tiêu chí hoàn thành:** chơi được trọn vẹn từ đầu đến cuối.

## Giai đoạn 8 — Hoàn thiện và tối ưu

Triển khai:

- Sửa lỗi.
- Kiểm thử.
- Thay thế asset tạm bằng asset hoàn thiện theo quy chuẩn `docs/ASSET_STYLE_GUIDE.md`. Điều kiện tiên quyết: Bắt buộc phải vượt qua Cổng kiểm định thị giác (Visual-Validation Gate) trước khi sản xuất hoặc tích hợp số lượng lớn asset đồ họa.
- Cải thiện giao diện.
- Tối ưu hiệu năng.
- Thêm âm thanh và hoạt ảnh cần thiết.
- Kiểm tra các trường hợp biên.

Không thêm các hệ thống lớn mới ở giai đoạn này nếu còn lỗi trong vòng chơi cốt lõi.

---

# PHẦN XIX — QUY TẮC LÀM VIỆC BẮT BUỘC CHO AI

1. Đọc tài liệu trước khi thay đổi dự án.
2. Chỉ triển khai một giai đoạn hoặc một nhóm tính năng liên quan trong mỗi bước.
3. Trước khi sửa nhiều file, giải thích ngắn gọn mục tiêu và phạm vi thay đổi.
4. Không viết lại toàn bộ dự án chỉ để sửa một lỗi nhỏ.
5. Không tạo giao diện giả cho tính năng được mô tả là đã hoàn thành.
6. Không dùng dữ liệu giả thay cho hệ thống mô phỏng thật, trừ khi đang xây một test fixture được ghi rõ.
7. Sau mỗi giai đoạn, chạy dự án và kiểm tra lỗi.
8. Viết kiểm thử cho logic tài nguyên, công việc, tự động hóa, save/load và chiến thắng.
9. Không xóa file hoặc thay đổi cấu trúc quan trọng mà không hiểu tác động.
10. Không hardcode các giá trị cân bằng trong nhiều file.
11. Không để UI trực tiếp sửa trạng thái game ngoài các API đã định.
12. Không thêm phụ thuộc bên ngoài nếu chưa chứng minh được sự cần thiết.
13. Không gọi API AI trong vòng mô phỏng chính.
14. Không tuyên bố một tính năng hoàn thành nếu chưa kiểm tra hoạt động thực tế.
15. Khi gặp lỗi, xác định nguyên nhân trước khi thêm workaround.
16. Nếu yêu cầu mới xung đột với GDD, chỉ ra xung đột và đề xuất cách giải quyết.
17. Duy trì Git commit hoặc checkpoint sau mỗi giai đoạn ổn định.
18. Ưu tiên tính đúng đắn, khả năng kiểm thử và khả năng mở rộng hơn việc tạo nhiều file nhanh chóng.

---

# PHẦN XX — MASTER PROMPT ĐƯA CHO AI VIBE CODING

Bạn là Senior Game Developer, Technical Designer và QA Engineer chịu trách nhiệm triển khai một game 2D isometric / dimetric pixel-art kingdom simulation (three-quarter top-down view, tuyệt đối không dùng flat overhead 90°) theo GDD đính kèm.

Mục tiêu là xây dựng một MVP có thể chơi hoàn chỉnh, không phải một bản demo giao diện.

## Nhiệm vụ

1. Đọc toàn bộ GDD.
2. Kiểm tra repository hiện tại trước khi sửa.
3. Xác định công nghệ và kiến trúc phù hợp với dự án hiện có.
4. Lập kế hoạch triển khai theo các giai đoạn trong GDD.
5. Triển khai lần lượt, kiểm thử sau từng giai đoạn.
6. Duy trì trạng thái game nhất quán.
7. Không bỏ qua các yêu cầu save/load, tự động hóa và kiểm thử.

## Yêu cầu chất lượng

- Game phải khởi động được.
- Người chơi phải có thể tương tác với bản đồ.
- Dân phải thực sự thực hiện công việc.
- Tài nguyên phải được sản xuất và tiêu thụ bởi các hệ thống thật.
- Công trình phải có chi phí và trạng thái.
- Tự động hóa phải thực thi điều kiện và hành động thật.
- Pause phải dừng mô phỏng.
- Save/load phải khôi phục đúng trạng thái.
- Chiến thắng và thất bại phải được quyết định bởi logic game.
- Game phải hoạt động mà không cần dịch vụ AI bên ngoài.
- Lỗi phải được ghi nhận và xử lý rõ ràng.

## Quy tắc triển khai

Không tạo tất cả tính năng cùng lúc.

Bắt đầu bằng việc kiểm tra repository và báo cáo:

- Engine và phiên bản.
- Cấu trúc hiện tại.
- Những tính năng đã có.
- Những lỗi hoặc rủi ro đã phát hiện.
- Giai đoạn đầu tiên cần triển khai.
- Các file dự kiến sẽ tạo hoặc sửa.

Sau khi có kế hoạch, thực hiện giai đoạn đầu tiên. Kiểm tra dự án chạy được trước khi tiếp tục.

Không tự ý mở rộng phạm vi. Không thêm multiplayer, hệ thống di truyền phức tạp, chiến thuật quân sự nâng cao hoặc AI điều khiển thế giới khi chưa hoàn thành MVP.

Nếu phải lựa chọn giữa nhiều cách triển khai, chọn cách đơn giản nhất đáp ứng đầy đủ yêu cầu, dễ kiểm thử và không cản trở mở rộng.

Mọi giá trị cân bằng phải được lưu ở cấu hình tập trung. Mọi thay đổi tài nguyên phải đi qua hệ thống quản lý tài nguyên. Mọi thực thể quan trọng phải có ID ổn định. Các hành động có thể gây thay đổi lớn phải có kiểm tra điều kiện trước khi thực thi.

Sau mỗi giai đoạn, cung cấp báo cáo gồm:

1. Tính năng đã hoàn thành.
2. File đã tạo hoặc sửa.
3. Cách kiểm thử.
4. Kết quả kiểm thử.
5. Lỗi còn tồn tại.
6. Giai đoạn tiếp theo.

Không được tuyên bố hoàn thành nếu chưa chạy và kiểm tra dự án.

**Bắt đầu ngay bằng việc kiểm tra repository và thực hiện Giai đoạn 0. Không triển khai toàn bộ game trong một lần.**

---

# KẾT THÚC TÀI LIỆU

Đây là nguồn yêu cầu chính cho MVP. Khi cần thay đổi phạm vi hoặc thông số, hãy cập nhật tài liệu thay vì để logic trong code và tài liệu bị mâu thuẫn.