import Foundation
import Contacts
import AppKit

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
            var firstPhone: String?
            for phone in contact.phoneNumbers {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: phone.label ?? "")
                let number = phone.value.stringValue
                firstPhone = firstPhone ?? number
                lines.append("电话(\(label)): \(number)")
            }
            var firstEmail: String?
            for email in contact.emailAddresses {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? "")
                let address = String(email.value)
                firstEmail = firstEmail ?? address
                lines.append("邮件(\(label)): \(address)")
            }
            if !contact.organizationName.isEmpty {
                lines.append("公司: \(contact.organizationName)")
            }

            if lines.isEmpty {
                return .simple("联系人「\(displayName)」无电话/邮件信息", success: false)
            }

            let body = lines.joined(separator: "\n")
            var actions: [AgentAction] = []
            if let firstPhone {
                actions.append(AgentAction(label: "复制电话", systemImage: "phone") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(firstPhone, forType: .string)
                })
            } else if let firstEmail {
                actions.append(AgentAction(label: "复制邮箱", systemImage: "envelope") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(firstEmail, forType: .string)
                })
            }
            actions.append(AgentAction(label: "打开通讯录", systemImage: "person.crop.circle") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Contacts.app"))
            })
            return AgentResponse(
                success: true,
                title: displayName,
                body: body,
                actions: actions,
                contentType: .keyValue
            )
        } catch {
            return .simple("联系人查询失败: \(error.localizedDescription)", success: false)
        }
    }
}
