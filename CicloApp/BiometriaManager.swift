//  BiometriaManager.swift — login por Face ID / Touch ID no V|D.
//
//  Modelo do Bolão (e NÃO o do LocaCobrança): o servidor emite um TOKEN
//  persistente (`auth.php?action=bio-enable`) e nós guardamos só esse token
//  no Keychain, protegido pela biometria (.biometryCurrentSet,
//  WhenUnlockedThisDeviceOnly). A senha do usuário nunca toca o aparelho.
//
//  Fluxo:
//    site → app("salvarBio", bioToken)  → grava no Keychain (pede Face ID)
//    site → app("pedirFaceID")          → Face ID libera o token →
//                                          chama window.cicloBioLogin(token)
//    site → app("limparBio")            → apaga o token local

import Foundation
import LocalAuthentication
import Security
import WebKit

final class BiometriaManager {
    static let shared = BiometriaManager()
    private init() {}

    private let service = "com.dprobaos.cicloadois.biometria"
    private let account = "bio_token"

    /// Hardware de biometria disponível e configurado.
    var disponivel: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// Já existe token guardado? (sem disparar o Face ID)
    var ativado: Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
            kSecReturnAttributes as String: true,
        ]
        let st = SecItemCopyMatching(q as CFDictionary, nil)
        return st == errSecSuccess || st == errSecInteractionNotAllowed
    }

    // ---- Ativar ----
    func ativar(token: String, _ done: @escaping (Bool) -> Void) {
        guard !token.isEmpty else { DispatchQueue.main.async { done(false) }; return }
        LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: "Confirme para ativar a entrada com Face ID") { ok, _ in
            guard ok else { DispatchQueue.main.async { done(false) }; return }
            let salvo = self.salvar(token: token)
            DispatchQueue.main.async { done(salvo) }
        }
    }

    // ---- Entrar ----
    func login(webView: WKWebView?) {
        guard ativado else { return }
        lerToken(motivo: "Entrar no V|D") { token in
            guard let token = token, let wv = webView else { return }
            let seguro = token.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("if(window.cicloBioLogin)window.cicloBioLogin('\(seguro)')",
                                  completionHandler: nil)
        }
    }

    // ---- Desativar ----
    func desativar() { apagar() }

    // ================= Keychain =================
    @discardableResult
    private func salvar(token: String) -> Bool {
        apagar()
        guard let acesso = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil),
              let dados = token.data(using: .utf8) else { return false }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: dados,
            kSecAttrAccessControl as String: acesso,
        ]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    func apagar() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }

    private func lerToken(motivo: String, _ done: @escaping (String?) -> Void) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseOperationPrompt as String: motivo,
            kSecReturnData as String: true,
        ]
        DispatchQueue.global(qos: .userInitiated).async {
            var item: CFTypeRef?
            let st = SecItemCopyMatching(q as CFDictionary, &item)
            let token = (st == errSecSuccess) ? (item as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
            DispatchQueue.main.async { done(token) }
        }
    }
}
