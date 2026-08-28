import Foundation

public struct FileNameDecoder: Sendable {

    /// 智能解码压缩包内的文件名（优先 UTF-8，失败后回退 GBK / GB18030 / Shift-JIS / CP437）
    public static func decode(cString: UnsafePointer<CChar>) -> String {
        // 先尝试 UTF-8
        if let utf8Str = String(validatingUTF8: cString) {
            return utf8Str
        }

        // 如果不是合法的 UTF-8，尝试获取字节数据进行多编码探测
        let len = strlen(cString)
        let data = Data(bytes: cString, count: len)

        // 尝试 GB18030 / GBK (Windows 简体中文)
        let gbkEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let gbkStr = String(data: data, encoding: gbkEncoding) {
            return gbkStr
        }

        // 尝试 Shift_JIS (日文)
        let shiftJISEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        if let sjisStr = String(data: data, encoding: shiftJISEncoding) {
            return sjisStr
        }

        // 尝试 Windows-1252 / CP437 (欧美通用)
        let cp437Encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
        if let cp437Str = String(data: data, encoding: cp437Encoding) {
            return cp437Str
        }

        // 最终兜底：非破坏性替换
        return String(cString: cString)
    }
}
