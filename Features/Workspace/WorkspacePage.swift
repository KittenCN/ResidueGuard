import Foundation

enum WorkspacePage: String, CaseIterable, Identifiable {
    case overview = "总览", applications = "应用关联"
    case loginItems = "登录项", backgroundItems = "后台登记"
    case userAgents = "用户启动代理", sharedAgents = "共享启动代理", daemons = "系统守护进程"
    case accessibility = "辅助功能", fullDisk = "完全磁盘访问", screen = "屏幕与系统音频录制"
    case input = "输入监控", camera = "摄像头", microphone = "麦克风", automation = "自动化"
    case files = "文件与文件夹", contacts = "通讯录", calendars = "日历", reminders = "提醒事项"
    case photos = "照片", bluetooth = "蓝牙", speech = "语音识别", developer = "开发者工具"
    case network = "本地网络", location = "定位", notifications = "通知", unknown = "其他与未知权限"
    case history = "操作历史与恢复", ignore = "忽略规则"
    var id: String { rawValue }
    var group: String {
        switch self {
        case .overview, .applications: "工作台"
        case .loginItems, .backgroundItems, .userAgents, .sharedAgents, .daemons: "启动与后台"
        case .history, .ignore: "管理"
        default: "权限"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .applications: "app.connected.to.app.below.fill"
        case .loginItems: "person.crop.circle.badge.checkmark"
        case .backgroundItems: "gearshape.2"
        case .userAgents, .sharedAgents, .daemons: "terminal"
        case .history: "clock.arrow.circlepath"
        case .ignore: "eye.slash"
        default: "hand.raised"
        }
    }
    var isPermission: Bool { group == "权限" }
}
