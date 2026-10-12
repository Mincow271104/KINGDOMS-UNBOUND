# KINGDOMS UNBOUND — Đánh giá GDD v1.0 và đề xuất chỉnh sửa

## 1. Kết luận

GDD có cấu trúc tốt, tư duy hệ thống khá vững và phù hợp làm nguồn yêu cầu cho AI coding. Tuy nhiên, phạm vi được gọi là “MVP” đang lớn: world generation, 24 citizen agents, needs/lifecycle, pathfinding, job scheduler, hauling/reservations, buildings, production/consumption, automation rule engine, research, fog of war, events, traders, diplomacy, rival factions, battles, victory/collapse, save/load, achievements/Legacy, UI nhiều bảng và test tự động. Các hệ thống tương tác nhau nên rủi ro chính là lỗi xuyên hệ thống, không chỉ là lỗi cú pháp.

Điểm đánh giá (ước lượng chuyên môn, không phải benchmark):

- Độ rõ ràng/ tổ chức của GDD: 8/10.
- Độ khó nếu hoàn thiện toàn bộ GDD: 9/10.
- Độ phù hợp với vibe coding khi chia milestone: 7/10.
- Mức độ phù hợp nếu giao một prompt và yêu cầu sinh toàn bộ một lần: thấp.

## 2. Tỉ lệ thành công tham khảo

Đây là các ước lượng để lập kế hoạch; không phải xác suất thống kê được đo trên Antigravity/Gemini.

| Mục tiêu | Ước lượng |
|---|---:|
| Project Godot mở/chạy, có menu, map và HUD | 80–95% |
| Vertical slice với citizen, job và kinh tế cơ bản chơi được | 60–80% |
| Game lõi tương đối ổn định sau nhiều lượt sửa/test và cắt gọn phạm vi đầu tiên | 40–60% |
| Toàn bộ GDD v1.0 đúng và hoạt động khi chỉ giao AI tự làm | 15–30% |
| Đạt chất lượng hoàn chỉnh bằng một prompt khổng lồ trong một lượt | 5–15% |

Thành công nên được định nghĩa là “các acceptance tests đã chạy và qua”, không phải AI đã tạo nhiều file hoặc báo “done”.

## 3. Điểm tốt nên giữ nguyên

- UI không được sửa trực tiếp dữ liệu tài nguyên.
- Mọi thay đổi tài nguyên đi qua một hệ thống có thẩm quyền.
- Entity dùng ID ổn định, không dùng index mảng làm ID dài hạn.
- Simulation time tập trung; Pause phải dừng mọi tiến trình simulation.
- Automation là gameplay thật, không phải menu trang trí.
- Save/load phải phục hồi trạng thái, không chạy lại khởi tạo thế giới hoặc trao thưởng lần nữa.
- Test/acceptance criteria được viết ngay trong GDD.
- MVP ưu tiên hệ thống ít nhưng chơi được; chưa thêm multiplayer, AI tạo sinh trong gameplay, mod và hệ thống quy mô lớn.

## 4. Mâu thuẫn/thiếu quy tắc cần giải quyết

| Vấn đề trong GDD | Rủi ro | Đề xuất |
|---|---|---|
| Phân công ban đầu có 2 Miner, 2 Researcher, 2 Guard, nhưng không có Mine, Research Hall hay Barracks trong danh sách công trình đã xây sẵn. | Citizen đứng chờ, job vô hiệu, AI sửa bằng workaround. | Starter allocation: 5 Farmer, 4 Woodcutter, 3 Builder, 3 Hauler, 9 Idle; chỉ mở nghề khi nơi làm việc tồn tại. Ghi đây là quyết định mặc định. |
| Starting resource quantities xuất hiện đồng thời với danh sách công trình đã có sẵn. | Có thể trừ tiền/vật liệu xây starter buildings lần thứ hai. | Xem số tài nguyên trong bảng là kho ban đầu sau khi khu định cư đã được xây. |
| Farmer 5 × 5 = 25 Food/ngày, nhưng tiêu thụ 19.2; mùa bất lợi chỉ còn 12.5. | Có thể thiếu hụt Food tùy thời điểm bắt đầu và thời gian kéo dài khủng hoảng. | Quy định mùa đầu, modifier từng mùa, thời điểm tick, ngưỡng cảnh báo và thời gian trước khi hậu quả nặng lên. |
| Win cần dân số ≥30 nhưng khởi đầu 24. Cơ chế sinh/nhập cư mới mô tả xác suất. | Win có thể khó tái hiện hoặc phụ thuộc may rủi. | Định nghĩa immigration có điều kiện, nhịp độ và test bảo đảm con đường chiến thắng khả thi. |
| Collapse được định nghĩa bằng “không còn khả năng duy trì chính quyền”. | Agent tự chế các điều kiện khác nhau; game-over khó kiểm thử. | Viết các điều kiện cụ thể, thời lượng phải duy trì, khả năng cứu vãn và thông báo giải thích. |
| GDD nói về storage capacity, resources in transit, reservations nhưng chưa quyết định inventory nằm ở đâu. | Nhân đôi tài nguyên, hàng teleport, vật liệu bị giữ mãi khi job fail. | Chốt mô hình kho cục bộ/trung tâm, reservation/release, local buffers và quy tắc nhập/xuất. |
| Mỗi nghề có logic khác nhau nhưng job lifecycle chưa định nghĩa cách claim/release/unreachable. | Dân đổi việc vô hạn hoặc hai dân làm cùng một job. | Dùng shared JobSystem với trạng thái Available → Reserved → In Progress → Completed/Failed/Cancelled. |
| Giao dịch có route risk nhưng không có spec chi tiết cho đường đi, biên giới hay logistics thương nhân. | Agent xây hệ thống quá lớn hoặc tạo UI giả. | Thương mại nguyên tử, hàng hữu hạn và faction AI trừu tượng trước; mọi giả lập phải được ghi rõ. |
| Legacy được mô tả là cosmetic-only nhưng có mặt trong phase hoàn thiện MVP. | Kéo dài thời gian trước khi vòng chơi lõi ổn định. | Hoãn shop và Legacy cho đến khi game loop, save/load, victory/collapse ổn định; không xóa khỏi backlog. |
| 20 mục “bắt buộc MVP” bao gồm gần như toàn bộ hệ thống lớn. | Agent cố làm mọi thứ song song, sinh code lớn nhưng không tích hợp. | Các phase là cổng nghiệm thu tuần tự; không bắt đầu feature-heavy phase kế tiếp khi gate hiện tại chưa qua. |
| Yêu cầu tạo pixel assets chưa định nghĩa rõ frame size, palette, collision footprint, import filtering. | Assets có vẻ đẹp nhưng không ghép sprite/animation hoặc không khớp tile grid. | Tạo Asset Style Guide, sinh theo batch nhỏ, kiểm tra kích thước/frame và xem trong engine trước khi nhân rộng. |

## 5. Thứ tự triển khai khuyên dùng

### Vertical slice đầu tiên

1. Godot project chạy được; main menu, tạo thế giới theo seed, map 64×64, camera, pause và tốc độ.
2. Tài nguyên và công trình ban đầu; quy tắc xây dựng và HUD.
3. Citizen ID, grid pathfinding, job state machine, chọn dân/giao việc.
4. Farm + Woodcutter + food upkeep, storage/capacity và logistics theo mô hình đã chốt.
5. Automation cơ bản và giải thích tại sao dân đang làm/không làm việc.
6. Save/load đủ trạng thái và test không nhân đôi.

Đừng thêm faction, diplomacy, full lifecycle, Legacy hay polish hàng loạt trước khi vòng lặp này hoạt động.

### Sau vertical slice

7. Research, exploration, fog of war và events.
8. Trade/factions/diplomacy/abstract battles.
9. Immigration, victory/collapse, world summary và Legacy tối giản.
10. Visual polish, audio, hiệu năng, stress tests và Windows release build.

Thứ tự này là thứ tự kỹ thuật, không phải tự ý loại bỏ yêu cầu. Những phần hoãn phải còn trong backlog và cuối cùng phải có test hoặc được đánh dấu rõ là ngoài MVP nếu thay đổi phạm vi được chấp thuận.

## 6. Quy tắc nghiệm thu

Mỗi feature phải có:

1. Hành vi mong đợi rõ ràng.
2. Ít nhất một test logic nếu có state/rules.
3. Kiểm tra runtime nếu liên quan scene, animation, input hay navigation.
4. Bằng chứng: command, exit code, log, screenshot hoặc bước tái hiện.
5. Backlog/Worklog cập nhật.

Không được coi menu có nút là hoàn thành gameplay. Không được coi headless test là đã xác minh chất lượng hình ảnh. Không được coi screenshot là bằng chứng dữ liệu kinh tế/save-load đúng.

## 7. Antigravity và công cụ test

- Dùng `/goal` nếu phiên bản Antigravity đang chạy có hỗ trợ lệnh đó; tài liệu chính thức mô tả nó là chạy mục tiêu đến khi hoàn tất mà không cần hỏi input trung gian.
- Dùng Godot MCP để inspect/launch/điều khiển game/chụp screenshot nếu kết nối thực sự hoạt động.
- Giữ đường fallback bằng Godot command-line/headless để xác thực project và chạy test; đánh dấu kiểm tra thị giác/interactive là chưa xác minh khi không có MCP.
- Chốt Godot version thật trước khi chọn APIs. Với các bản Godot 4 hiện tại, `TileMapLayer` là lựa chọn nên xem xét thay cho `TileMap` đã deprecated; phải xác minh theo version đã cài.
- Tất cả công cụ ngoài game phải miễn phí; game runtime không phụ thuộc dịch vụ AI.

## 8. Cách dùng file Master Prompt

Dùng `MASTER_PROMPT.md` cùng GDD gốc trong một workspace riêng. Nếu Antigravity hỗ trợ `/goal`, có thể prefix prompt bằng `/goal`. Quy trình thực thi trong `MASTER_PROMPT.md` chia thành 10 Phase kỹ thuật (Phases 0–9, trong đó Save/Load được tách riêng thành Phase 8 độc lập để bảo đảm an toàn dữ liệu, khớp hoàn toàn với 9 Giai đoạn 0–8 cấp cao trong GDD). Để agent thực sự làm việc lâu dài, mọi tiến độ phải được ghi vào `docs/BACKLOG.md`, `docs/WORKLOG.md`, `docs/TEST_PLAN.md` và `docs/KNOWN_ISSUES.md`; quota, lỗi công cụ hoặc phiên agent kết thúc vẫn có thể ngắt công việc, nên prompt không thể bảo đảm chạy vô hạn.
