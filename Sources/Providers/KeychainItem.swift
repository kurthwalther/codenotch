import Foundation
import Security

/// Asking about a keychain item without asking for what is inside it.
///
/// The access control on another app's item guards its **data**, not its
/// attributes: `kSecReturnAttributes` is answered from the item's metadata and
/// never raises the "wants to access your confidential information" dialogue,
/// where `kSecReturnData` always may. `security find-generic-password` versus
/// the same command with `-w` is the same distinction from the shell.
///
/// That is what makes it worth asking often. The expensive read — the one that
/// can interrupt someone — then only has to happen when this says the item has
/// actually changed.
enum KeychainItem {
    /// When the owning app last wrote this item, or nil if there is no such
    /// item or macOS declined to say.
    static func modifiedAt(service: String, account: String? = nil) -> Date? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if let account { query[kSecAttrAccount] = account }

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [CFString: Any]
        else { return nil }
        return attributes[kSecAttrModificationDate] as? Date
    }

    enum ToolRead: Equatable {
        case data(Data)
        case notFound
        /// `security`'s exit status, or -1 if it could not be started.
        case failed(Int32)
    }

    /// The item's data, read by `/usr/bin/security` rather than by this app.
    ///
    /// For an item that tool wrote — Claude Code's is one — this is the read
    /// that never prompts. `security` is the item's author, so it is on the
    /// item's access list and in its `apple-tool:` partition for as long as the
    /// item exists, however often it is rewritten. A grant to *this* app is not
    /// that durable: Claude Code rewrites its item with
    /// `security add-generic-password -U` on every token refresh, and in
    /// practice "Always Allow" did not survive it — the dialogue came back
    /// several times a day. Claude Code reads its own token this same way.
    static func readViaSecurityTool(service: String,
                                    timeout: TimeInterval = 10) -> ToolRead {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failed(-1) }

        // A locked keychain makes `security` wait on an unlock dialogue. Give
        // up on it rather than hold the refresh behind it indefinitely.
        let deadline = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        // Drained before waiting: a pipe that fills up would block the tool
        // from exiting, and the wait would never return.
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        switch process.terminationStatus {
        case 0:  return .data(decodeToolOutput(printed))
        case 44: return .notFound   // errSecItemNotFound, as `security` exits
        default: return .failed(process.terminationStatus)
        }
    }

    /// `security -w` ends the password with a newline, and prints one it
    /// judges unprintable as hex instead — so the same item can come back
    /// either way.
    static func decodeToolOutput(_ printed: Data) -> Data {
        var bytes = printed
        if bytes.last == UInt8(ascii: "\n") { bytes.removeLast() }
        guard let text = String(data: bytes, encoding: .utf8),
              !text.isEmpty, text.count.isMultiple(of: 2),
              text.allSatisfy(\.isHexDigit)
        else { return bytes }

        var decoded = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return bytes }
            decoded.append(byte)
            index = next
        }
        return decoded
    }
}
