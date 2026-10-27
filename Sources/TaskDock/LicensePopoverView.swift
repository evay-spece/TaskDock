import AppKit
import SwiftUI

@MainActor
struct LicensePopoverView: View {
    @ObservedObject var license: LicenseService
    @State private var code = ""
    @State private var email = ""
    @State private var confirmedEmail = ""
    @State private var requestCopied = false
    @State private var activationFeedback: LicenseActivationResult?
    @State private var showsActivationAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("TaskDock 授权").font(.headline)
                Text(license.hasPermanentTrial ? "永久试用已开启" : "7 天完整试用 · ¥59 一次购买授权")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("接收激活码的邮箱", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: email) { _ in
                        confirmedEmail = ""
                        requestCopied = false
                        license.clearPaymentSelection()
                    }
                Text("邮箱仅保存于本机。付款后需要你主动发送申请，客服才能收到。")
                    .font(.caption).foregroundStyle(.secondary)
                if confirmedEmail.isEmpty {
                    Button("确认接收邮箱") {
                        confirmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .disabled(!isValidEmail(email))
                } else {
                    Text("已确认邮箱：\(confirmedEmail)")
                        .font(.caption).textSelection(.enabled)
                }
                HStack {
                    Button("支付宝扫码") { requestCopied = false; license.beginPurchase(provider: "alipay", email: confirmedEmail) }
                    Button("微信扫码") { requestCopied = false; license.beginPurchase(provider: "wechat", email: confirmedEmail) }
                }
                .disabled(confirmedEmail.isEmpty)
                if let qrCode = license.paymentQRCode {
                    Image(nsImage: qrCode).resizable().interpolation(.high)
                        .scaledToFit()
                        .frame(width: 310, height: 310 * qrCode.size.height / max(qrCode.size.width, 1))
                        .frame(maxWidth: .infinity)
                    Button("打开原图放大") { license.openPaymentQRCode() }
                    Text("¥59 · 请核对手机付款页的收款方")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("本机申请码：\(license.deviceID)")
                        .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button("打开申请邮件") { license.openPurchaseRequestDraft() }
                        Button(requestCopied ? "已复制申请信息" : "复制申请信息") {
                            NSPasteboard.general.clearContents()
                            requestCopied = NSPasteboard.general.setString(license.purchaseRequest, forType: .string)
                        }
                    }
                    .disabled(!license.canPreparePurchaseRequest)
                    Text("打开草稿不等于发送。请在邮箱中补充付款时间和流水号后发送；也可复制信息到网页邮箱发送。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("客服邮箱：\(license.supportEmail)")
                        .font(.caption).textSelection(.enabled)
                }
                Text("每笔付款最多人工签发 3 个不同本机申请码。换机或重置钥匙串请联系客服处理。")
                    .font(.caption).foregroundStyle(.secondary)
                if !license.message.isEmpty {
                    Text(license.message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("粘贴购买授权长码或内测试用码").font(.caption)
                TextEditor(text: $code).font(.system(.caption, design: .monospaced))
                    .frame(height: 70).border(Color.secondary.opacity(0.3))
                Text("购买授权长码可永久离线使用；内测码每个增加 7 天试用，同一码在本机只能兑换一次。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("验证并激活") {
                    activationFeedback = license.activate(code: code)
                    showsActivationAlert = true
                }
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let feedback = activationFeedback {
                    Label(feedback.message, systemImage: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(feedback.isSuccess ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !license.activatedLicenseCode.isEmpty {
                    Button("复制已保存的激活码") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(license.activatedLicenseCode, forType: .string)
                    }
                }
            }.padding(16)
        }
        .frame(width: 350, height: 580)
        .alert(activationFeedback?.title ?? "激活结果", isPresented: $showsActivationAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(activationFeedback?.message ?? "")
        }
        .onChange(of: code) { _ in activationFeedback = nil }
        .onAppear { if email.isEmpty { email = license.pendingBuyerEmail } }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.range(of: "^[^\\s@,;<>]+@[^\\s@,;<>]+\\.[^\\s@,;<>]+$", options: .regularExpression) != nil
    }
}
