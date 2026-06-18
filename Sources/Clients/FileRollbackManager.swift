import Foundation

public class FileRollbackManager {
    public static let shared = FileRollbackManager()
    
    private let backupDirectory: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.backupDirectory = appSupport.appendingPathComponent("OpenCowork/Backups")
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }
    
    public func backupFile(atPath path: String, sessionID: UUID) -> FileBackup? {
        let fileManager = FileManager.default
        let fileURL = URL(fileURLWithPath: path)
        let isNew = !fileManager.fileExists(atPath: path)
        
        let sessionBackupDir = backupDirectory.appendingPathComponent(sessionID.uuidString)
        try? fileManager.createDirectory(at: sessionBackupDir, withIntermediateDirectories: true)
        
        let backupFileURL = sessionBackupDir.appendingPathComponent(UUID().uuidString)
        
        if !isNew {
            do {
                try fileManager.copyItem(at: fileURL, to: backupFileURL)
            } catch {
                print("Failed to backup file: \(error)")
                return nil
            }
        }
        
        return FileBackup(filePath: path, backupPath: backupFileURL.path, isNewFile: isNew)
    }
    
    public func rollback(backups: [FileBackup]) {
        let fileManager = FileManager.default
        for backup in backups {
            let fileURL = URL(fileURLWithPath: backup.filePath)
            let backupURL = URL(fileURLWithPath: backup.backupPath)
            
            if backup.isNewFile {
                // It was a new file, delete it
                try? fileManager.removeItem(at: fileURL)
            } else {
                // Restore backup
                if fileManager.fileExists(atPath: backup.filePath) {
                    try? fileManager.removeItem(at: fileURL)
                }
                try? fileManager.copyItem(at: backupURL, to: fileURL)
            }
        }
    }
}
