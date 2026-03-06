import Foundation
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseFirestore
#endif

struct FirestoreSyncSettings {
    let enabled: Bool
    let spaceID: String

    private static let enabledDefaultsKey = "WispMark.Sync.Enabled"
    private static let spaceIDDefaultsKey = "WispMark.Sync.SpaceID"

    private static let enabledInfoKey = "WispMarkFirestoreSyncEnabled"
    private static let spaceIDInfoKey = "WispMarkFirestoreSyncSpaceID"

    static func current() -> FirestoreSyncSettings {
        let defaults = UserDefaults.standard
        let info = Bundle.main.infoDictionary

        let infoEnabled = info?[enabledInfoKey] as? Bool ?? false
        let infoSpace = (info?[spaceIDInfoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let enabled = defaults.object(forKey: enabledDefaultsKey) as? Bool ?? infoEnabled
        let spaceID = (defaults.string(forKey: spaceIDDefaultsKey) ?? infoSpace)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return FirestoreSyncSettings(enabled: enabled, spaceID: spaceID)
    }

    static func persist(enabled: Bool, spaceID: String) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: enabledDefaultsKey)
        defaults.set(spaceID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: spaceIDDefaultsKey)
    }

    static func generateSpaceID() -> String {
        let first = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let second = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String((first + second).prefix(48))
    }
}

enum FirestoreRemoteChange {
    case upsert(Note)
    case delete(noteID: UUID, modifiedAt: Date)
}

final class FirestoreSyncManager {
    static let shared = FirestoreSyncManager()

    typealias NotesProvider = () -> [Note]
    private var notesProvider: NotesProvider?
    private var applyRemoteUpsert: ((Note) -> Void)?
    private var applyRemoteDelete: ((UUID, Date) -> Void)?

    private var hasBootstrappedLocalUpload = false
    private var started = false

    private let deviceIDDefaultsKey = "WispMark.Sync.DeviceID"
    private lazy var deviceID: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: deviceIDDefaultsKey), !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: deviceIDDefaultsKey)
        return newID
    }()

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
    private var notesCollection: CollectionReference?
    private var listener: ListenerRegistration?
#endif

    private init() {}

    var isRunning: Bool { started }

    var importedGoogleServiceInfoURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("WispMark", isDirectory: true)
            .appendingPathComponent("GoogleService-Info.plist")
    }

    var hasImportedGoogleServiceInfo: Bool {
        FileManager.default.fileExists(atPath: importedGoogleServiceInfoURL.path)
    }

    func importGoogleServiceInfo(from sourceURL: URL) throws {
        let fileManager = FileManager.default
        let destination = importedGoogleServiceInfoURL
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
    }

    func configurationSourceDescription() -> String {
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        switch firebaseConfigurationSource() {
        case .bundled:
            return "Bundled GoogleService-Info.plist"
        case .imported:
            return "Imported GoogleService-Info.plist"
        case .manual:
            return "Manual Firebase defaults"
        case .missing:
            return "Missing Firebase config"
        }
#else
        return "Firebase SDK not linked"
#endif
    }

    func statusDescription() -> String {
        let settings = FirestoreSyncSettings.current()
        if !settings.enabled {
            return "Sync is off"
        }
        if settings.spaceID.isEmpty {
            return "Add a Sync Space ID"
        }
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        if firebaseConfigurationSource() == .missing {
            return "Import GoogleService-Info.plist or add Firebase defaults"
        }
        if started {
            return "Sync running for space \(settings.spaceID)"
        }
        return "Sync ready for space \(settings.spaceID)"
#else
        return "Firebase SDK not linked"
#endif
    }

    func restartNoticeIfNeeded() -> String? {
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            return "Firebase project changes apply on next launch."
        }
#endif
        return nil
    }

    func start(
        notesProvider: @escaping NotesProvider,
        applyRemoteUpsert: @escaping (Note) -> Void,
        applyRemoteDelete: @escaping (UUID, Date) -> Void
    ) {
        guard !started else { return }

        let settings = FirestoreSyncSettings.current()
        guard settings.enabled else {
            NSLog("WispMark Sync: disabled (set WispMarkFirestoreSyncEnabled=true to enable)")
            return
        }

        guard !settings.spaceID.isEmpty else {
            NSLog("WispMark Sync: missing space ID (WispMarkFirestoreSyncSpaceID)")
            return
        }

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        guard configureFirebaseIfNeeded() else {
            NSLog("WispMark Sync: Firebase not configured. Add GoogleService-Info.plist or Info.plist Firebase keys.")
            return
        }

        self.notesProvider = notesProvider
        self.applyRemoteUpsert = applyRemoteUpsert
        self.applyRemoteDelete = applyRemoteDelete

        notesCollection = Firestore.firestore()
            .collection("syncSpaces")
            .document(settings.spaceID)
            .collection("notes")

        started = true
        attachListener()
        NSLog("WispMark Sync: started for space '%@'", settings.spaceID)
#else
        _ = notesProvider
        _ = applyRemoteUpsert
        _ = applyRemoteDelete
        NSLog("WispMark Sync: Firebase SDK not linked in this build")
#endif
    }

    func stop() {
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        listener?.remove()
        listener = nil
#endif
        started = false
        hasBootstrappedLocalUpload = false
        notesProvider = nil
        applyRemoteUpsert = nil
        applyRemoteDelete = nil
    }

    func upsertLocalNote(_ note: Note) {
        guard started else { return }
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        guard let notesCollection else { return }

        let payload: [String: Any] = [
            "content": note.content,
            "createdAt": note.createdAt,
            "modifiedAt": note.modifiedAt,
            "isPinned": note.isPinned,
            "workspaces": Array(note.workspaces).sorted(),
            "tags": Array(note.tags).sorted(),
            "deleted": false,
            "updatedBy": deviceID,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        notesCollection.document(note.id.uuidString).setData(payload, merge: true) { error in
            if let error {
                NSLog("WispMark Sync: failed to upsert note %@: %@", note.id.uuidString, error.localizedDescription)
            }
        }
#else
        _ = note
#endif
    }

    func markLocalDeletion(noteID: UUID, modifiedAt: Date = Date()) {
        guard started else { return }
#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
        guard let notesCollection else { return }

        let payload: [String: Any] = [
            "deleted": true,
            "modifiedAt": modifiedAt,
            "updatedBy": deviceID,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        notesCollection.document(noteID.uuidString).setData(payload, merge: true) { error in
            if let error {
                NSLog("WispMark Sync: failed to mark delete %@: %@", noteID.uuidString, error.localizedDescription)
            }
        }
#else
        _ = noteID
        _ = modifiedAt
#endif
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseFirestore)
private extension FirestoreSyncManager {
    enum FirebaseConfigurationSource {
        case bundled
        case imported
        case manual
        case missing
    }

    struct RemoteState {
        let modifiedAt: Date
        let deleted: Bool
    }

    func configureFirebaseIfNeeded() -> Bool {
        if FirebaseApp.app() != nil {
            return true
        }

        if let bundlePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: bundlePath) {
            FirebaseApp.configure(options: options)
            return true
        }

        if let options = FirebaseOptions(contentsOfFile: importedGoogleServiceInfoURL.path) {
            FirebaseApp.configure(options: options)
            return true
        }

        guard let options = firebaseOptionsFromInfoPlist() else {
            return false
        }

        FirebaseApp.configure(options: options)
        return true
    }

    func firebaseOptionsFromInfoPlist() -> FirebaseOptions? {
        guard let info = Bundle.main.infoDictionary else { return nil }
        let defaults = UserDefaults.standard

        let appID = (
            defaults.string(forKey: "WispMark.Sync.FirebaseAppID")
            ?? (info["WispMarkFirebaseAppID"] as? String)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let senderID = (
            defaults.string(forKey: "WispMark.Sync.FirebaseSenderID")
            ?? (info["WispMarkFirebaseSenderID"] as? String)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let apiKey = (
            defaults.string(forKey: "WispMark.Sync.FirebaseAPIKey")
            ?? (info["WispMarkFirebaseAPIKey"] as? String)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let projectID = (
            defaults.string(forKey: "WispMark.Sync.FirebaseProjectID")
            ?? (info["WispMarkFirebaseProjectID"] as? String)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !appID.isEmpty, !senderID.isEmpty, !apiKey.isEmpty, !projectID.isEmpty else {
            return nil
        }

        let options = FirebaseOptions(googleAppID: appID, gcmSenderID: senderID)
        options.apiKey = apiKey
        options.projectID = projectID

        let storageBucket = (
            defaults.string(forKey: "WispMark.Sync.FirebaseStorageBucket")
            ?? (info["WispMarkFirebaseStorageBucket"] as? String)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !storageBucket.isEmpty {
            options.storageBucket = storageBucket
        }

        return options
    }

    func firebaseConfigurationSource() -> FirebaseConfigurationSource {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            return .bundled
        }
        if FileManager.default.fileExists(atPath: importedGoogleServiceInfoURL.path) {
            return .imported
        }
        if firebaseOptionsFromInfoPlist() != nil {
            return .manual
        }
        return .missing
    }

    func attachListener() {
        guard let notesCollection else { return }

        listener = notesCollection.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                NSLog("WispMark Sync: listener error: %@", error.localizedDescription)
                return
            }

            guard let snapshot else { return }

            let remoteChanges = snapshot.documents.compactMap { self.decodeRemoteChange(from: $0) }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyRemoteChanges(remoteChanges)
                self.bootstrapLocalUploadIfNeeded(remoteChanges: remoteChanges)
            }
        }
    }

    func decodeRemoteChange(from doc: QueryDocumentSnapshot) -> FirestoreRemoteChange? {
        guard let noteID = UUID(uuidString: doc.documentID) else { return nil }
        let data = doc.data()

        let deleted = data["deleted"] as? Bool ?? false
        let modifiedAt = dateValue(from: data["modifiedAt"]) ?? Date.distantPast

        if deleted {
            return .delete(noteID: noteID, modifiedAt: modifiedAt)
        }

        guard let content = data["content"] as? String else {
            return nil
        }

        let createdAt = dateValue(from: data["createdAt"]) ?? modifiedAt
        let isPinned = data["isPinned"] as? Bool ?? false
        let workspaces = Set(data["workspaces"] as? [String] ?? [])
        let tags = Set(data["tags"] as? [String] ?? [])

        let note = Note(
            id: noteID,
            content: content,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isPinned: isPinned,
            workspaces: workspaces,
            tags: tags
        )

        return .upsert(note)
    }

    func dateValue(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        if let epochSeconds = value as? TimeInterval {
            return Date(timeIntervalSince1970: epochSeconds)
        }
        if let intSeconds = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(intSeconds))
        }
        return nil
    }

    func applyRemoteChanges(_ changes: [FirestoreRemoteChange]) {
        guard !changes.isEmpty else { return }

        let ordered = changes.sorted { lhs, rhs in
            let leftDate: Date
            let rightDate: Date

            switch lhs {
            case .upsert(let note):
                leftDate = note.modifiedAt
            case .delete(_, let modifiedAt):
                leftDate = modifiedAt
            }

            switch rhs {
            case .upsert(let note):
                rightDate = note.modifiedAt
            case .delete(_, let modifiedAt):
                rightDate = modifiedAt
            }

            return leftDate < rightDate
        }

        for change in ordered {
            switch change {
            case .upsert(let note):
                applyRemoteUpsert?(note)
            case .delete(let noteID, let modifiedAt):
                applyRemoteDelete?(noteID, modifiedAt)
            }
        }
    }

    func bootstrapLocalUploadIfNeeded(remoteChanges: [FirestoreRemoteChange]) {
        guard !hasBootstrappedLocalUpload else { return }
        guard let notesProvider else { return }

        var remoteState: [UUID: RemoteState] = [:]
        for change in remoteChanges {
            switch change {
            case .upsert(let note):
                remoteState[note.id] = RemoteState(modifiedAt: note.modifiedAt, deleted: false)
            case .delete(let noteID, let modifiedAt):
                remoteState[noteID] = RemoteState(modifiedAt: modifiedAt, deleted: true)
            }
        }

        let localNotes = notesProvider()
        for note in localNotes {
            if let remote = remoteState[note.id] {
                if remote.deleted || note.modifiedAt > remote.modifiedAt {
                    upsertLocalNote(note)
                }
            } else {
                upsertLocalNote(note)
            }
        }

        hasBootstrappedLocalUpload = true
    }
}
#endif
