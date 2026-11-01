import Foundation

public enum WindowsExecutableIcon {
    /// Read PE resources without loading or running the Windows executable.
    /// Reassemble the first usable RT_GROUP_ICON and its RT_ICON frames as ICO.
    public static func iconData(in executable: Data) -> Data? {
        try? Resources(executable).icon()
    }

    private enum Invalid: Error { case resource }
    private struct Bytes {
        let data: Data
        func range(_ offset: Int, _ count: Int) throws -> Range<Int> {
            guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { throw Invalid.resource }
            return offset..<(offset + count)
        }
        func u16(_ offset: Int) throws -> Int {
            _ = try range(offset, 2)
            return Int(data[offset]) | Int(data[offset+1]) << 8
        }
        func u32(_ offset: Int) throws -> Int {
            _ = try range(offset, 4)
            return (0..<4).reduce(0) { $0 | Int(data[offset+$1]) << (8*$1) }
        }
        func slice(_ offset: Int, _ count: Int) throws -> Data { data.subdata(in: try range(offset, count)) }
    }
    private struct Section {
        let rva: Int, raw: Int, size: Int
    }
    private struct Entry {
        let id: Int, offset: Int, isDirectory: Bool
    }
    private struct Resources {
        let file: Bytes
        let sections: [Section]
        let base: Int, size: Int

        init(_ data: Data) throws {
            let file = Bytes(data: data)
            guard try file.u16(0) == 0x5a4d else { throw Invalid.resource }
            let pe = try file.u32(0x3c)
            guard try file.u32(pe) == 0x4550 else { throw Invalid.resource }
            let sectionCount = try file.u16(pe+6), optionalSize = try file.u16(pe+20)
            let optional = pe+24, magic = try file.u16(optional)
            guard magic == 0x10b || magic == 0x20b else { throw Invalid.resource }
            let directories = magic == 0x20b ? 112 : 96
            guard optionalSize >= directories+24, try file.u32(optional+directories-4) >= 3 else { throw Invalid.resource }
            let table = optional + optionalSize
            _ = try file.range(table, sectionCount * 40)
            let sections = try (0..<sectionCount).map { index in
                let offset = table + index * 40
                return Section(rva: try file.u32(offset+12), raw: try file.u32(offset+20), size: try file.u32(offset+16))
            }
            let rva = try file.u32(optional+directories+16), size = try file.u32(optional+directories+20)
            guard rva != 0, size >= 16 else { throw Invalid.resource }
            self.file = file; self.sections = sections; self.size = size
            self.base = try Self.fileOffset(rva, size, sections, file)
        }

        private static func fileOffset(_ rva: Int, _ size: Int, _ sections: [Section], _ file: Bytes) throws -> Int {
            for section in sections where rva >= section.rva {
                let delta = rva - section.rva
                if delta < section.size, size <= section.size - delta {
                    let offset = section.raw + delta
                    _ = try file.range(offset, size)
                    return offset
                }
            }
            throw Invalid.resource
        }
        private func resourceOffset(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset <= size, count <= size-offset else { throw Invalid.resource }
            return base + offset
        }
        private func directory(_ relative: Int) throws -> [Entry] {
            let offset = try resourceOffset(relative, 16)
            let count = try file.u16(offset+12) + file.u16(offset+14)
            _ = try resourceOffset(relative+16, count*8)
            return try (0..<count).map { index in
                let row = offset + 16 + index*8, target = try file.u32(row+4)
                return Entry(id: try file.u32(row), offset: target & 0x7fffffff, isDirectory: target & 0x80000000 != 0)
            }
        }
        private func children(_ entry: Entry) throws -> [Entry] {
            guard entry.isDirectory else { throw Invalid.resource }
            return try directory(entry.offset)
        }
        private func payload(_ entry: Entry) throws -> Data {
            guard !entry.isDirectory else { throw Invalid.resource }
            let offset = try resourceOffset(entry.offset, 16)
            let rva = try file.u32(offset), count = try file.u32(offset+4)
            // Actual icon frames are small; never allocate arbitrary PE payload sizes.
            guard count > 0, count <= 4*1024*1024 else { throw Invalid.resource }
            return try file.slice(Self.fileOffset(rva, count, sections, file), count)
        }
        func icon() throws -> Data {
            let types = try directory(0)
            guard let groupType = types.first(where: { $0.id == 14 }), let iconType = types.first(where: { $0.id == 3 }) else { throw Invalid.resource }
            let icons = try children(iconType)
            // Resource order matches Explorer: named groups, then numbered groups.
            for group in try children(groupType) {
                for language in try children(group) {
                    if let icon = try? assemble(payload(language), language: language.id, icons: icons) { return icon }
                }
            }
            throw Invalid.resource
        }
        private func assemble(_ data: Data, language: Int, icons: [Entry]) throws -> Data {
            let group = Bytes(data: data), count = try group.u16(4)
            guard try group.u16(0) == 0, try group.u16(2) == 1, count > 0, count <= 256 else { throw Invalid.resource }
            _ = try group.range(6, count*14)
            var header = try group.slice(0, 6), frames = Data()
            for index in 0..<count {
                let row = 6 + index*14, id = try group.u16(row+12)
                guard let icon = icons.first(where: { $0.id == id }) else { throw Invalid.resource }
                let languages = try children(icon)
                guard let image = languages.first(where: { $0.id == language }) ?? languages.first else { throw Invalid.resource }
                let frame = try payload(image)
                guard frame.count == (try group.u32(row+8)), frames.count + frame.count <= 32*1024*1024 else { throw Invalid.resource }
                header.append(try group.slice(row, 12))
                let offset = UInt32(6 + count*16 + frames.count)
                for byte in 0..<4 { header.append(UInt8(truncatingIfNeeded: offset >> (byte*8))) }
                frames.append(frame)
            }
            header.append(frames)
            return header
        }
    }
}
