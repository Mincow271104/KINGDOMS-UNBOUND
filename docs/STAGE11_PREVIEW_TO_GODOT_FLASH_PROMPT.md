# KINGDOMS UNBOUND — STAGE 11 PREVIEW-TO-GODOT REPOSITORY MIGRATION DIRECTIVE
Version 1.0 — tailored for Antigravity + Gemini 3.8 Flash

## MỤC TIÊU
Đưa dự án Godot hiện có trong `Mincow271104/KINGDOMS-UNBOUND` tiến gần nhất có thể tới chất lượng hành vi, giao diện, phạm vi gameplay và độ ổn định của file tham chiếu `KINGDOMS_UNBOUND_STAGE11_FINAL.html` (bản preview hoàn tất 11 stage). Không phải viết lại một game mới, không tạo game HTML song song và không chỉ dừng ở phân tích/kế hoạch.

Làm việc trong workspace repo hiện được mở ở Antigravity. Dùng Gemini Flash nên phải chia thay đổi thành các gói nhỏ, cụ thể, có thể kiểm thử. Không cố viết hàng nghìn dòng trong một lần. Sau mỗi gói, giữ project mở/chạy được, lưu tài liệu checkpoint và ghi chính xác kết quả.

## NGUỒN CHUẨN VÀ THỨ TỰ ƯU TIÊN
1. `KINGDOMS_UNBOUND_STAGE11_FINAL.html` — bản preview tham chiếu chức năng, UI, trạng thái mô phỏng, hành vi tương tác và regression tests. Người dùng sẽ cung cấp/mở file này trong workspace hoặc chỉ đường dẫn local. Đây là chuẩn so sánh cho hành vi đã hiện thực trong preview.
2. Repo Godot hiện tại: `project.godot`, scenes/scripts/assets thực có trong workspace và lịch sử Git. Đây là ứng dụng đích; cần phát triển bằng Godot/GDScript, không thay thế bằng HTML.
3. `docs/GDD.md` — gameplay intent và quy tắc thiết kế.
4. `MASTER_PROMPT.md` — quy trình/phase gates hiện có.
5. `docs/ASSET_STYLE_GUIDE.md` — chuẩn hình ảnh isometric/pixel art.
6. `AGENTS.md`, `docs/WORKLOG.md`, `docs/GDD_REVIEW.md` — quy tắc workspace, lịch sử và quyết định phạm vi.

Nếu các nguồn mâu thuẫn, không tự lặng lẽ chọn một cách. Ghi conflict vào `docs/SCOPE_DECISIONS.md`, chọn cách giữ được gameplay core và giải thích tác động.

## ĐIỂM CẦN HIỂU RÕ
Preview HTML không thể “copy-paste” thẳng thành Godot. Nó có code JavaScript, DOM/CSS, Canvas 2D và inline handlers; repo là dự án Godot. Hãy CHUYỂN HÓA hành vi/thiết kế sang scene, Node, GDScript, resources và hệ thống Godot phù hợp. Không thêm HTML runtime thứ hai. Không bê nguyên kiến trúc JavaScript vào một file GDScript khổng lồ.

Preview tham chiếu hiện có trung tâm các hệ thống sau (cần xác minh trong source thực tế, không suy ra từ tên module là đã đúng): `CONFIG`, `SeededRNG`, `IsoMath`, `WorldGenerator`, `WorldLogger`, `ResourceManager`, `BuildingSystem`, `ResearchSystem`, `ExplorationSystem`, `QuestSystem`, `WorldDirector`, `Pathfinder`, `CitizenManager`, `JobSystem`, `AutomationSystem`, `TradeSystem`, `DiplomacySystem`, `EspionageSystem`, `GovernanceSystem`, `MilitarySystem`, `WorldChronicleSystem`, `AchievementSystem`, `LegacySystem`, `EndgameSystem`, `TimeManager`, `SaveLoadSystem`, `IsometricRenderer`, `TestRunner`, `UIController`, `SettingsSystem`, `AudioSystem`, `ContentPackSystem`, `Stage10UI`.

HTML preview có Self-Test runner với test ID 1–123 và UI chạy test; không được tuyên bố tất cả pass chỉ vì kết quả/ghi chú trước đó nói vậy. Trong Godot, thiết kế test tương đương theo hành vi và thực thi thật.

## LUẬT KHÔNG THƯƠNG LƯỢNG
- Không xóa project hoặc thay thế hàng loạt.
- Không chỉnh `addons/godot_mcp/` trừ khi lỗi trong addon thực sự là blocker được chứng minh.
- Không xóa, làm yếu hoặc hardcode test PASS.
- Không thêm UI giả; mọi control hoạt động thật hoặc hiển thị rõ disabled + lý do.
- Không tự thay `MASTER_PROMPT.md`/GDD thành spec nhỏ hơn để đạt mục tiêu giả.
- Không cài engine/dependency trả phí; core game offline-first.
- Không phụ thuộc API/key/CDN/network để game chạy.
- Không `git reset --hard`, force-push, xóa asset hoặc ghi đè việc không liên quan.
- Không commit/push tự động trừ khi người dùng cho phép. Tạo local checkpoint an toàn nếu phù hợp.
- Giữ Godot version/setting hiện tại trừ khi có bằng chứng kỹ thuật bắt buộc.
- Dùng Vietnamese UI, stable IDs/coding identifiers bằng English theo repo.
- Tuyệt đối không dùng flat overhead top-down. Chuẩn là dimetric 2:1, tile 32×16, roof + hai mặt tiền công trình, pixel scale nhất quán, nearest-neighbor, contact pivots hợp lý và Y-sort.
- Không tuyên bố “preview parity” khi chỉ mới có scene/menu. Phân biệt `Implemented`, `Automated-test-passed`, `Runtime-tested`, `Visually-reviewed`.

## PHẦN A — AUDIT BẮT BUỘC TRƯỚC KHI CHỈNH SỬA
1. Kiểm tra `git status`, nhánh, recent commits; giữ nguyên mọi sửa đổi chưa commit của người dùng.
2. Xác nhận version/path của Godot thật và các lệnh kiểm tra có sẵn. Không đoán phiên bản.
3. Liệt kê toàn bộ project files, scenes, scripts, resources/assets, autoloads, input map, main scene và plugin config. Loại trừ chi tiết nặng của addon MCP khỏi báo cáo nhưng không xóa.
4. Đọc đủ `MASTER_PROMPT.md`, `docs/GDD.md`, `docs/ASSET_STYLE_GUIDE.md`, `AGENTS.md`, `docs/WORKLOG.md`, `docs/GDD_REVIEW.md`. Đọc các tài liệu khác nếu tồn tại.
5. Đọc source preview HTML thật. Nếu file chưa nằm trong workspace, tìm nó trong project attachments/known paths; nếu thực sự không thể truy cập, ghi rõ blocker và dùng prompt này + mô tả module làm mốc tạm thời, không giả vờ đã đọc file.
6. Lập bảng parity theo hệ thống, mỗi mục phải có:
   - Yêu cầu/hành vi ở preview.
   - File/module hiện tại trong Godot.
   - Trạng thái: `MISSING`, `PARTIAL`, `IMPLEMENTED-UNVERIFIED`, `TESTED`, `VISUAL-REVIEWED`.
   - Cụ thể các hành vi còn thiếu.
   - Test/step xác minh.
7. Chạy kiểm tra baseline thật: import/parse/headless startup nếu công cụ hỗ trợ; mở game/runtime qua Godot MCP nếu đã xác nhận plugin kết nối đúng project; lấy log/screenshot nếu khả thi. Nếu không chạy được một kiểm tra, đánh dấu `NOT RUN` và lý do.
8. Sau audit, bắt đầu implement gói nhỏ đầu tiên trong cùng phiên nếu có đủ thông tin; không chỉ nộp roadmap. Nếu project không có gameplay scene/script cốt lõi, gói đầu tiên phải là vertical slice tối thiểu có thể chạy, không tạo menu giả.

## PHẦN B — KIẾN TRÚC ĐÍCH ĐỂ GIỮ PROJECT DỄ SỬA
Không được tạo tất cả ngay nếu chưa cần; dùng như hướng phân chia trách nhiệm khi có các file tương ứng:

- `autoload/GameState.gd` hoặc tên hợp lý đang dùng: một WorldState authoritative; không để UI/automation/military sở hữu các bản sao state.
- `autoload/SimulationClock.gd`: tick/game time, pause, speed, day-boundary exactly once.
- `scripts/world/WorldGenerator.gd`: seeded generation và bản đồ Standard/Large/Endless nếu đang trong scope.
- `scripts/world/IsometricView.gd`: projection/rendering/camera/selection; tách logic grid khỏi screen pixel.
- `scripts/economy/ResourceLedger.gd`: atomic changes, storage cap, reservations/transaction log.
- `scripts/buildings/BuildingSystem.gd`: footprint/terrain/cost/construct/repair/upgrade/cancel/refund/effects.
- `scripts/citizens/CitizenSystem.gd`, `scripts/jobs/JobSystem.gd`, `scripts/navigation/Pathfinder.gd`: stable IDs, jobs/reservations, reachability/failure recovery.
- `scripts/automation/AutomationRunner.gd` + node data/editor UI: graph data thật, validation, dry-run/execute, bounded steps, pause-aware delays.
- `scripts/save/SaveService.gd`: schema/version/migration/round-trip.
- `scenes/main/`, `scenes/world/`, `scenes/ui/`, `scenes/test/`: scene organization.
- Data-driven definitions in `.tres`, `.res`, JSON or dictionaries with validation; choose what best fits actual project.

Treat these as examples, not an order to duplicate systems when repo already has equivalent files. Inspect first and keep only one authoritative implementation for each responsibility.

## PHẦN C — GÓI THỰC HIỆN THEO THỨ TỰ PHỤ THUỘC
Do not attempt every stage in a single generated edit. In the current session, choose one coherent package based on actual audit evidence and implement it now, then stop at a safe checkpoint. Continue the next package in a later instruction by reading the worklog/backlog.

### Package 0 — Audit + runnable proof
- Record baseline and parity matrix in `docs/PREVIEW_PARITY.md`.
- Create/repair `docs/WORKLOG.md`, `docs/BACKLOG.md`, `docs/TEST_PLAN.md` only as needed.
- Ensure at least the intended main scene can be launched and document the exact command/result.
- If existing project is documentation-only, create the smallest safe Godot runnable scene/script package with an isometric test view, but do not claim full game.
Acceptance: project parse/import succeeds; main scene launches or blocker is evidenced; scene structure, Godot version and baseline all documented.

### Package 1 — Isometric visual-validation scene first
Before large gameplay implementation, create/use `res://scenes/test/visual_validation_test.tscn`:
- diamond 32×16 ground tiles with a coherent restrained palette;
- trees and rocks at distinct scales;
- at least one 2×2 or 3×3 building with visible roof AND front-facing facades;
- one citizen that moves on logical grid coordinates;
- hover highlight uses mathematically correct inverse transform and shows selected cell;
- unit passes behind/in front of tree/building correctly through y-sort/pivot;
- camera pan/zoom and viewport resize work;
- crisp nearest-neighbor pixel style, no smooth-vector substitute that looks unrelated.
Acceptance: actual runtime screenshot captured/inspected if tools permit, and interaction test results documented. If this gate fails, fix before making dozens of assets or adding feature systems.

### Package 2 — Core loop and canonical state
- reproducible seed creates a 64×64 playable map and initial settlement;
- initial settlement has 24 citizens, 8 resource pools + separate Treasury, initial buildings/config aligned with documented scope decisions;
- central time with Pause/1×/2×/3×; no state changes while paused and day events exactly once;
- selection/hover, construction preview and usable side panel;
- every UI action routes to canonical systems.
Acceptance: seed reproducibility, isometric transform round trip, no invalid starting structures, tick/pause tests, run boot and interaction test.

### Package 3 — Economic causality
- Resource ledger, transaction logs, capacity limits, cost charged once, no negative/duplicate resources;
- buildings have actual production/consumption/workplace requirements, production chains consume inputs and produce outputs;
- food shortage explanation identifies cause and practical recovery;
- construction checks footprint, terrain, occupancy, resources, tech, access; support progress/cancel/refund as specified.
Acceptance: transaction atomicity, capacity, resource reservation/release, production input-output, pause, Save/Load.

### Package 4 — Citizens/jobs/logistics/pathfinding
- stable citizen/job IDs and job lifecycle; role vs active workplace state is distinct;
- citizens have visible job/action/failure state;
- pathfinding avoids blocked tiles and occupied cells, with timeout/repath cooldown;
- no endless role thrashing; work slots have capacity; citizens do not overlap continuously or teleport;
- haulers physically pick up/deliver resources when modeled as physical logistics.
Acceptance: two workers do not claim same slot/resource; unreachable job fails safely; reservations release; multi-day soak test; Save/Load identities stable.

### Package 5 — Functional automation graph
- draggable nodes and edge connections are serialized actual data; editor supports configure, delete, duplicate, enable/disable, save/load;
- bounded interpreter supports trigger/condition/branch/actions/wait/repeat cap/end, execution budgets and conflict policy;
- dry-run cannot mutate canonical state; execute must call same authoritative APIs as manual UI;
- logs show trigger, condition, branch, action, result and deltas; pause halts game-time delays.
Acceptance: create graph in actual UI, connect it, validate, save, reload, execute, observe measurable world-state change and both true/false branch tests.

### Package 6 — Expansion systems
Implement in coherent increments: research/magic, POI/quest/World Director/events, trade/contracts/prices, diplomacy/factions, espionage, governance. Each is real gameplay with validation/cost/cooldown/log/save-load, not static panels.
Acceptance: tests for costs, effects, prerequisites, cooldowns, deterministic conditions, one-time rewards, save/load, faction response.

### Package 7 — Direct military tactics
- visible unit entities on tactical/world grid; click and drag-box selection;
- real commands Move, Attack, Attack-Move, Hold, Defend, Patrol, Follow, Regroup, Retreat;
- movement/pathing/collision/attack cooldown/range/HP/armor/morale/supply and enemy AI;
- manual orders outrank automation except explicit, logged emergency policy.
Acceptance: actual runtime movement/combat, multi-selection, lethal-hit idempotency, pause, save/load and battle consequence tests.

### Package 8 — Crisis, endings, chronicle, legacy, polish and content packs
- recovery windows and clear crisis causes;
- victory routes and continuous prosperity streak; world summary, chronicle/achievements, cosmetics-only Legacy;
- settings/accessibility/tooltips/keybindings/autosave/audio and safe data-only content packs;
- every visible button works or is disabled with reason.
Acceptance: no duplicate awards after load; all settings affect behavior; import validation rejects executable payload; UI/visual regression review.

### Final parity sweep — Not before packages above pass
Check every major system in the Stage 11 preview including the actual tests/behaviors, not just labels:
- world generation + map modes + seed
- time/season/weather/pause/speed
- resource ledger/storage/production/economy
- buildings/placement/upgrade/repair/refund
- citizens/roles/needs/workplace/pathfinding/logistics
- automation editor and execution
- research/magic
- exploration/quests/artifacts/events
- trade/contracts/factions/diplomacy
- espionage/counterintelligence
- governance/culture/stability
- crisis/recovery/collapse and victory
- Chronicle/achievements/Legacy
- save/load/backup/migrations
- settings/help/accessibility/audio
- content packs and test runner

## PHẦN D — QUY TẮC KHI DÙNG GEMINI FLASH
Model có giới hạn context, lượt sinh và suy luận. Đừng đưa nhiệm vụ “hoàn thành toàn bộ game ngay” rồi chấp nhận output dài không tích hợp.

Trong mỗi lượt:
1. Đọc lại Git status và worklog/backlog; xem code hiện tại, không dựa mù vào hội thoại trước.
2. Nêu tối đa 3–5 file dự kiến thay đổi, nêu lý do ngắn.
3. Chọn một gói nhỏ nhất có thể nghiệm thu độc lập. Không triển khai nhiều hệ thống không liên quan.
4. Sửa file thực tế trong workspace, không chỉ trả code trong chat.
5. Tự chạy validation/test phù hợp; không giả lập kết quả test.
6. Nếu test thất bại, sửa lỗi liên quan và chạy lại. Nếu không thể, ghi `NOT RUN/UNVERIFIED` cùng lý do.
7. Cập nhật `docs/WORKLOG.md`, `docs/BACKLOG.md`, `docs/TEST_PLAN.md`, `docs/PREVIEW_PARITY.md` tương ứng.
8. Dừng khi có checkpoint an toàn, nêu đúng bước tiếp theo. Không tự chạy vòng lặp vô hạn hay tiêu quota cho các refactor ít giá trị.

Không dùng High/extended reasoning trừ khi người dùng chọn; ưu tiên Flash với thay đổi nhỏ, deterministic, có kiểm thử.

## PHẦN E — CÁCH SO SÁNH VỚI PREVIEW
Preview là chuẩn về feature behavior/UI layout, nhưng không yêu cầu pixel-identical DOM. Trong Godot:
- giữ thanh resource trên, thanh trạng thái/thời gian, map isometric lớn là trọng tâm, minimap/overlay, event log, panel bên phải, toolbar dưới;
- panel/toolbar phải có chức năng thật và không che quá nhiều bản đồ;
- world visual phải là dimetric top-down 3/4 pixel art, không phải khối màu đại diện quá thô nếu đã có thể render sprite/pixel geometry nhất quán;
- hover/select/placement/camera/minimap phải có tọa độ nhất quán;
- show exact causes, feedback toasts, clear disabled reasons, save/load and test access.
Dùng ảnh `docs/reference/kingdom_visual_reference.png` cho visual direction; dùng preview HTML để hiểu cụ thể state/actions/components.

## PHẦN F — BÁO CÁO CUỐI MỖI LƯỢT
Trả lời ngắn gọn bằng tiếng Việt:
1. Gói đã thực hiện; file tạo/sửa.
2. Hành vi thực tế đã implement.
3. Lệnh/test đã chạy, kết quả thực quan sát (PASS/FAIL/NOT RUN).
4. Trạng thái runtime/game window/screenshot/log.
5. Bảng parity items vừa thay đổi trạng thái và bằng chứng.
6. Các lỗi còn lại, rủi ro/chưa xác minh.
7. Bước tiếp theo chính xác (một gói duy nhất).
8. Git status; không push/commit nếu chưa được phép.

## THỰC HIỆN NGAY
Bắt đầu audit repo hiện đang mở và file preview được cung cấp. Đừng yêu cầu người dùng lặp lại thông tin đã có. Không chỉ đưa kế hoạch. Chọn package đầu tiên từ bằng chứng, thực hiện một chỉnh sửa thực tế nhỏ, test bằng công cụ có sẵn và ghi lại checkpoint. Nếu không thể chạy Godot hoặc chưa truy cập được preview, ghi blocker chính xác và vẫn hoàn thành phần kiểm tra an toàn có thể làm.
