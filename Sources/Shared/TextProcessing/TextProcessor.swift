import Foundation

/// TextProcessor handles AI text enhancement including:
/// - F6: Filler word removal
/// - F7: Duplicate word removal
/// - F8: Text formatting
class TextProcessor {

    // MARK: - Default Filler Words

    /// Default Chinese filler words
    static let defaultChineseFillers = [
        "嗯", "啊", "哦", "呀", "哎", "诶", "嗯嗯", "啊啊", "哦哦",
        "这个", "那个", "就是", "其实", "也就是说", "然后", "那么",
        "然后呢", "也就是说", "怎么说呢", "就是那个", "你知道吧",
        "那个啥", "就是吧", "差不多", "大概", "基本上"
    ]

    /// Default English filler words
    static let defaultEnglishFillers = [
        "um", "uh", "er", "ah", "like", "you know", "I mean", "basically",
        "actually", "literally", "so yeah", "you know what I mean"
    ]

    // MARK: - Properties

    /// Custom filler words added by user
    private var customFillers: Set<String> = []

    /// Enable/disable filler word removal
    var enableFillerWordRemoval = true

    /// Enable/disable duplicate word removal
    var enableDuplicateRemoval = true

    /// Enable/disable text formatting
    var enableFormatting = true

    // MARK: - Initialization

    init() {}

    // MARK: - F6: Filler Word Removal

    /// Remove filler words from text
    /// - Parameter text: Input text
    /// - Returns: Text with filler words removed
    func removeFillerWords(_ text: String) -> String {
        guard enableFillerWordRemoval else { return text }

        var result = text

        // Combine all filler words
        let allFillers = TextProcessor.defaultChineseFillers +
                        TextProcessor.defaultEnglishFillers +
                        Array(customFillers)

        // Sort by length (longest first) to handle multi-word fillers
        let sortedFillers = allFillers.sorted { $0.count > $1.count }

        for filler in sortedFillers {
            // Create pattern with word boundaries
            let escapedFiller = NSRegularExpression.escapedPattern(for: filler)
            let pattern = "\\b\(escapedFiller)\\b"

            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // Clean up extra spaces
        result = cleanExtraSpaces(result)

        return result
    }

    /// Add custom filler word
    func addCustomFiller(_ word: String) {
        customFillers.insert(word)
    }

    /// Remove custom filler word
    func removeCustomFiller(_ word: String) {
        customFillers.remove(word)
    }

    /// Get all custom filler words
    func getCustomFillers() -> [String] {
        return Array(customFillers)
    }

    // MARK: - F7: Duplicate Word Removal

    /// Remove consecutive duplicate words
    /// - Parameter text: Input text
    /// - Returns: Text with duplicate words removed
    func removeDuplicateWords(_ text: String) -> String {
        guard enableDuplicateRemoval else { return text }

        var result = text

        // Handle Chinese duplicates (e.g., "我我我" -> "我")
        if let chineseRegex = try? NSRegularExpression(pattern: "(.)\\1+", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = chineseRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }

        // Handle English duplicates (e.g., "the the" -> "the")
        if let englishRegex = try? NSRegularExpression(pattern: "\\b(\\w+)(?:\\s+\\1)+\\b", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = englishRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }

        // Clean up extra spaces
        result = cleanExtraSpaces(result)

        return result
    }

    // MARK: - F8: Formatting

    /// Format text with intelligent punctuation and spacing
    /// - Parameter text: Input text
    /// - Returns: Formatted text
    func formatText(_ text: String) -> String {
        guard enableFormatting else { return text }

        var result = text

        // Add space after English punctuation when followed by Chinese
        result = addSpacing(result)

        // Fix common punctuation issues
        result = fixPunctuation(result)

        // Handle list formats (第一、第二 -> 1. 2.)
        result = formatLists(result)

        return result
    }

    /// Add proper spacing between Chinese and English
    private func addSpacing(_ text: String) -> String {
        var result = text

        // Add space between Chinese and English
        // Chinese characters: \u{4E00}-\u{9FFF}
        // English: a-zA-Z

        if let regex = try? NSRegularExpression(pattern: "([\\u{4E00}-\\u{9FFF}])([a-zA-Z])", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }

        if let regex = try? NSRegularExpression(pattern: "([a-zA-Z])([\\u{4E00}-\\u{9FFF}])", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }

        return result
    }

    /// Fix common punctuation issues
    private func fixPunctuation(_ text: String) -> String {
        var result = text

        // Add space after English comma/period when followed by Chinese
        if let regex = try? NSRegularExpression(pattern: "([,.])([\\u{4E00}-\\u{9FFF}])", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }

        // Add space before English comma/period when preceded by Chinese
        if let regex = try? NSRegularExpression(pattern: "([\\u{4E00}-\\u{9FFF}])([,.]))", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }

        // Fix double punctuation
        if let regex = try? NSRegularExpression(pattern: "([,，;；:：!！?？])\\1+", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }

        return result
    }

    /// Format Chinese list markers
    private func formatLists(_ text: String) -> String {
        var result = text

        // First, second, third in Chinese
        let chineseNumbers = ["第一", "第二", "第三", "第四", "第五", "第六", "第七", "第八", "第九", "第十"]

        for (index, number) in chineseNumbers.enumerated() {
            let pattern = "\(number)[、，,]"
            let replacement = "\(index + 1). "
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }

        return result
    }

    // MARK: - Helper Methods

    /// Clean extra spaces in text
    private func cleanExtraSpaces(_ text: String) -> String {
        var result = text

        // Replace multiple spaces with single space
        if let regex = try? NSRegularExpression(pattern: " {2,}", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        // Trim leading and trailing spaces
        result = result.trimmingCharacters(in: .whitespaces)

        return result
    }

    // MARK: - Complete Processing Pipeline

    /// Process text through all enhancement steps
    /// - Parameter text: Input text from speech recognition
    /// - Returns: Fully processed and enhanced text
    func process(_ text: String) -> String {
        var result = text

        // Step 1: Remove filler words
        result = removeFillerWords(result)

        // Step 2: Remove duplicate words
        result = removeDuplicateWords(result)

        // Step 3: Format text
        result = formatText(result)

        // Final cleanup
        result = cleanExtraSpaces(result)

        return result
    }
}
