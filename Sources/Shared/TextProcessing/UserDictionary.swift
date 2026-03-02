import Foundation

/// UserDictionary manages personal vocabulary for custom word recognition
/// - F9: Personal dictionary with CRUD operations
class UserDictionary {

    // MARK: - Data Model

    /// Structure representing a user dictionary entry
    struct DictionaryEntry: Codable, Equatable {
        let word: String
        let createdAt: Date
        var usageCount: Int
        var tags: [String]

        init(word: String, tags: [String] = []) {
            self.word = word
            self.createdAt = Date()
            self.usageCount = 0
            self.tags = tags
        }
    }

    // MARK: - Storage Keys

    private let storageKey = "VoiceInput.UserDictionary"

    // MARK: - Properties

    /// Dictionary storage
    private var entries: [String: DictionaryEntry] = [:]

    /// UserDefaults for persistence
    private let userDefaults: UserDefaults

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromStorage()
    }

    // MARK: - CRUD Operations

    /// Add a new word to the dictionary
    /// - Parameters:
    ///   - word: The word to add
    ///   - tags: Optional tags for categorization
    func addWord(_ word: String, tags: [String] = []) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        // Check if word already exists
        if var existingEntry = entries[trimmedWord] {
            existingEntry.usageCount += 1
            entries[trimmedWord] = existingEntry
        } else {
            let entry = DictionaryEntry(word: trimmedWord, tags: tags)
            entries[trimmedWord] = entry
        }

        saveToStorage()
    }

    /// Remove a word from the dictionary
    /// - Parameter word: The word to remove
    func removeWord(_ word: String) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.removeValue(forKey: trimmedWord)
        saveToStorage()
    }

    /// Get all words in the dictionary
    /// - Returns: Array of all dictionary entries
    func getAllWords() -> [DictionaryEntry] {
        return Array(entries.values).sorted { $0.word < $1.word }
    }

    /// Get all words as simple strings
    /// - Returns: Array of words
    func getAllWordStrings() -> [String] {
        return getAllWords().map { $0.word }
    }

    /// Check if a word exists in the dictionary
    /// - Parameter word: The word to check
    /// - Returns: True if word exists
    func containsWord(_ word: String) -> Bool {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries[trimmedWord] != nil
    }

    /// Get a specific entry by word
    /// - Parameter word: The word to find
    /// - Returns: Dictionary entry if found
    func getEntry(_ word: String) -> DictionaryEntry? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries[trimmedWord]
    }

    // MARK: - Advanced Operations

    /// Update word tags
    /// - Parameters:
    ///   - word: The word to update
    ///   - tags: New tags
    func updateTags(for word: String, tags: [String]) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var entry = entries[trimmedWord] else { return }

        entry.tags = tags
        entries[trimmedWord] = entry
        saveToStorage()
    }

    /// Get words by tag
    /// - Parameter tag: Tag to filter by
    /// - Returns: Array of matching entries
    func getWordsByTag(_ tag: String) -> [DictionaryEntry] {
        return entries.values.filter { $0.tags.contains(tag) }
    }

    /// Get all unique tags
    /// - Returns: Array of unique tags
    func getAllTags() -> [String] {
        var tags = Set<String>()
        for entry in entries.values {
            tags.formUnion(entry.tags)
        }
        return Array(tags).sorted()
    }

    /// Search words by prefix
    /// - Parameter prefix: Prefix to search
    /// - Returns: Array of matching entries
    func searchByPrefix(_ prefix: String) -> [DictionaryEntry] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty else { return getAllWords() }

        return entries.values
            .filter { $0.word.hasPrefix(trimmedPrefix) }
            .sorted { $0.usageCount > $1.usageCount } // Sort by usage count
    }

    /// Get priority matched words (most used first)
    /// - Parameter text: Input text to match against
    /// - Returns: Array of matching entries sorted by priority
    func getPriorityMatches(for text: String) -> [DictionaryEntry] {
        return entries.values
            .filter { text.contains($0.word) }
            .sorted { $0.usageCount > $1.usageCount }
    }

    /// Increment usage count for a word
    /// - Parameter word: The word to update
    func incrementUsage(for word: String) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var entry = entries[trimmedWord] else { return }

        entry.usageCount += 1
        entries[trimmedWord] = entry
        saveToStorage()
    }

    /// Clear all entries
    func clearAll() {
        entries.removeAll()
        saveToStorage()
    }

    /// Get total word count
    var count: Int {
        return entries.count
    }

    // MARK: - Persistence

    /// Save dictionary to UserDefaults
    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(Array(entries.values))
            userDefaults.set(data, forKey: storageKey)
        } catch {
            print("UserDictionary: Failed to save - \(error)")
        }
    }

    /// Load dictionary from UserDefaults
    private func loadFromStorage() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }

        do {
            let loadedEntries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            entries = Dictionary(uniqueKeysWithValues: loadedEntries.map { ($0.word, $0) })
        } catch {
            print("UserDictionary: Failed to load - \(error)")
        }
    }
}
