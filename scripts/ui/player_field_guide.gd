class_name PlayerFieldGuide
extends Control
## In-Game Player Field Guide & 30-Day Starter Manual (Package 2D).
## Authoritative Vietnamese in-game encyclopedia and non-linear reference manual.
## Opening/closing does NOT alter world state, simulation clock, or economy parameters.

signal guide_opened
signal guide_closed
signal chapter_selected(chapter_index: int)

const TOTAL_CHAPTERS: int = 6

const CHAPTER_TITLES: Array[String] = [
	"Chương A: Khởi Đầu Vương Quốc",
	"Chương B: Dân Cư & Nghề Nghiệp",
	"Chương C: Xây Dựng & Chuỗi Sản Xuất",
	"Chương D: Hướng Dẫn 30 Ngày Đầu Tiên",
	"Chương E: Sự Kiện, Ngoại Giao & Quân Đội",
	"Chương F: Chiến Thắng, Sụp Đổ & Di Sản"
]

const CHAPTER_SUBTITLES: Array[String] = [
	"Giao diện điều khiển, chu kỳ thời gian và thiết lập khu định cư ban đầu",
	"Nghề nghiệp, chỉ số sinh tồn và tiến trình kỹ năng 5 cấp độ (Package 2B)",
	"Quy hoạch công trình, kho đệm nội bộ và cơ chế vận chuyển của Hauler",
	"Lịch 40 ngày/năm, chu kỳ mùa lương thực và lộ trình sinh tồn 4 giai đoạn",
	"Biến cố thế giới, mạng lưới ngoại giao, chợ giao thương và rủi ro quân sự",
	"Chiến thắng Phồn Vinh, điều kiện sụp đổ và chuyển đổi ngân khố (Package 2C)"
]

const CHAPTER_TEXTS: Array[String] = [
	# Chương A
	"""[color=#ffd700][b]1. VAI TRÒ CỦA NGƯỜI CHƠI[/b][/color]
Trong KINGDOMS UNBOUND, bạn là người dẫn dắt khu định cư từ một nhóm dân di cư nhỏ bé vươn lên thành một vương quốc phồn thịnh. Bạn chịu trách nhiệm quy hoạch công trình, phân công việc làm, bảo đảm chuỗi cung ứng lương thực, phòng thủ và ngoại giao với các thế lực lân cận.

[color=#ffd700][b]2. CÁCH ĐỌC THANH GIAO DIỆN (HUD)[/b][/color]
[b]• Thanh thông tin trên đỉnh (TopBar):[/b]
  - [color=#66ccff]Đồng hồ & Ngày tháng:[/color] Giờ trong ngày (06:00 đến 21:00 lao động ban ngày, ban đêm nghỉ ngơi), Ngày (1–40), Mùa hiện tại và Năm.
  - [color=#66ccff]Điều khiển tốc độ:[/color] Tạm dừng ([b]⏸[/b]), [b]1x[/b] (chuẩn), [b]2x[/b] (nhanh), [b]3x[/b] (tối đa).
  - [color=#66ccff]Dải tài nguyên kho trung tâm:[/color]
    🌾 Lương thực: Nguồn sống hàng ngày của dân cư.
    🪵 Gỗ & 🪨 Đá: Vật liệu cơ bản để dựng nhà và công trình.
    ⛏️ Quặng thô: Khoáng sản để luyện kim.
    ⚔️ Kim loại: Dùng rèn công cụ và vũ khí.
    🛠️ Công cụ: Tăng năng suất lao động và duy trì sản xuất.
    🪙 Vàng: Ngân khố quốc gia dùng trả lương, thương mại và đổi Di Sản.
    👥 Dân số: Số dân hiện tại / Sức chứa nhà ở tối đa.

[b]• Thanh tác vụ đáy màn hình (BottomBar):[/b]
  - [color=#66ccff]Thông tin ô đất:[/color] Tọa độ (x, y), kiểu địa hình (Cỏ, Đất, Rừng, Nước, Đá) và công trình trên ô.
  - [color=#66ccff]Các nút chức năng chính:[/color]
    🏗️ [b]Xây Dựng (B)[/b] | 🔬 [b]Nghiên Cứu (T)[/b] | 👑 [b]Ngoại Giao (Y)[/b] | ⚔️ [b]Quân Đội (U)[/b] | ⚙️ [b]Tự Động (G)[/b]
    📖 [b]Cẩm Nang (H)[/b]: Mở cuốn sổ tay này bất cứ lúc nào.

[color=#ffd700][b]3. THIẾT LẬP KHU ĐỊNH CƯ BAN ĐẦU (DỮ LIỆU THỰC TẾ)[/b][/color]
Khi bước vào thế giới mới, vương quốc của bạn đã có sẵn nền móng vững chắc:
• [b]Dân số ban đầu: 24 công dân[/b], bao gồm:
  - 5 Nông dân (Farmer)
  - 4 Tiều phu (Woodcutter)
  - 3 Thợ xây (Builder)
  - 3 Người vận chuyển (Hauler)
  - 9 Công dân nhàn rỗi (Idle) sẵn sàng nhận việc mới.
• [b]Công trình ban đầu: 8 công trình[/b], gồm:
  - 1 Tòa thị chính (Town Hall, 3×3 ô): Trung tâm hành chính, tăng sức chứa kho.
  - 1 Nhà kho trung tâm (Storehouse, 2×2 ô): Kho trữ vật phẩm chính.
  - 4 Nhà ở (House, 2×2 ô): Chỗ cư trú ấm áp cho toàn bộ 24 dân cư.
  - 1 Nông trại (Farm, 2×2 ô): Sản xuất Lương thực.
  - 1 Trại đốn gỗ (Woodcutter, 2×2 ô): Khai thác gỗ từ cây cối quanh vùng.
• [b]Tài nguyên xuất phát trong kho trung tâm:[/b]
  - Lương thực: [b]150[/b] | Gỗ: [b]120[/b] | Đá: [b]60[/b]
  - Quặng thô: [b]0[/b] | Kim loại: [b]20[/b] | Công cụ: [b]15[/b]
  - Pha lê ma thuật: [b]5[/b] | Thảo mộc: [b]10[/b] | Vàng ngân khố: [b]200[/b]

[color=#ffd700][b]4. QUAN SÁT CÔNG DÂN VÀ CÔNG TRÌNH[/b][/color]
• Nhấp chuột trái vào bất kỳ công dân nào để mở bảng thanh tra: xem tên tuổi, nghề nghiệp, thanh nhu cầu (Đói, Mệt mỏi, Sức khỏe, Tinh thần) và tiến độ kỹ năng nghề.
• Nhấp vào công trình để kiểm tra tình trạng vận hành, số công nhân đang làm việc và lượng hàng đang tích trong kho đệm nội bộ.""",

	# Chương B
	"""[color=#ffd700][b]1. NGHỀ NGHIỆP VÀ TRÁCH NHIỆM[/b][/color]
Mỗi công dân trong vương quốc đảm nhiệm một vai trò thiết yếu:
• [b]Nông dân (Farmer):[/b] Chăm sóc đồng ruộng tại Nông trại, tạo ra Lương thực nuôi sống vương quốc.
• [b]Tiều phu (Woodcutter):[/b] Đốn hạ cây cối trong bán kính làm việc, cung cấp Gỗ xây dựng.
• [b]Thợ đá / Thợ mỏ (Miner / Quarryman):[/b] Khai thác Đá tại Mỏ đá (Quarry) hoặc Quặng tại Mỏ quặng (Mine).
• [b]Thợ rèn / Chế tác (Smith):[/b] Luyện Kim loại từ quặng và chế tạo Công cụ tại Xưởng thợ (Workshop).
• [b]Thợ xây (Builder):[/b] Tiếp nhận vật liệu và thi công các công trình đang đặt móng.
• [b]Người vận chuyển (Hauler):[/b] Nhận hàng từ kho đệm của các nơi sản xuất, gánh về lưu trữ tại Kho trung tâm.
• [b]Công dân nhàn rỗi (Idle):[/b] Chưa có việc làm cố định; bạn có thể chuyển họ sang bất kỳ nghề nào qua bảng thanh tra công dân.

[color=#ffd700][b]2. CHỈ SỐ SINH TỒN VÀ SỨC KHỎE[/b][/color]
• [color=#ff9966]Đói (Hunger):[/color] Tích lũy liên tục khi công dân làm việc. Khi đói, công dân sẽ tự đến Nhà kho tìm thức ăn. Nếu kho cạn kiệt, đói tăng kịch trần (100) sẽ gây kiệt sức và dẫn tới tử vong.
• [color=#ff9966]Mệt mỏi (Fatigue):[/color] Tăng theo giờ lao động. Hết ca làm việc, công dân về Nhà ở để ngủ hồi phục thể lực.
• [color=#ff9966]Sức khỏe (Health) & Tinh thần (Morale):[/color] Duy trì ở mức cao giúp công dân di chuyển nhanh và làm việc hiệu quả. Mất nhà cửa hoặc thiếu ăn kéo dài sẽ làm suy giảm nghiêm trọng.

[color=#ffd700][b]3. SÁU KỸ NĂNG NGHỀ NGHIỆP (PACKAGE 2B PROGRESSION)[/b][/color]
Mỗi công dân sở hữu điểm kinh nghiệm (XP) riêng biệt trên 6 nghề:
  1. [b]Nông nghiệp (Farming)[/b] — Tăng tốc độ canh tác và sản xuất lương thực.
  2. [b]Lâm nghiệp (Woodcutting)[/b] — Tăng tốc độ đốn hạ và gom gỗ.
  3. [b]Khai khoáng (Mining)[/b] — Tăng tốc độ khai thác đá và quặng thô.
  4. [b]Rèn & Chế tác (Smithing)[/b] — Tăng tốc độ luyện kim và chế tạo công cụ.
  5. [b]Xây dựng (Building)[/b] — Đẩy nhanh tốc độ thi công công trình.
  6. [b]Vận chuyển (Hauling)[/b] — Tăng tốc độ di chuyển và hiệu quả bốc dỡ hàng hóa.

[color=#ffd700][b]4. CƠ CHẾ TĂNG KỸ NĂNG VÀ HỆ SỐ HIỆU SUẤT[/b][/color]
Kỹ năng tăng lên thông qua [b]lao động thực tế[/b]: mỗi chu kỳ hoàn thành sản phẩm, cuốc đất, đốn gỗ, nung kim loại, thi công móng hay mỗi chuyến gánh hàng đều tích lũy XP trực tiếp cho công dân đó.

[b]Bảng cấp độ và hệ số chuẩn xác theo CitizenSkillData:[/b]
  • [color=#99e699]Cấp 1 (Tập sự):[/color] 0 – 99 XP | Hệ số: [b]1,00×[/b] (+0% hiệu suất)
  • [color=#99e699]Cấp 2 (Học việc):[/color] 100 – 299 XP | Hệ số: [b]1,08×[/b] (+8% hiệu suất)
  • [color=#99e699]Cấp 3 (Thợ lành nghề):[/color] 300 – 599 XP | Hệ số: [b]1,16×[/b] (+16% hiệu suất)
  • [color=#99e699]Cấp 4 (Chuyên gia):[/color] 600 – 999 XP | Hệ số: [b]1,25×[/b] (+25% hiệu suất)
  • [color=#ffd700]Cấp 5 (Bậc thầy):[/color] 1.000 XP (Tối đa) | Hệ số: [b]1,35×[/b] ([b]+35% hiệu suất tối đa[/b])

[color=#ffd700][b]5. VÌ SAO CÔNG DÂN TAY NGHỀ CAO RẤT QUÝ GIÁ?[/b][/color]
Một công dân Bậc thầy (Cấp 5) tạo ra sản lượng nhanh hơn 35% so với người mới vào nghề. Bảo vệ tính mạng và giữ chân những thợ lành nghề lâu năm là chìa khóa để vương quốc bứt phá kinh tế.""",

	# Chương C
	"""[color=#ffd700][b]1. CÁCH ĐẶT CÔNG TRÌNH VÀ QUY TẮC HỢP LỆ[/b][/color]
Nhấn phím [b]B[/b] hoặc nút [b]🏗️ Xây Dựng[/b] trên thanh đáy để mở danh mục công trình:
• [b]Diện tích mặt bằng:[/b] Nhà dân, Kho, Nông trại, Trại gỗ, Mỏ đá (2×2 ô); Tháp canh, Tường rào (1×1 ô); Tòa thị chính, Doanh trại, Chợ, Viện nghiên cứu (3×3 ô).
• [b]Điều kiện hợp lệ:[/b] Ô đất phải bằng phẳng (Cỏ/Đất), không ngập nước, không có vật cản rắn và không chồng lấn lên công trình hiện hữu.
• Khi đặt móng, tài nguyên xây dựng tương ứng sẽ được tự động giữ chỗ (reserve) trong kho trung tâm để tránh tình trạng thiếu hụt giữa chừng.

[color=#ffd700][b]2. TIẾN ĐỘ THI CÔNG VÀ LAO ĐỘNG CỦA BUILDER[/b][/color]
Khi được đặt, công trình ở trạng thái [b]Đang xây dựng (under_construction)[/b]:
• Cần có Thợ xây (Builder) di chuyển đến công trường để lao động.
• Tiến độ tăng dần từ 0% đến 100%. Kỹ năng Xây dựng của Builder càng cao thì công trình càng nhanh khánh thành và đưa vào sử dụng.

[color=#ffd700][b]3. KHO ĐỆM NƠI LÀM VIỆC VS KHO TRUNG TÂM (ĐẶC BIỆT LƯU Ý)[/b][/color]
Đây là nguyên lý logistics cốt lõi nhất của KINGDOMS UNBOUND:
• Mọi cơ sở sản xuất (Nông trại, Trại gỗ, Mỏ đá, Mỏ quặng, Xưởng thợ) đều có một [b]Kho đệm nội bộ (Local Buffer)[/b].
• Khi nông dân thu hoạch lúa hay tiều phu đốn gỗ, sản phẩm sẽ được xếp vào kho đệm của chính công trình đó trước.

[color=#ff6666][b]⚠️ NGUYÊN TẮC BẮT BUỘC PHẢI NHỚ:[/b][/color]
[color=#ffff99]Tài nguyên đang nằm trong kho đệm nội bộ [b]CHƯA PHẢI[/b] là tài nguyên sẵn có của vương quốc! Bạn [b]KHÔNG THỂ[/b] dùng số hàng này để dựng công trình mới, nung đúc hay nuôi sống dân cư.[/color]

[color=#ffd700][b]4. VAI TRÒ SỐNG CÒN CỦA NGƯỜI VẬN CHUYỂN (HAULER)[/b][/color]
• Chỉ khi người vận chuyển ([b]Hauler[/b]) đến tận nơi, bốc dỡ hàng từ kho đệm và gánh về [b]Kho trung tâm (Storehouse/Townhall)[/b], số tài nguyên đó mới chính thức xuất hiện trên dải HUD để bạn sử dụng.
• [b]Hiện tượng Đầy kho đệm (Buffer Saturation):[/b] Nếu bạn không phân bổ đủ Hauler, kho đệm sẽ bị đầy tràn (50–100 đơn vị). Khi kho đệm đầy, công nhân tại đó sẽ buộc phải ngừng việc hoàn toàn!
• Hãy luôn duy trì ít nhất 3–5 Hauler và tăng thêm khi mở rộng sản xuất.

[color=#ffd700][b]5. SỨC CHỨA KHO VÀ MỞ RỘNG[/b][/color]
Kho trung tâm có giới hạn chứa đồ (Base capacity). Xây thêm Nhà kho (Storehouse) sẽ gia tăng đáng kể sức chứa cho các nhóm tài nguyên cơ bản (Lương thực, Gỗ, Đá).""",

	# Chương D
	"""[color=#ffd700][b]1. LỊCH 40 NGÀY MỖI NĂM VÀ HỆ SỐ MÙA THỰC PHẨM[/b][/color]
Vương quốc vận hành theo chu kỳ một năm gồm đúng [b]40 ngày[/b], chia đều làm 4 mùa (mỗi mùa 10 ngày):

[table=3]
[cell][b]Mùa Trong Năm[/b][/cell][cell][b]Khung Ngày[/b][/cell][cell][b]Hệ Số Nông Trại[/b][/cell]
[cell]🌸 Mùa Xuân (Spring)[/cell][cell]Ngày 1 – 10[/cell][cell][color=#99e699][b]1,0×[/b] (Chuẩn)[/color][/cell]
[cell]☀️ Mùa Hè (Summer)[/cell][cell]Ngày 11 – 20[/cell][cell][color=#ffd700][b]1,2×[/b] (+20% bội thu)[/color][/cell]
[cell]🍂 Mùa Thu (Autumn)[/cell][cell]Ngày 21 – 30[/cell][cell][color=#99e699][b]1,0×[/b] (Chuẩn)[/color][/cell]
[cell]❄️ Mùa Đông (Winter)[/cell][cell]Ngày 31 – 40[/cell][cell][color=#ff6666][b]0,5×[/b] (-50% giá rét)[/color][/cell]
[/table]

[color=#ffff99][b]LƯU Ý QUAN TRỌNG:[/b] Hệ số mùa [b]CHỈ ÁP DỤNG DUY NHẤT[/b] cho sản lượng Lương thực của Nông trại (Farm). Sản lượng Gỗ, Đá, Quặng thô và Kim loại tại các mỏ xưởng [b]hoàn toàn không bị suy giảm[/b] theo mùa.[/color]

[color=#ffd700][b]2. HƯỚNG DẪN CHIẾN LƯỢC 4 GIAI ĐOẠN ĐẦU TIÊN[/b][/color]

[b]• Giai đoạn 1: Ngày 1 – 10 (Mùa Xuân — Ổn định và Quan sát)[/b]
  - Kho xuất phát có 150 Lương thực. Với 24 dân cư tiêu thụ khoảng 24 lương thực/ngày, số dự trữ này chỉ đủ ăn trong khoảng 6 ngày nếu không có nguồn tiếp tế.
  - Đảm bảo 5 Nông dân làm việc liên tục tại Farm và ít nhất 3 Hauler gánh lương thực về kho đều đặn.
  - Sử dụng 4 Tiều phu đốn gỗ để tích lũy vật liệu dựng thêm công trình.
  - Dùng 3 Builder khởi công xây thêm 1 Mỏ đá (Quarry) để tự chủ nguồn đá.

[b]• Giai đoạn 2: Ngày 11 – 20 (Mùa Hè — Bội thu và Tăng tốc)[/b]
  - Nông trại đạt hiệu suất đỉnh cao [b]1,2×[/b]. Lúa chín nhanh và sản lượng dồi dào.
  - [color=#ffcc66]Mối nguy lớn nhất:[/color] Kho đệm của Farm rất dễ bị đầy tràn! Hãy lập tức phân công thêm 1–2 Hauler từ nhóm nhàn rỗi để giải tỏa kho đệm nông trại.
  - Đặt móng xây dựng Xưởng thợ (Workshop) và Mỏ quặng (Mine) để chuẩn bị chế tác kim loại và công cụ thay thế đồ dùng hỏng hóc.

[b]• Giai đoạn 3: Ngày 21 – 30 (Mùa Thu — Tổng lực tích trữ)[/b]
  - Hệ số lương thực trở lại 1,0×. Đây là cơ hội cuối cùng để tích trữ lương thực trước mùa đông giá rét.
  - [color=#66ffcc]Mục tiêu dự trữ:[/color] Bạn cần đạt ít nhất [b]240 – 300 Lương thực[/b] an toàn trong kho trung tâm trước khi ngày 31 gõ cửa (24 dân × 10 ngày đông = 240 phần ăn).
  - Khởi công xây thêm Tháp canh (Watchtower) hoặc Tường rào (Palisade) nếu biên giới có dấu hiệu bất an.

[b]• Giai đoạn 4: Ngày 31 – 40 (Mùa Đông — Thử thách giá rét)[/b]
  - Sản lượng Nông trại bị cắt giảm một nửa ([b]0,5×[/b]), trong khi khẩu phần ăn của dân cư vẫn nguyên vẹn 100%!
  - Vương quốc sẽ sống sót nhờ kho lương thực đã tích lũy từ mùa Thu.
  - Hạn chế khởi công công trình đồ sộ tốn nhân lực; tập trung giữ ấm, bảo đảm an ninh và duy trì chuỗi vận chuyển thông suốt.""",

	# Chương E
	"""[color=#ffd700][b]1. SỰ KIỆN THẾ GIỚI VÀ CẢNH BÁO KHỦNG HOẢNG[/b][/color]
Thế giới KINGDOMS UNBOUND biến đổi không ngừng thông qua EventManager:
• [b]Biến cố ngẫu nhiên:[/b] Thời tiết bất thuận, thị trường biến động, di dân tị nạn xin gia nhập hoặc dịch bệnh rình rập.
• [b]Biểu ngữ sự kiện (Event Banner):[/b] Xuất hiện nổi bật ở nửa trên màn hình thông báo tin tức tốt lành (xanh lá) hoặc hiểm họa khẩn cấp (đỏ thẫm).
• [b]Làn sóng di dân:[/b] Tiếp nhận di dân giúp gia tăng lực lượng lao động nhưng sẽ làm tăng áp lực khẩu phần ăn và nhà ở.

[color=#ffd700][b]2. MẠNG LƯỚI QUAN HỆ NGOẠI GIAO[/b][/color]
Nhấn phím [b]Y[/b] hoặc nút [b]👑 Ngoại Giao[/b] để mở bảng quan hệ quốc tế:
• [b]Chỉ số thiện cảm (Opinion):[/b] Xác định mức độ thân thiện của các lãnh bang: Thù địch (< -50), Căng thẳng, Trung lập, Thân thiện (> +30), Đồng minh (> +70).
• [b]Hiệp ước Không Xâm Lược (NAP):[/b] Ký kết bảo đảm hòa bình trong một khoảng thời gian, ngăn chặn các cuộc đột kích bất ngờ.
• [b]Quà tặng ngoại giao (Gifts):[/b] Gửi tặng Vàng hoặc tài nguyên để xoa dịu hiềm khích và nâng cao thiện cảm láng giềng.

[color=#ffd700][b]3. ĐOÀN THƯƠNG GIA VÀ CHỢ (MARKET)[/b][/color]
• Khi bạn xây dựng Chợ (Market), các đoàn thương nhân (Caravan) sẽ định kỳ ghé thăm định cư.
• Chợ cho phép bán tháo các loại tài nguyên dư thừa lấy Vàng ngân khố, hoặc mua các vật liệu hiếm (Pha lê ma thuật, Thảo mộc, Quặng kim loại) khi chuỗi sản xuất nội địa chưa cung ứng kịp.

[color=#ffd700][b]4. DOANH TRẠI, QUÂN ĐỘI VÀ TÁC CHIẾN[/b][/color]
Nhấn phím [b]U[/b] hoặc nút [b]⚔️ Quân Đội[/b] để quản lý quân sự:
• [b]Doanh trại (Barracks):[/b] Nơi tuyển mộ binh sĩ từ công dân nhàn rỗi. Tuyển quân tốn Công cụ, Vũ khí, Vàng và tiêu hao nhân lực sản xuất.
• [b]Chi phí duy trì (Upkeep):[/b] Mỗi binh lính tiêu thụ Lương thực và Vàng đều đặn mỗi ngày. Quân đội quá đông sẽ nhanh chóng vắt kiệt ngân khố!
• [b]Điều động chiến thuật:[/b] Chỉ huy đạo quân di chuyển tuần tra biên giới, đánh chặn thổ phỉ hoặc công hãm các cứ điểm địch.
• [b]Rủi ro quân sự:[/b] Chiến dịch thất bại đồng nghĩa với thương vong binh sĩ, tổn thất kinh tế và nguy cơ bị đối phương phản kích cướp phá.""",

	# Chương F
	"""[color=#ffd700][b]1. CHIẾN THẮNG PHỒN VINH (PROSPERITY VICTORY)[/b][/color]
Để ghi danh vào sử sách vinh quang, vương quốc của bạn cần hoàn thành các tiêu chí phồn vinh:
• [b]Quy mô dân số:[/b] Đạt mốc dân cư phát triển thịnh vượng (tối thiểu 50 công dân).
• [b]Độ ổn định xã hội (Stability):[/b] Duy trì vững chắc từ [b]80% trở lên[/b].
• [b]Ngân khố dồi dào:[/b] Tích lũy đủ lượng Vàng theo chuẩn phát triển.
• [b]Duy trì liên tục:[/b] Vương quốc phải giữ vững toàn bộ các điều kiện trên liên tục trong [b]5 ngày[/b] thử thách.
• Khi thành công, Màn hình Tổng kết Thế giới (Victory Summary) sẽ hiện lên thông báo chiến thắng.

[color=#ffd700][b]2. ĐIỀU KIỆN SỤP ĐỔ VƯƠNG QUỐC (COLLAPSE)[/b][/color]
Vương quốc sẽ bị tuyên bố sụp đổ và kết thúc trò chơi nếu:
• Dân số giảm về [b]0[/b] (toàn bộ công dân chết vì nạn đói, kiệt sức hoặc chiến tranh).
• Độ ổn định xã hội (Stability) suy sụp hoàn toàn về [b]0%[/b].

[color=#ffd700][b]3. PHẦN THƯỞNG DI SẢN (LEGACY REWARDS) — CHUẨN PACKAGE 2C[/b][/color]
Hệ thống Di Sản giúp lưu giữ thành quả của bạn qua các thế hệ thế giới:
• [b]Phần thưởng Chiến Thắng cơ bản:[/b] Hoàn thành chiến thắng vinh quang nhận ngay [b]+100 Điểm Di Sản (Legacy Points)[/b] vào hồ sơ người chơi.

[color=#66ccff][b]4. CƠ CHẾ CHUYỂN ĐỔI NGÂN KHỐ THẶNG DƯ (SURPLUS TREASURY CONVERSION)[/b][/color]
Khi quyết toán chiến thắng, người chơi có thể đổi Vàng thặng dư thành Điểm Di Sản:
• [b]Ngân khố bảo lưu an toàn: 1.000 Vàng[/b]. Đây là khoản quỹ dự trữ bất khả xâm phạm để duy trì vương quốc, không được phép chuyển đổi.
• [b]Tỷ lệ chuyển đổi chuẩn: 100 Vàng thặng dư = 1 Điểm Di Sản[/b].
  - Công thức tính:
    [code]Vàng thặng dư = max(0, Tổng Vàng - 1000)[/code]
    [code]Di Sản nhận thêm = floor(Vàng thặng dư / 100)[/code]
    [code]Vàng khấu trừ = Di Sản nhận thêm × 100[/code]
  - [b]Ví dụ thực tế:[/b] Ngân khố có 5.050 Vàng -> Thặng dư 4.050 Vàng -> Nhận thêm [b]+40 Điểm Di Sản[/b], khấu trừ 4.000 Vàng, ngân khố còn 1.050 Vàng (bao gồm 1.000 Vàng bảo lưu + 50 Vàng lẻ).

[color=#ffd700][b]5. CÁC ĐIỀU KIỆN BẮT BUỘC KHI CHUYỂN ĐỔI:[/b][/color]
• [b]Độ ổn định tối thiểu:[/b] Stability phải đạt [b]từ 80% trở lên[/b]. Nếu dưới 80%, vương quốc không đủ điều kiện chuyển đổi ngân khố.
• [b]Vương quốc sụp đổ không có quà:[/b] Nếu vương quốc bị sụp đổ hoặc bại trận, toàn bộ chuyển đổi ngân khố bị từ chối ([b]0 Điểm Di Sản[/b]).
• [b]Quy tắc một lần duy nhất (Exactly-Once):[/b] Mỗi mã thế giới (World ID) chỉ được hưởng quyền chuyển đổi ngân khố tối đa [b]một lần duy nhất[/b]. Việc lưu và tải lại thế giới đã quyết toán sẽ không cho phép chuyển đổi thêm lần thứ hai."""
]

# Internal node references
@onready var modal_backdrop: ColorRect = $ModalBackdrop
@onready var guide_panel: PanelContainer = $CenterContainer/GuidePanel
@onready var close_btn: Button = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/HeaderBox/CloseBtn
@onready var chapter_title_lbl: Label = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/ContentBox/ChapterHeaderLabel
@onready var chapter_sub_lbl: Label = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/ContentBox/ChapterSubLabel
@onready var content_scroll: ScrollContainer = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/ContentBox/ContentScroll
@onready var content_text: RichTextLabel = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/ContentBox/ContentScroll/ContentText
@onready var page_indicator: Label = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/ContentBox/NavFooter/PageIndicator
@onready var prev_btn: Button = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/ContentBox/NavFooter/PrevBtn
@onready var next_btn: Button = $CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/ContentBox/NavFooter/NextBtn

var chapter_buttons: Array[Button] = []
var current_chapter: int = 0

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if modal_backdrop:
		modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	if guide_panel:
		guide_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Find sidebar buttons
	var sidebar_vbox: VBoxContainer = get_node_or_null("CenterContainer/GuidePanel/MarginContainer/VBoxContainer/MainBody/Sidebar")
	if sidebar_vbox:
		for i in range(TOTAL_CHAPTERS):
			var b := sidebar_vbox.get_node_or_null("ChapterBtn%d" % i) as Button
			if b:
				chapter_buttons.append(b)
				var chap_idx := i
				b.pressed.connect(func(): select_chapter(chap_idx))

	if close_btn:
		close_btn.pressed.connect(close_guide)
	if prev_btn:
		prev_btn.pressed.connect(_on_prev_pressed)
	if next_btn:
		next_btn.pressed.connect(_on_next_pressed)

	select_chapter(0)

func open_guide(chapter_idx: int = -1) -> void:
	if chapter_idx >= 0 and chapter_idx < TOTAL_CHAPTERS:
		select_chapter(chapter_idx)
	elif current_chapter < 0 or current_chapter >= TOTAL_CHAPTERS:
		select_chapter(0)
	else:
		_refresh_display()

	visible = true
	guide_opened.emit()

func close_guide() -> void:
	visible = false
	guide_closed.emit()

func is_guide_open() -> bool:
	return visible

func toggle_guide() -> void:
	if visible:
		close_guide()
	else:
		open_guide()

func select_chapter(idx: int) -> void:
	current_chapter = clampi(idx, 0, TOTAL_CHAPTERS - 1)
	_refresh_display()
	chapter_selected.emit(current_chapter)

func get_current_chapter() -> int:
	return current_chapter

func get_chapter_title(idx: int) -> String:
	if idx >= 0 and idx < CHAPTER_TITLES.size():
		return CHAPTER_TITLES[idx]
	return ""

func get_chapter_subtitle(idx: int) -> String:
	if idx >= 0 and idx < CHAPTER_SUBTITLES.size():
		return CHAPTER_SUBTITLES[idx]
	return ""

func get_chapter_content(idx: int) -> String:
	if idx >= 0 and idx < CHAPTER_TEXTS.size():
		return CHAPTER_TEXTS[idx]
	return ""

func _refresh_display() -> void:
	if chapter_title_lbl:
		chapter_title_lbl.text = get_chapter_title(current_chapter)
	if chapter_sub_lbl:
		chapter_sub_lbl.text = get_chapter_subtitle(current_chapter)
	if content_text:
		content_text.text = get_chapter_content(current_chapter)
	if page_indicator:
		page_indicator.text = "Chương %d / %d" % [current_chapter + 1, TOTAL_CHAPTERS]

	# Reset scroll to top
	if content_scroll:
		content_scroll.scroll_vertical = 0

	# Update button visual states
	for i in range(chapter_buttons.size()):
		var b: Button = chapter_buttons[i]
		if is_instance_valid(b):
			if i == current_chapter:
				b.modulate = Color(1.0, 0.9, 0.4, 1.0) # Gold accent for selected
			else:
				b.modulate = Color(1.0, 1.0, 1.0, 0.85)

	if prev_btn:
		prev_btn.disabled = (current_chapter == 0)
	if next_btn:
		next_btn.disabled = (current_chapter == TOTAL_CHAPTERS - 1)

func _on_prev_pressed() -> void:
	if current_chapter > 0:
		select_chapter(current_chapter - 1)

func _on_next_pressed() -> void:
	if current_chapter < TOTAL_CHAPTERS - 1:
		select_chapter(current_chapter + 1)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_H or event.keycode == KEY_F1:
			close_guide()
		get_viewport().set_input_as_handled()
