import Foundation
import Contacts

final class ContactsAgent: VoiceAgentPlugin {
    var intentTypes: [IntentType] { [.queryContact] }

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        let name = intent.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .simple("未指定联系人姓名", success: false)
        }

        let store = CNContactStore()

        let granted: Bool
        do {
            granted = try await store.requestAccess(for: .contacts)
        } catch {
            return .simple("联系人权限请求失败: \(error.localizedDescription)", success: false)
        }

        guard granted else {
            return .simple("未授权访问联系人。请在 系统设置 > 隐私与安全性 > 联系人 中允许 VoiceInput。", success: false)
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]

        let predicate = CNContact.predicateForContacts(matchingName: name)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            if contacts.isEmpty {
                return .simple("未找到联系人「\(name)」", success: false)
            }

            let contact = contacts[0]
            let fullName = "\(contact.familyName)\(contact.givenName)".trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = fullName.isEmpty ? name : fullName

            var lines: [String] = []
            for phone in contact.phoneNumbers {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: phone.label ?? "")
                lines.append("电话(\(label)): \(phone.value.stringValue)")
            }
            for email in contact.emailAddresses {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? "")
                lines.append("邮件(\(label)): \(email.value)")
            }
            if !contact.organizationName.isEmpty {
                lines.append("公司: \(contact.organizationName)")
            }

            if lines.isEmpty {
                return .simple("联系人「\(displayName)」无电话/邮件信息", success: false)
            }

            let body = lines.joined(separator: "\n")
            return AgentResponse(
                success: true,
                title: displayName,
                body: body,
                actions: [],
                contentType: .keyValue
            )
        } catch {
            return .simple("联系人查询失败: \(error.localizedDescription)", success: false)
        }
    }
}
