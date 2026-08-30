import Foundation
import SwiftUI
import AppKit

public enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh_Hans"
    case zhHant = "zh_Hant"
    case en = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        }
    }
}

public enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    @MainActor
    public func displayName(using l10n: LocalizationManager) -> String {
        switch self {
        case .system: return l10n.t("theme_system")
        case .light: return l10n.t("theme_light")
        case .dark: return l10n.t("theme_dark")
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    @Published public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "dwum_language")
        }
    }

    @Published public var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "dwum_theme")
            applyTheme()
        }
    }

    private init() {
        let savedLangRaw = UserDefaults.standard.string(forKey: "dwum_language") ?? "zh_Hans"
        self.currentLanguage = AppLanguage(rawValue: savedLangRaw) ?? .zhHans

        let savedThemeRaw = UserDefaults.standard.string(forKey: "dwum_theme") ?? "system"
        self.currentTheme = AppTheme(rawValue: savedThemeRaw) ?? .system

        applyTheme()
    }

    public func applyTheme() {
        DispatchQueue.main.async {
            switch self.currentTheme {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    @MainActor
    public func setLanguage(_ lang: AppLanguage) {
        self.currentLanguage = lang
    }

    @MainActor
    public func setTheme(_ theme: AppTheme) {
        self.currentTheme = theme
    }

    @MainActor
    public func t(_ key: String) -> String {
        guard let dict = strings[key] else { return key }
        return dict[currentLanguage] ?? dict[.zhHans] ?? key
    }

    // MARK: - 全量多语言字典
    private let strings: [String: [AppLanguage: String]] = [
        // Tabs
        "tab_general": [
            .zhHans: "通用",
            .zhHant: "通用",
            .en: "General"
        ],
        "tab_appearance": [
            .zhHans: "外观",
            .zhHant: "外觀",
            .en: "Appearance"
        ],
        "tab_about": [
            .zhHans: "关于",
            .zhHant: "關於",
            .en: "About"
        ],

        // 主窗口
        "app_name": [
            .zhHans: "DeleteWhenUnzipMac",
            .zhHant: "DeleteWhenUnzipMac",
            .en: "DeleteWhenUnzipMac"
        ],
        "disk_free": [
            .zhHans: "磁盘剩余",
            .zhHant: "磁碟剩餘",
            .en: "Disk Free"
        ],
        "drop_title": [
            .zhHans: "拖入压缩包，边解压边释放空间",
            .zhHant: "拖入壓縮包，邊解壓邊釋放空間",
            .en: "Drop archive here to unzip & reclaim space"
        ],
        "drop_title_targeted": [
            .zhHans: "松开即可开始分析",
            .zhHant: "放開即可開始分析",
            .en: "Release to analyze archive"
        ],
        "drop_formats": [
            .zhHans: "单文件与多分卷: ZIP · RAR · 7Z · TAR · GZIP · .part1.rar · .z01 · .7z.001",
            .zhHant: "單檔案與多分卷: ZIP · RAR · 7Z · TAR · GZIP · .part1.rar · .z01 · .7z.001",
            .en: "Single & Multi-volume: ZIP · RAR · 7Z · TAR · GZIP · .part1.rar · .z01 · .7z.001"
        ],
        "choose_file": [
            .zhHans: "选取文件…",
            .zhHant: "選取檔案…",
            .en: "Choose File…"
        ],
        "analyzing": [
            .zhHans: "正在分析压缩包结构与分卷信息...",
            .zhHant: "正在分析壓縮包結構與分卷資訊...",
            .en: "Analyzing archive structure and volumes..."
        ],

        // Warning Sheet
        "warning_title": [
            .zhHans: "⚠️ 破坏性操作确认",
            .zhHant: "⚠️ 破壞性操作確認",
            .en: "⚠️ Destructive Action Confirmation"
        ],
        "warning_desc": [
            .zhHans: "解压过程中，原压缩包将被物理销毁以回收磁盘空间，操作不可撤销！",
            .zhHant: "解壓過程中，原壓縮包將被物理銷毀以回收磁碟空間，操作不可撤銷！",
            .en: "The original archive will be physically destroyed during extraction to reclaim space. This cannot be undone!"
        ],
        "password_optional": [
            .zhHans: "解压密码（若有）",
            .zhHant: "解壓密碼（若有）",
            .en: "Password (Optional)"
        ],
        "password_placeholder": [
            .zhHans: "输入密码（未加密请留空）",
            .zhHant: "輸入密碼（未加密請留空）",
            .en: "Enter password (leave empty if not encrypted)"
        ],
        "chunk_size": [
            .zhHans: "分块大小",
            .zhHant: "分塊大小",
            .en: "Chunk Size"
        ],
        "start_extraction": [
            .zhHans: "开始解压与删除",
            .zhHant: "開始解壓與刪除",
            .en: "Start Extraction & Deletion"
        ],
        "cancel": [
            .zhHans: "取消",
            .zhHant: "取消",
            .en: "Cancel"
        ],

        // Progress
        "extracting_title": [
            .zhHans: "正在解压并物理打洞回收空间...",
            .zhHant: "正在解壓並物理打洞回收空間...",
            .en: "Extracting & reclaiming space via hole punching..."
        ],
        "processed": [
            .zhHans: "已处理",
            .zhHant: "已處理",
            .en: "Processed"
        ],
        "total_size": [
            .zhHans: "总大小",
            .zhHant: "總大小",
            .en: "Total Size"
        ],
        "speed": [
            .zhHans: "解压速度",
            .zhHant: "解壓速度",
            .en: "Speed"
        ],
        "current_file": [
            .zhHans: "当前正在处理",
            .zhHant: "目前正在處理",
            .en: "Current File"
        ],
        "cancel_extraction": [
            .zhHans: "取消解压",
            .zhHant: "取消解壓",
            .en: "Cancel Extraction"
        ],

        // Completed
        "completed_title": [
            .zhHans: "解压已顺利完成！",
            .zhHant: "解壓已順利完成！",
            .en: "Extraction Completed!"
        ],
        "completed_desc": [
            .zhHans: "原始压缩文件已全部删除，目标文件已保存至：",
            .zhHant: "原始壓縮檔案已全部刪除，目標檔案已儲存至：",
            .en: "Source archives have been deleted. Extracted files saved to:"
        ],
        "reveal_in_finder": [
            .zhHans: "在访达中显示",
            .zhHant: "在訪達中顯示",
            .en: "Show in Finder"
        ],
        "done": [
            .zhHans: "完成",
            .zhHant: "完成",
            .en: "Done"
        ],
        "failed_title": [
            .zhHans: "解压失败",
            .zhHant: "解壓失敗",
            .en: "Extraction Failed"
        ],
        "cancelled_title": [
            .zhHans: "操作已取消",
            .zhHant: "操作已取消",
            .en: "Extraction Cancelled"
        ],
        "back": [
            .zhHans: "返回",
            .zhHant: "返回",
            .en: "Back"
        ],

        // General Pane
        "section_perf": [
            .zhHans: "解压与性能",
            .zhHant: "解壓與效能",
            .en: "Extraction & Performance"
        ],
        "default_chunk_size": [
            .zhHans: "默认分块大小",
            .zhHant: "預設分塊大小",
            .en: "Default Chunk Size"
        ],
        "chunk_size_tip": [
            .zhHans: "分块大小影响空间回收频率与内存占用。推荐 10 ~ 50 MB。",
            .zhHant: "分塊大小影響空間回收頻率與記憶體佔用。推薦 10 ~ 50 MB。",
            .en: "Chunk size affects space reclamation frequency and memory. 10 ~ 50 MB recommended."
        ],
        "section_cli": [
            .zhHans: "命令行工具",
            .zhHant: "命令列工具",
            .en: "Command Line Tool"
        ],
        "cli_name": [
            .zhHans: "dwum 命令行工具",
            .zhHant: "dwum 命令列工具",
            .en: "dwum Command Line Tool"
        ],
        "cli_installed_prefix": [
            .zhHans: "已安装到",
            .zhHant: "已安裝到",
            .en: "Installed at"
        ],
        "cli_not_installed": [
            .zhHans: "未安装 · 随时可在终端中运行 dwum 边解压边删除",
            .zhHant: "未安裝 · 隨時可在終端機中執行 dwum 邊解壓邊刪除",
            .en: "Not installed · Run dwum anytime in terminal to unzip & delete"
        ],
        "cli_check_update": [
            .zhHans: "检查更新",
            .zhHant: "檢查更新",
            .en: "Check for Updates"
        ],
        "cli_get_latest": [
            .zhHans: "获取最新版",
            .zhHant: "取得最新版",
            .en: "Get Latest"
        ],
        "section_automation": [
            .zhHans: "自动化行为",
            .zhHant: "自動化行為",
            .en: "Automation"
        ],
        "auto_reveal_finder": [
            .zhHans: "解压完成后在访达中显示目标文件夹",
            .zhHant: "解壓完成後在訪達中顯示目標資料夾",
            .en: "Reveal extracted folder in Finder upon completion"
        ],
        "show_destructive_warning": [
            .zhHans: "每次解压前显示不可逆删除确认",
            .zhHant: "每次解壓前顯示不可逆刪除確認",
            .en: "Show destructive confirmation warning before extraction"
        ],

        // Appearance Pane
        "section_language": [
            .zhHans: "语言",
            .zhHant: "語言",
            .en: "Language"
        ],
        "language_label": [
            .zhHans: "应用语言",
            .zhHant: "應用語言",
            .en: "App Language"
        ],
        "section_theme": [
            .zhHans: "外观主题",
            .zhHant: "外觀主題",
            .en: "Appearance Theme"
        ],
        "theme_label": [
            .zhHans: "主题模式",
            .zhHant: "主題模式",
            .en: "Theme Mode"
        ],
        "theme_system": [
            .zhHans: "随系统",
            .zhHant: "隨系統",
            .en: "System"
        ],
        "theme_light": [
            .zhHans: "浅色",
            .zhHant: "淺色",
            .en: "Light"
        ],
        "theme_dark": [
            .zhHans: "深色",
            .zhHant: "深色",
            .en: "Dark"
        ],

        // About Pane
        "version_prefix": [
            .zhHans: "版本",
            .zhHant: "版本",
            .en: "Version"
        ],
        "about_desc": [
            .zhHans: "适用于 macOS 的原生高效压缩包解压与即时删除工具。",
            .zhHant: "適用於 macOS 的原生高效壓縮包解壓與即時刪除工具。",
            .en: "Native high-performance archive extraction with real-time space reclamation for macOS."
        ],
        "section_author": [
            .zhHans: "关于作者",
            .zhHant: "關於作者",
            .en: "About Author"
        ],
        "section_tribute": [
            .zhHans: "灵感与致敬",
            .zhHant: "靈感與致敬",
            .en: "Inspiration & Credits"
        ],
        "tribute_desc": [
            .zhHans: "Windows / Python 原版边解压边删除工具 · 原作者: auto-Dog",
            .zhHant: "Windows / Python 原版邊解壓邊刪除工具 · 原作者: auto-Dog",
            .en: "Original Windows / Python unarchiver · Author: auto-Dog"
        ],
        "section_update": [
            .zhHans: "软件更新",
            .zhHant: "軟體更新",
            .en: "Software Update"
        ],
        "auto_update_toggle": [
            .zhHans: "启动时自动检查更新",
            .zhHant: "啟動時自動檢查更新",
            .en: "Automatically check for updates on launch"
        ],
        "check_update_btn": [
            .zhHans: "检查更新...",
            .zhHant: "檢查更新...",
            .en: "Check for Updates..."
        ],
        "checking_update": [
            .zhHans: "正在检查更新...",
            .zhHant: "正在檢查更新...",
            .en: "Checking for updates..."
        ],
        "up_to_date": [
            .zhHans: "已是最新版本",
            .zhHant: "已是最新版本",
            .en: "You're up to date"
        ],
        "new_version": [
            .zhHans: "发现新版本",
            .zhHant: "發現新版本",
            .en: "New version available"
        ]
    ]
}
