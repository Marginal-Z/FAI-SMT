/// Chinese / English / Thai text table (no Flutter dependency).
library;

const supportedLanguages = ['zh', 'en', 'th'];

/// key -> [zh, en, th]. Templates use `{name}` placeholders.
const Map<String, List<String>> _t = {
  'app_name': ['SMT-FAI', 'SMT-FAI', 'SMT-FAI'],
  'app_subtitle': ['BOM 站位表核对 · FAI 坐标生成', 'BOM / Station Check · FAI CAD Builder', 'ตรวจ BOM / ตารางสถานี · สร้างพิกัด FAI'],

  // Ribbon tabs
  'tab_home': ['开始', 'Home', 'หน้าแรก'],
  'tab_rules': ['规则', 'Rules', 'กฎ'],
  'tab_output': ['输出', 'Output', 'ส่งออก'],
  'tab_view': ['视图', 'View', 'มุมมอง'],
  'tab_help': ['帮助', 'Help', 'ช่วยเหลือ'],

  // Ribbon groups
  'grp_import': ['导入文件', 'Import', 'นำเข้าไฟล์'],
  'grp_check': ['核对', 'Check', 'ตรวจสอบ'],
  'grp_export': ['导出', 'Export', 'ส่งออก'],
  'grp_rules': ['核对规则', 'Check Rules', 'กฎการตรวจสอบ'],
  'grp_coord_import': ['坐标单位', 'Coordinate Unit', 'หน่วยพิกัด'],
  'grp_cad': ['FAI CAD', 'FAI CAD', 'FAI CAD'],
  'grp_language': ['语言', 'Language', 'ภาษา'],
  'grp_theme': ['主题', 'Theme', 'ธีม'],
  'grp_panels': ['面板', 'Panels', 'แผง'],
  'grp_workspace': ['工作区', 'Workspace', 'พื้นที่ทำงาน'],
  'grp_about': ['关于', 'About', 'เกี่ยวกับ'],

  // Ribbon buttons
  'btn_bom': ['T100 BOM', 'T100 BOM', 'T100 BOM'],
  'btn_station_a': ['站位表 A', 'Station A', 'สถานี A'],
  'btn_station_b': ['站位表 B', 'Station B', 'สถานี B'],
  'btn_coord': ['坐标文件', 'Coordinates', 'ไฟล์พิกัด'],
  'btn_run': ['开始核对', 'Run Check', 'เริ่มตรวจ'],
  'btn_clear': ['清空', 'Clear', 'ล้าง'],
  'btn_export_report': ['核对报告', 'Check Report', 'รายงานตรวจ'],
  'btn_gen_cad': ['生成 CAD', 'Build CAD', 'สร้าง CAD'],
  'btn_exclusion': ['排除物料', 'Exclusions', 'การยกเว้น'],
  'btn_substitutes': ['替代料', 'Alternates', 'วัสดุทดแทน'],
  'btn_general': ['常规', 'General', 'ทั่วไป'],
  'btn_cad_template': ['CAD 格式', 'CAD Format', 'รูปแบบ CAD'],
  'btn_dark': ['深色', 'Dark', 'มืด'],
  'btn_light': ['浅色', 'Light', 'สว่าง'],
  'btn_system': ['跟随系统', 'System', 'ตามระบบ'],
  'theme_toggle': ['切换浅色 / 深色', 'Switch light / dark', 'สลับสว่าง / มืด'],
  'theme_now_system': ['主题：跟随系统', 'Theme: system', 'ธีม: ตามระบบ'],
  'theme_now_light': ['主题：浅色', 'Theme: light', 'ธีม: สว่าง'],
  'theme_now_dark': ['主题：深色', 'Theme: dark', 'ธีม: มืด'],
  'guide_title': ['开始首件核对', 'Start a first-article check', 'เริ่มตรวจชิ้นงานแรก'],
  'guide_sub': ['依次导入下列文件，然后点击「开始核对」', 'Import the files below, then run the check', 'นำเข้าไฟล์ด้านล่าง แล้วกด เริ่มตรวจ'],
  'step_bom': ['T100 导出的 BOM 文件', 'BOM exported from T100', 'BOM ที่ส่งออกจาก T100'],
  'step_station_a': ['A 面站位表', 'Station list, side A', 'ตารางสถานีด้าน A'],
  'step_station_b': ['B 面站位表（单面板可不导入）', 'Station list, side B (skip for single-sided)', 'ตารางสถานีด้าน B (ข้ามได้ถ้าด้านเดียว)'],
  'step_coord': ['原始坐标文件，用于生成 FAI CAD', 'Original coordinates, for the FAI CAD file', 'ไฟล์พิกัดต้นฉบับ สำหรับสร้าง CAD'],
  'step_optional': ['可选', 'Optional', 'ไม่บังคับ'],
  'step_import': ['导入', 'Import', 'นำเข้า'],
  'step_replace': ['更换', 'Replace', 'เปลี่ยน'],
  'btn_files_panel': ['项目面板', 'Project', 'โปรเจกต์'],
  'btn_inspector': ['属性面板', 'Inspector', 'คุณสมบัติ'],
  'btn_about': ['关于', 'About', 'เกี่ยวกับ'],
  'btn_settings_folder': ['配置目录', 'Config Folder', 'โฟลเดอร์ตั้งค่า'],

  'unit_auto': ['自动', 'Auto', 'อัตโนมัติ'],
  'unit_mm': ['mm', 'mm', 'mm'],
  'unit_mil': ['mil', 'mil', 'mil'],
  'unit_inch': ['inch', 'inch', 'inch'],

  // Workspace
  'ws_check': ['核对结果', 'Check Result', 'ผลการตรวจ'],
  'ws_board': ['坐标视图', 'Board View', 'มุมมองบอร์ด'],
  'ws_cad': ['CAD 预览', 'CAD Preview', 'ตัวอย่าง CAD'],

  // Project panel
  'panel_files': ['项目文件', 'Project Files', 'ไฟล์โปรเจกต์'],
  'panel_summary': ['核对概况', 'Summary', 'สรุป'],
  'panel_inspector': ['属性', 'Inspector', 'คุณสมบัติ'],
  'file_none': ['未加载', 'Not loaded', 'ยังไม่โหลด'],
  'file_items': ['{n} 项', '{n} items', '{n} รายการ'],
  'file_columns': ['识别列', 'Detected columns', 'คอลัมน์ที่พบ'],
  'file_remove': ['移除', 'Remove', 'ลบ'],
  'inspector_empty': ['在结果表中选择一行查看详情', 'Select a row to see details', 'เลือกแถวเพื่อดูรายละเอียด'],

  // Categories
  'cat_all': ['全部', 'All', 'ทั้งหมด'],
  'cat_pass': ['PASS', 'PASS', 'PASS'],
  'cat_ng': ['NG', 'NG', 'NG'],
  'cat_excluded': ['已排除物料', 'Excluded', 'ยกเว้นแล้ว'],
  'cat_substitute': ['替代料', 'Alternates', 'วัสดุทดแทน'],
  'res_pass': ['PASS', 'PASS', 'PASS'],
  'res_ng': ['NG', 'NG', 'NG'],
  'res_excluded': ['排除', 'EXCL', 'ยกเว้น'],
  'res_substitute': ['替代', 'ALT', 'ทดแทน'],

  // Columns
  'col_no': ['序号', 'No.', 'ลำดับ'],
  'col_pn': ['料号', 'Part No.', 'รหัสวัสดุ'],
  'col_desc': ['品名 / 物料描述', 'Name / Description', 'ชื่อ / รายละเอียด'],
  'col_bom_qty': ['BOM用量', 'BOM Qty', 'จำนวน BOM'],
  'col_smt_qty': ['SMT数量', 'SMT Qty', 'จำนวน SMT'],
  'col_bom_refs': ['BOM插件位置', 'BOM Designators', 'ตำแหน่ง BOM'],
  'col_smt_refs': ['SMT站位表位号', 'Station Designators', 'ตำแหน่งตารางสถานี'],
  'col_smt_pn': ['上料料号', 'Loaded Part No.', 'รหัสที่ติดตั้ง'],
  'col_side': ['面别', 'Side', 'ด้าน'],
  'col_slot': ['站位', 'Slot', 'สล็อต'],
  'col_result': ['核对结果', 'Result', 'ผลลัพธ์'],
  'col_reason': ['异常原因', 'Reason', 'สาเหตุ'],
  'col_ref': ['位号', 'Designator', 'ตำแหน่ง'],
  'col_bom_pn': ['BOM料号', 'BOM Part No.', 'รหัส BOM'],
  'col_x': ['X', 'X', 'X'],
  'col_y': ['Y', 'Y', 'Y'],

  'side_a': ['A面', 'Side A', 'ด้าน A'],
  'side_b': ['B面', 'Side B', 'ด้าน B'],
  'side_top': ['顶面', 'Top', 'ด้านบน'],
  'side_bottom': ['底面', 'Bottom', 'ด้านล่าง'],
  'side_both': ['双面', 'Both', 'ทั้งสองด้าน'],

  // Reasons
  'not_on_station': ['站位表中无此料号', 'Not in station list', 'ไม่พบในตารางสถานี'],
  'station_missing_refs': ['站位表缺少位号: {refs}', 'Missing in station list: {refs}', 'ตารางสถานีขาดตำแหน่ง: {refs}'],
  'station_extra_refs': ['站位表多出位号: {refs}', 'Extra in station list: {refs}', 'ตารางสถานีมีตำแหน่งเกิน: {refs}'],
  'bom_no_refs': ['BOM无插件位置', 'BOM line has no designators', 'BOM ไม่มีตำแหน่ง'],
  'bom_dup_refs': ['BOM位号重复: {refs}', 'Duplicate BOM designators: {refs}', 'ตำแหน่งซ้ำใน BOM: {refs}'],
  'bom_ref_conflict': ['位号 {refs} 同时属于BOM料号 {pn}', 'Designators {refs} also on BOM part {pn}', 'ตำแหน่ง {refs} อยู่ในรหัส BOM {pn} ด้วย'],
  'station_ref_conflict': ['位号 {refs} 在站位表中同时贴装 {pn}', 'Designators {refs} also loaded with {pn}', 'ตำแหน่ง {refs} ติดตั้ง {pn} ด้วย'],
  'ref_both_sides': ['位号 {refs} 同时出现在A、B站位表', 'Designators {refs} in both station A and B', 'ตำแหน่ง {refs} อยู่ทั้งสถานี A และ B'],
  'qty_mismatch': ['BOM用量({qty})与位号数({n})不符', 'BOM qty ({qty}) does not match designator count ({n})', 'จำนวน BOM ({qty}) ไม่ตรงกับจำนวนตำแหน่ง ({n})'],
  'alt_used': ['使用替代料 {pn}: {refs}', 'Alternate {pn} used: {refs}', 'ใช้วัสดุทดแทน {pn}: {refs}'],
  'not_in_bom': ['BOM中无此料号 {refs}', 'Part not in BOM {refs}', 'ไม่มีรหัสนี้ใน BOM {refs}'],
  'alt_outside_main': ['替代料位号超出主料范围: {refs}', 'Alternate outside main designators: {refs}', 'วัสดุทดแทนเกินตำแหน่งหลัก: {refs}'],
  'ref_belongs_to': ['位号 {refs} 在BOM中属于 {pn}', 'Designators {refs} belong to BOM part {pn}', 'ตำแหน่ง {refs} เป็นของรหัส BOM {pn}'],
  'excl_keyword': ['品名含排除关键字「{kw}」', 'Matches exclusion keyword "{kw}"', 'ตรงกับคำยกเว้น "{kw}"'],
  'excl_prefix': ['料号前缀「{prefix}」已排除', 'Part prefix "{prefix}" excluded', 'คำนำหน้า "{prefix}" ถูกยกเว้น'],
  'excl_no_refs': ['无插件位置，非SMT贴装物料', 'No designators, not an SMT part', 'ไม่มีตำแหน่ง ไม่ใช่วัสดุ SMT'],

  // Messages
  'msg_need_bom': ['请先导入 T100 BOM 文件', 'Import the T100 BOM first', 'กรุณานำเข้า T100 BOM ก่อน'],
  'msg_need_station': ['请至少导入一个站位表', 'Import at least one station list', 'กรุณานำเข้าตารางสถานีอย่างน้อยหนึ่งไฟล์'],
  'msg_need_check': ['请先执行核对', 'Run the check first', 'กรุณาตรวจสอบก่อน'],
  'msg_need_coord': ['请先导入原始坐标文件', 'Import the coordinate file first', 'กรุณานำเข้าไฟล์พิกัดก่อน'],
  'msg_saved': ['已保存: {path}', 'Saved: {path}', 'บันทึกแล้ว: {path}'],
  'msg_ng_confirm': ['核对结果中仍有 {n} 项 NG，确定继续生成 CAD 文件吗？', '{n} NG items remain. Build the CAD file anyway?', 'ยังมี NG {n} รายการ ต้องการสร้างไฟล์ CAD ต่อหรือไม่?'],
  'msg_error': ['错误', 'Error', 'ข้อผิดพลาด'],
  'msg_warning': ['提示', 'Notice', 'แจ้งเตือน'],
  'err_xls_unsupported': ['暂不支持旧版 .xls，请在 Excel 中另存为 .xlsx 后再导入', 'Legacy .xls is not supported. Save it as .xlsx in Excel and import again.', 'ไม่รองรับ .xls รุ่นเก่า กรุณาบันทึกเป็น .xlsx แล้วนำเข้าใหม่'],
  'err_read_failed': ['文件读取失败: {detail}', 'Could not read file: {detail}', 'อ่านไฟล์ไม่สำเร็จ: {detail}'],
  'err_empty': ['文件中没有数据', 'The file contains no data', 'ไฟล์ไม่มีข้อมูล'],
  'err_parse_no_header_bom': ['未识别到 BOM 表头，需要包含「料件编号」和「插件位置」列', 'BOM header not found. It needs part number and designator columns.', 'ไม่พบหัวตาราง BOM ต้องมีคอลัมน์รหัสวัสดุและตำแหน่ง'],
  'err_parse_no_header_station': ['未识别到站位表表头，需要包含「料号」和「位号」列', 'Station list header not found. It needs part number and designator columns.', 'ไม่พบหัวตารางสถานี ต้องมีคอลัมน์รหัสวัสดุและตำแหน่ง'],
  'err_parse_no_header_coord': ['未识别到坐标文件表头，需要包含位号、X、Y 列', 'Coordinate header not found. It needs designator, X and Y columns.', 'ไม่พบหัวตารางพิกัด ต้องมีคอลัมน์ตำแหน่ง X และ Y'],
  'parse_bad_qty': ['第 {row} 行用量无法识别: {detail}', 'Row {row}: unreadable quantity {detail}', 'แถว {row}: อ่านจำนวนไม่ได้ {detail}'],
  'parse_bad_xy': ['第 {row} 行坐标无效: {detail}', 'Row {row}: invalid coordinates {detail}', 'แถว {row}: พิกัดไม่ถูกต้อง {detail}'],
  'parse_station_qty': ['第 {row} 行数量与位号数不符: {detail}', 'Row {row}: quantity does not match designator count {detail}', 'แถว {row}: จำนวนไม่ตรงกับจำนวนตำแหน่ง {detail}'],
  'alt_listed': ['站位表备有替代料 {pn}（站位 {slot}）', 'Station lists alternate {pn} (slot {slot})', 'ตารางสถานีมีวัสดุทดแทน {pn} (สล็อต {slot})'],
  'excl_programmed': ['由烧录料 {pn} 贴装，原料不单独上料', 'Placed as programmed part {pn}; blank part not loaded', 'ติดตั้งเป็นชิ้นที่โปรแกรมแล้ว {pn}'],
  'rules_program': ['烧录料关键字 (品名包含即视为烧录后物料，与其共用位号的原料归入已排除，每行一个)', 'Programmed-part keywords (blank parts sharing its designators go to Excluded, one per line)', 'คำสำคัญชิ้นที่โปรแกรมแล้ว (ชิ้นเปล่าที่ใช้ตำแหน่งเดียวกันจะถูกยกเว้น หนึ่งบรรทัดต่อคำ)'],
  'excl_parent': ['成品 / 主件料号（用量为 0）', 'Assembly / parent item (qty 0)', 'รหัสชิ้นงานหลัก (จำนวน 0)'],
  'parse_dup_ref': ['第 {row} 行位号重复: {detail}', 'Row {row}: duplicate designator {detail}', 'แถว {row}: ตำแหน่งซ้ำ {detail}'],

  // Status bar
  'status_ready': ['就绪', 'Ready', 'พร้อม'],
  'status_loaded': ['已加载 {name}', 'Loaded {name}', 'โหลดแล้ว {name}'],
  'status_checked': ['核对完成: PASS {pass} · NG {ng} · 排除 {ex} · 替代 {alt}', 'Check done: PASS {pass} · NG {ng} · Excluded {ex} · Alternates {alt}', 'ตรวจเสร็จ: PASS {pass} · NG {ng} · ยกเว้น {ex} · ทดแทน {alt}'],
  'status_rows': ['{n} 行', '{n} rows', '{n} แถว'],

  // CAD preview
  'cad_rows': ['输出 {n} 个位号', '{n} designators to write', 'ส่งออก {n} ตำแหน่ง'],
  'cad_no_coord': ['缺少坐标的位号 ({n})', 'Designators without coordinates ({n})', 'ตำแหน่งที่ไม่มีพิกัด ({n})'],
  'cad_not_in_bom': ['不在BOM中的坐标位号 ({n})', 'Coordinates not in BOM ({n})', 'พิกัดที่ไม่อยู่ใน BOM ({n})'],
  'cad_unknown_side': ['面别未知的位号 ({n})', 'Designators with unknown side ({n})', 'ตำแหน่งที่ไม่ทราบด้าน ({n})'],
  'cad_side_mismatch': ['坐标面别与站位表A/B面不符 ({n})', 'Layer differs from station side A/B ({n})', 'ด้านในพิกัดไม่ตรงกับสถานี A/B ({n})'],
  'cad_checks': ['生成检查', 'Build Checks', 'การตรวจสอบ'],
  'cad_all_good': ['所有位号均已匹配坐标', 'All designators matched to coordinates', 'ทุกตำแหน่งจับคู่พิกัดแล้ว'],

  // CAD template dialog
  'cad_title': ['FAI i450 CAD 文件格式', 'FAI i450 CAD File Format', 'รูปแบบไฟล์ CAD FAI i450'],
  'cad_fields': ['输出列（勾选并调整顺序）', 'Columns (tick and reorder)', 'คอลัมน์ (เลือกและจัดลำดับ)'],
  'cad_header_text': ['表头文字', 'Header text', 'ข้อความหัวตาราง'],
  'cad_write_header': ['写入表头行', 'Write header row', 'เขียนแถวหัวตาราง'],
  'cad_delim': ['分隔符', 'Delimiter', 'ตัวคั่น'],
  'cad_ext': ['扩展名', 'Extension', 'นามสกุล'],
  'cad_encoding': ['编码', 'Encoding', 'การเข้ารหัส'],
  'cad_decimals': ['小数位', 'Decimals', 'ทศนิยม'],
  'cad_unit': ['输出单位', 'Output unit', 'หน่วยส่งออก'],
  'cad_top': ['顶面标记', 'Top text', 'ข้อความด้านบน'],
  'cad_bottom': ['底面标记', 'Bottom text', 'ข้อความด้านล่าง'],
  'cad_include_unmatched': ['同时输出不在BOM中的坐标', 'Also write coordinates not in the BOM', 'ส่งออกพิกัดที่ไม่อยู่ใน BOM ด้วย'],
  'cad_side_from_station': ['坐标文件无面别时按站位表判断 (A=顶面, B=底面)', 'If no layer column, use station list (A = top, B = bottom)', 'หากไม่มีคอลัมน์ด้าน ใช้ตารางสถานี (A = บน, B = ล่าง)'],
  'cad_preview': ['预览', 'Preview', 'ตัวอย่าง'],
  'delim_comma': ['逗号 ,', 'Comma ,', 'จุลภาค ,'],
  'delim_tab': ['制表符', 'Tab', 'แท็บ'],
  'delim_space': ['空格', 'Space', 'ช่องว่าง'],
  'delim_semicolon': ['分号 ;', 'Semicolon ;', 'อัฒภาค ;'],
  'cad_format': ['文件格式', 'File format', 'รูปแบบไฟล์'],
  'fmt_xlsx': ['Excel (.xlsx)', 'Excel (.xlsx)', 'Excel (.xlsx)'],
  'fmt_text': ['文本 (CSV/TXT)', 'Text (CSV/TXT)', 'ข้อความ (CSV/TXT)'],
  'field_qty': ['数量 (固定 1)', 'Qty (always 1)', 'จำนวน (1 เสมอ)'],
  'field_loadedPartNo': ['上料料号', 'Loaded part no.', 'รหัสที่ติดตั้ง'],
  'field_ref': ['位号 (Location)', 'Designator (Location)', 'ตำแหน่ง (Location)'],
  'field_x': ['X 坐标', 'X', 'X'],
  'field_y': ['Y 坐标', 'Y', 'Y'],
  'field_rotation': ['角度', 'Rotation', 'มุม'],
  'field_side': ['面别', 'Side', 'ด้าน'],
  'field_partNo': ['BOM料号', 'BOM part no.', 'รหัส BOM'],
  'field_description': ['规格 (BOM品名)', 'Specification', 'สเปก'],
  'field_value': ['值', 'Value', 'ค่า'],
  'field_footprint': ['封装', 'Footprint', 'ฟุตพริ้นต์'],
  'field_slot': ['站位', 'Slot', 'สล็อต'],
  'move_up': ['上移', 'Move up', 'เลื่อนขึ้น'],
  'move_down': ['下移', 'Move down', 'เลื่อนลง'],

  // Rules dialog
  'rules_title': ['核对规则', 'Check Rules', 'กฎการตรวจสอบ'],
  'rules_keywords': ['排除关键字 (品名/规格包含即视为非SMT物料，每行一个)', 'Exclusion keywords (name/spec contains → not SMT, one per line)', 'คำยกเว้น (ชื่อ/สเปกมีคำนี้ → ไม่ใช่ SMT หนึ่งบรรทัดต่อคำ)'],
  'rules_prefixes': ['排除料号前缀 (每行一个)', 'Excluded part-number prefixes (one per line)', 'คำนำหน้ารหัสที่ยกเว้น (หนึ่งบรรทัดต่อรายการ)'],
  'rules_ignore_refs': ['忽略位号 (Mark 点等，支持 * 通配，每行一个)', 'Ignored designators (fiducials etc., * wildcard, one per line)', 'ตำแหน่งที่ละเว้น (ใช้ * ได้ หนึ่งบรรทัดต่อรายการ)'],
  'rules_subs': ['替代料对照 (每行: 主料号=替代料号1,替代料号2)', 'Alternates (per line: MAIN=ALT1,ALT2)', 'วัสดุทดแทน (ต่อบรรทัด: หลัก=ทดแทน1,ทดแทน2)'],
  'rules_subs_note': ['BOM 中的替代料列会自动识别，这里补充额外的替代关系', 'Alternates in the BOM are read automatically; add extra pairs here', 'วัสดุทดแทนใน BOM อ่านอัตโนมัติ เพิ่มเติมได้ที่นี่'],
  'rules_exclude_norefs': ['无插件位置的 BOM 行归入已排除物料', 'BOM lines without designators go to Excluded', 'บรรทัด BOM ที่ไม่มีตำแหน่งจัดเป็นยกเว้น'],
  'rules_check_qty': ['核对 BOM 组成用量与位号数量', 'Compare BOM quantity with designator count', 'เปรียบเทียบจำนวน BOM กับจำนวนตำแหน่ง'],
  'rules_reset': ['恢复默认', 'Restore defaults', 'คืนค่าเริ่มต้น'],
  'rules_rerun': ['规则已更新，重新核对后生效', 'Rules updated; re-run the check to apply', 'อัปเดตกฎแล้ว ตรวจใหม่เพื่อใช้งาน'],

  'dlg_ok': ['确定', 'OK', 'ตกลง'],
  'dlg_cancel': ['取消', 'Cancel', 'ยกเลิก'],
  'dlg_save': ['保存', 'Save', 'บันทึก'],
  'dlg_continue': ['继续', 'Continue', 'ดำเนินการต่อ'],
  'dlg_close': ['关闭', 'Close', 'ปิด'],

  // Board view
  'board_empty': ['导入坐标文件后显示元件分布', 'Import a coordinate file to see placements', 'นำเข้าไฟล์พิกัดเพื่อดูตำแหน่งชิ้นส่วน'],
  'board_not_in_bom': ['不在BOM', 'Not in BOM', 'ไม่อยู่ใน BOM'],
  'board_unchecked': ['未核对', 'Unchecked', 'ยังไม่ตรวจ'],
  'board_fit': ['适应窗口', 'Fit', 'พอดีหน้าต่าง'],

  'empty_check': ['导入 T100 BOM 和站位表后，点击「开始核对」', 'Import the T100 BOM and station lists, then click Run Check', 'นำเข้า T100 BOM และตารางสถานี แล้วกด เริ่มตรวจ'],
  'empty_filter': ['没有符合条件的记录', 'No matching rows', 'ไม่มีรายการที่ตรงกัน'],
  'empty_cad': ['完成核对并导入坐标文件后显示 CAD 预览', 'Run the check and import coordinates to preview the CAD file', 'ตรวจสอบและนำเข้าพิกัดเพื่อดูตัวอย่างไฟล์ CAD'],
  'search_hint': ['搜索料号 / 位号 / 描述', 'Search part no. / designator / description', 'ค้นหารหัส / ตำแหน่ง / รายละเอียด'],

  'about_text': [
    'SMT 首件核对工具：T100 BOM 与站位表 A/B 核对，合并后结合原始坐标生成 FAI i450 首件测试仪 CAD 坐标文件。',
    'SMT first-article tool: checks the T100 BOM against station lists A/B, then merges with the original coordinates to build the CAD file for the FAI i450 tester.',
    'เครื่องมือตรวจชิ้นงานแรก SMT: ตรวจ T100 BOM กับตารางสถานี A/B แล้วรวมกับพิกัดต้นฉบับเพื่อสร้างไฟล์ CAD สำหรับเครื่อง FAI i450',
  ],
  'about_version': ['版本 {v}', 'Version {v}', 'เวอร์ชัน {v}'],
  'about_config': ['配置文件位置', 'Settings file', 'ไฟล์การตั้งค่า'],
};

class Texts {
  Texts(this.lang) : _i = supportedLanguages.indexOf(lang).clamp(0, 2);

  final String lang;
  final int _i;

  String t(String key, [Map<String, Object?> args = const {}]) {
    final entry = _t[key];
    var s = entry == null ? key : entry[_i];
    for (final e in args.entries) {
      s = s.replaceAll('{${e.key}}', '${e.value ?? ''}');
    }
    return s.trim();
  }

  static bool has(String key) => _t.containsKey(key);

  static Iterable<String> get keys => _t.keys;
}

/// Native names shown on the language buttons.
const languageNames = {'zh': '中文', 'en': 'English', 'th': 'ไทย'};
