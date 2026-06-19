import Foundation
import ZIPFoundation

// MARK: - FileInfo（バージョン解析エントリポイント）

enum FileInfo {

    private static let magic: [UInt8] = [
        0x06, 0x06, 0xED, 0xF5, 0xD8, 0x1D, 0x46, 0xE5,
        0xBD, 0x31, 0xEF, 0xE7, 0xFE, 0x74, 0xB7, 0x1D
    ]

    // MARK: - Public Entry

    /// ファイルを解析して FileClass を返す。
    /// - Parameters:
    ///   - useFullVersion: true = xref でフルバージョン取得（設定「フルバージョン」時）
    ///   - hideBuildNumber: true = フルバージョン表示時にビルド番号（4桁目）を除く（x.x.x.x → x.x.x）
    static func parse(url: URL, useFullVersion: Bool, hideBuildNumber: Bool = true) -> FileClass {
        let fc = FileClass()
        fc.file = url

        let ext = url.pathExtension.lowercased()

        // ヘッダーを先に読み、magic 一致ならバイナリ解析へ進む。
        // magic 不一致のときのみ IDML(ZIP) を拡張子非依存で確認することで、
        // 通常の indd/indt で不要な ZIP オープン（末尾走査）を避ける。
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            fc.isVersionUndetected = true
            return fc
        }
        defer { try? fh.close() }

        // ── ヘッダー 38 バイト読み込み
        guard let header = try? fh.read(upToCount: 0x26), header.count >= 0x26 else {
            fc.isVersionUndetected = true
            return fc
        }

        // マジック検証：不一致なら IDML(ZIP) かどうかをコンテンツで確認（拡張子に依存しない）
        guard Array(header[0..<16]) == magic else {
            if isIDMLPackage(url: url) {
                parseIDML(url: url, fc: fc)
            } else {
                fc.isNotInDesign = true
            }
            return fc
        }

        // ファイル種別文字列（0x10–0x17）
        let kindStr = String(bytes: header[0x10..<0x18], encoding: .ascii) ?? ""
        let contentKind: String
        switch kindStr {
        case "DOCUMENT": contentKind = ext == "indt" ? "indt" : "indd"
        case "BOOKBOOK": contentKind = "indb"
        case "LIBRARY4", "LIBRARY2": contentKind = "indl"
        default:
            fc.isNotInDesign = true
            return fc
        }

        // 拡張子との整合確認
        let expectedExts: [String: [String]] = [
            "indd": ["indd"],
            "indt": ["indt"],
            "indb": ["indb"],
            "indl": ["indl"],
        ]
        if let exts = expectedExts[contentKind], !exts.contains(ext) {
            fc.isExtMismatch = true
        }
        fc.contentKind = contentKind

        // フォーマット判別・major/minor 取得
        let newFmt = Array(header[0x18..<0x1c]) == [0x01, 0x70, 0x0F, 0x00]
        let headerMajor = Int(newFmt ? header[0x1d] : header[0x20])
        let headerMinor = Int(newFmt ? header[0x21] : header[0x24])

        fc.versionMajor = headerMajor

        // .indb / .indl は xref 構造を持たない
        if kindStr == "BOOKBOOK" {
            // indb: 別名保存の仕組みでバグ回避済み → header の major.minor を使用
            fc.versionMinor = headerMinor
            let display = "\(headerMajor).\(headerMinor)"
            fc.versionDisplay = display
            fc.versionLabel = "InDesign \(appName(headerMajor, headerMinor)) (\(display))"
            return fc
        }
        if kindStr.hasPrefix("LIBRARY") {
            // indl: CS6〜CC2018(v8〜v13)はバグあり・xref なし → major のみ。それ以外は major.minor
            if headerMajor >= 8 && headerMajor <= 13 {
                fc.versionMinor = -1
                let display = "\(headerMajor)"
                fc.versionDisplay = display
                fc.versionLabel = "InDesign \(appName(headerMajor, 0)) (\(display))"
            } else {
                fc.versionMinor = headerMinor
                let display = "\(headerMajor).\(headerMinor)"
                fc.versionDisplay = display
                fc.versionLabel = "InDesign \(appName(headerMajor, headerMinor)) (\(display))"
            }
            return fc
        }

        // .indd / .indt の minor 決定
        // major 8〜13（CS6〜CC2018）は xref が必要（ヘッダー minor が不正確）
        // 設定「フルバージョン」は全 major で xref 実行
        let needsXref = useFullVersion || (headerMajor >= 8 && headerMajor <= 13)

        if needsXref {
            try? fh.seek(toOffset: 0)
            if let data = try? fh.readToEnd(),
               let xrefVer = runXref(data: data, major: headerMajor, minor: headerMinor) {
                let parts = xrefVer.split(separator: ".")
                let major = Int(parts[0]) ?? headerMajor
                let minor = parts.count >= 2 ? (Int(parts[1]) ?? headerMinor) : headerMinor

                fc.versionMajor = major
                fc.versionMinor = minor

                if useFullVersion {
                    // ビルド番号（4桁目）を除く設定なら x.x.x.x → x.x.x に切り詰める
                    let fullDisplay = hideBuildNumber
                        ? xrefVer.split(separator: ".").prefix(3).joined(separator: ".")
                        : xrefVer
                    fc.versionDisplay = fullDisplay
                    fc.versionLabel = "InDesign \(appName(major, minor)) (\(fullDisplay))"
                } else {
                    let display = "\(major).\(minor)"
                    fc.versionDisplay = display
                    fc.versionLabel = "InDesign \(appName(major, minor)) (\(display))"
                }
                return fc
            }
            // xref 失敗時はヘッダーにフォールバック
        }

        // ヘッダーのみ
        fc.versionMinor = headerMinor
        let display = "\(headerMajor).\(headerMinor)"
        fc.versionDisplay = display
        fc.versionLabel = "InDesign \(appName(headerMajor, headerMinor)) (\(display))"
        return fc
    }

    // MARK: - xref スキャン（返値: "M.m.p.b" 文字列、失敗時 nil）

    private static func runXref(data: Data, major: Int, minor: Int) -> String? {
        let blockSize = 0x1000
        let blockCount = data.count / blockSize
        guard blockCount > 2 else { return nil }

        // ヘッダー minor の更新バグは major 8〜13（CS6〜CC2018）のみ。
        // それ以外（CS5.5 以前 / CC2019 以降）はヘッダー minor が信頼できるので minor まで絞り込む。
        let prefix = (major <= 7 || major >= 14) ? "\(major).\(minor)." : "\(major)."
        let pre = [UInt8](prefix.utf8)

        var sentinelHits: [(globalOffset: Int, version: String, ts6: UInt64)] = []
        var lastHits:     [(globalOffset: Int, version: String, ts6: UInt64)] = []

        // バイト走査は Data 越しの subscript / range(of:) を避け、生ポインタ＋memchr で行う。
        // trailer (+0xff4) の bid=8/9 抽出・プレフィックス絞り込み・sentinel 判定・TS6 読み出し・
        // ブロック境界(4096)の扱いは、いずれも従来の Data 版とバイト単位で完全に同一。
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let rawBase = raw.baseAddress else { return }
            let p = rawBase.assumingMemoryBound(to: UInt8.self)
            let n = raw.count

            // 各ブロックの trailer (+0xff4) を読み、bid==8 / bid==9 の候補を収集。
            var candidates: [Int] = []
            candidates.reserveCapacity(blockCount / 4 + 1)
            for i in 0..<blockCount {
                let t = i * blockSize + 0xff4
                if t + 4 <= n {
                    let bid = u32le(p, t)
                    if bid == 8 || bid == 9 { candidates.append(i) }
                }
            }

            for i in candidates {
                let chunkStart = i * blockSize
                let chunkEnd   = chunkStart + blockSize
                if chunkEnd > n { continue }

                var searchFrom = chunkStart
                while searchFrom < chunkEnd,
                      let found = memchr(rawBase + searchFrom, 0x2E, chunkEnd - searchFrom) {
                    let dotIndex = UnsafeRawPointer(found) - rawBase
                    guard let (vs, ve) = versionRangeFast(p, dotAt: dotIndex, lo: chunkStart, hi: chunkEnd),
                          startsWith(p, vs, ve, pre) else {
                        searchFrom = dotIndex + 1
                        continue
                    }
                    let afterEnd = min(ve + 24, chunkEnd)
                    let ts6 = readTS6Fast(p, from: ve, hi: chunkEnd)
                    let ver = String(decoding: UnsafeBufferPointer(start: p + vs, count: ve - vs), as: UTF8.self)
                    let globalOffset = vs
                    if hasSentinelFast(p, lo: ve, hi: afterEnd) {
                        sentinelHits.append((globalOffset, ver, ts6))
                    }
                    lastHits.append((globalOffset, ver, ts6))
                    searchFrom = ve
                }
            }
        }

        // 採用アルゴリズム: ts32（バージョン文字列直後 +2..+5 を LE u32、FILETIME hi32 を
        // 約 7 分粒度に切り詰めた保存時刻）を主キー、物理オフセットをタイブレーカーにして
        // 降順最大を採用。詳細は xref採用アルゴリズム解析.md
        let cmp: (
            (globalOffset: Int, version: String, ts6: UInt64),
            (globalOffset: Int, version: String, ts6: UInt64)
        ) -> Bool = { a, b in
            let aTS32 = (a.ts6 >> 16) & 0xFFFFFFFF
            let bTS32 = (b.ts6 >> 16) & 0xFFFFFFFF
            if aTS32 != bTS32 { return aTS32 < bTS32 }
            return a.globalOffset < b.globalOffset
        }

        if let chosen = sentinelHits.max(by: cmp) {
            return chosen.version
        }
        if let chosen = lastHits.max(by: cmp) {
            return chosen.version
        }
        return nil
    }

    // MARK: - IDML パーサー

    private static func parseIDML(url: URL, fc: FileClass) {
        fc.contentKind = "idml"
        let ext = url.pathExtension.lowercased()
        if ext != "idml" { fc.isExtMismatch = true }

        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { fc.isNotInDesign = true; return }
        guard let entry = archive["designmap.xml"] else {
            fc.isNotInDesign = true
            return
        }

        var xmlData = Data()
        do { _ = try archive.extract(entry) { xmlData.append($0) } }
        catch { fc.isVersionUndetected = true; return }

        let head = xmlData.prefix(2048)
        guard let text = String(data: head, encoding: .utf8) else {
            fc.isVersionUndetected = true
            return
        }

        guard let product = firstMatch(in: text, pattern: #"product="([^"]+)""#),
              !product.isEmpty else {
            fc.isVersionUndetected = true
            return
        }

        let mm: String
        if let lp = product.firstIndex(of: "(") {
            mm = String(product[..<lp])
        } else {
            mm = product
        }
        let mmParts = mm.split(separator: ".")
        let major = mmParts.first.flatMap { Int($0) } ?? 0
        let minor = mmParts.count >= 2 ? (Int(mmParts[1]) ?? 0) : 0

        fc.versionMajor = major
        fc.versionMinor = minor
        let display = "\(major).\(minor)"
        fc.versionDisplay = display
        fc.versionLabel = "InDesign \(appName(major, minor)) (\(display))"
    }

    // MARK: - バージョン名変換

    static func versionName(_ ver: String) -> String {
        let parts = ver.components(separatedBy: ".")
        let major = Int(parts.first ?? "") ?? 0
        let minor = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
        return appName(major, minor)
    }

    static func appName(_ major: Int, _ minor: Int) -> String {
        switch major {
        case 3:  return "CS"
        case 4:  return "CS2"
        case 5:  return "CS3"
        case 6:  return "CS4"
        case 7:  return minor >= 5 ? "CS5.5" : "CS5"
        case 8:  return "CS6"
        case 9:  return "CC"
        case 10: return "CC 2014"
        case 11: return "CC 2015"
        case 12: return "CC 2017"
        case 13: return "CC 2018"
        case 14: return "CC 2019"
        default: return major >= 15 ? String(major + 2005) : "\(major)"
        }
    }

    // MARK: - Private helpers

    /// ZIP 内の mimetype エントリで IDML パッケージかどうか確認する
    private static func isIDMLPackage(url: URL) -> Bool {
        do {
            let archive = try Archive(url: url, accessMode: .read)
            guard let entry = archive["mimetype"] else { return false }
            var raw = Data()
            _ = try archive.extract(entry) { raw.append($0) }
            let mime = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return mime == "application/vnd.adobe.indesign-idml-package"
        } catch {
            return false
        }
    }

    // MARK: - xref バイト走査ヘルパー（生ポインタ版）
    //
    // バージョンレコードの形式:
    //   旧フォーマット（CS）:     [len] 0x40 [len] [version] [TS6]
    //   新フォーマット（CC以降）: [len] 0x40 [version] [TS6]
    // 長さプレフィックスを尊重して version を切り出す（貪欲マッチだと
    // 例: "12.1.0.56" が直後の TS6 先頭バイト '8'(=0x38) を食って "12.1.0.568" になる）。
    // いずれも [lo,hi) のブロック境界内だけを参照し、従来の Data 版とバイト単位で同一の結果を返す。

    @inline(__always) private static func u32le(_ p: UnsafePointer<UInt8>, _ i: Int) -> UInt32 {
        UInt32(p[i]) | (UInt32(p[i + 1]) << 8) | (UInt32(p[i + 2]) << 16) | (UInt32(p[i + 3]) << 24)
    }

    @inline(__always) private static func isDig(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    /// "." の位置から M.m.p.b を [lo,hi) 内で解析。返値は p への絶対 index 範囲 (start, end)。
    @inline(__always)
    private static func versionRangeFast(_ p: UnsafePointer<UInt8>, dotAt: Int, lo: Int, hi: Int) -> (Int, Int)? {
        guard dotAt > lo else { return nil }
        var start = dotAt - 1
        while start > lo && isDig(p[start - 1]) { start -= 1 }
        guard isDig(p[start]) else { return nil }

        var pos = dotAt + 1
        var dots = 1
        while pos < hi {
            let b = p[pos]
            if isDig(b) { pos += 1 }
            else if b == 0x2E && dots < 3 { dots += 1; pos += 1 }
            else { break }
        }
        guard dots == 3, pos > dotAt + 1, isDig(p[pos - 1]) else { return nil }

        let offsetFromStart = start - lo
        let greedyLen = pos - start
        if offsetFromStart >= 2 {
            if p[start - 1] == 0x40 {
                let d = Int(p[start - 2])
                if d >= 5 && d <= 15 && d <= greedyLen { return (start, start + d) }
            } else if p[start - 2] == 0x40 {
                let d = Int(p[start - 1])
                if d >= 5 && d <= 15 && d <= greedyLen { return (start, start + d) }
            }
        }
        return (start, pos)
    }

    /// バージョン文字列直後の6バイトを LE u48 として読む（hi で打ち切り）。
    @inline(__always)
    private static func readTS6Fast(_ p: UnsafePointer<UInt8>, from start: Int, hi: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<6 {
            let idx = start + i
            if idx >= hi { break }
            v |= UInt64(p[idx]) << (i * 8)
        }
        return v
    }

    /// センチネル: [lo,hi) で 0x40 を全走査し、直後に 6バイト以上 0x00 が続くものを検出。
    @inline(__always)
    private static func hasSentinelFast(_ p: UnsafePointer<UInt8>, lo: Int, hi: Int) -> Bool {
        var i = lo
        while i < hi {
            if p[i] == 0x40 && i + 7 <= hi {
                var ok = true
                for k in 1...6 where p[i + k] != 0x00 { ok = false; break }
                if ok { return true }
            }
            i += 1
        }
        return false
    }

    /// p[start..<end] が pre で始まるか（バイト比較）。
    @inline(__always)
    private static func startsWith(_ p: UnsafePointer<UInt8>, _ start: Int, _ end: Int, _ pre: [UInt8]) -> Bool {
        if end - start < pre.count { return false }
        for k in 0..<pre.count where p[start + k] != pre[k] { return false }
        return true
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
