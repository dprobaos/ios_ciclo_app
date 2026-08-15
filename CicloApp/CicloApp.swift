//  CicloApp.swift — casca iOS do Ciclo a Dois (WebView + Face ID).
//  Target único (iOS 15+). Espelha o app web em produção, então toda
//  atualização do site aparece aqui sem precisar de novo build.

import SwiftUI

let SITE_URL = "https://neurovoice.com.br/ciclo/"

@main
struct CicloApp: App {
    var body: some Scene {
        WindowGroup {
            WebView(url: URL(string: SITE_URL)!)
                .ignoresSafeArea()
        }
    }
}
