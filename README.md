# V|D — App iOS (casca WebView + Face ID)

Embrulha o **V|D** web (https://neurovoice.com.br/ciclo/) numa casca nativa,
publicada no **TestFlight** via Codemagic (sem precisar de Mac).

Como é uma casca WebView, **toda atualização do site aparece no app automaticamente** —
só rebuilde se mudar algo nativo (ícone, permissões, versão, ponte do Face ID).

## Estrutura

```
ios_ciclo_app/                <- conecte ESTA pasta como raiz do repositório
├── codemagic.yaml            # pipeline: XcodeGen → assina → IPA → TestFlight
├── project.yml               # spec do XcodeGen (gera o .xcodeproj no Codemagic)
├── .gitignore
└── CicloApp/
    ├── CicloApp.swift         # @main; aponta para a URL do site
    ├── WebView.swift          # WKWebView + ponte JS↔nativo + pull-to-refresh
    ├── BiometriaManager.swift # Face ID: token do servidor no Keychain
    └── Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

## Como o Face ID funciona

Modelo do **Bolão** (token do servidor), não o do LocaCobrança (hash de senha):

| Passo | Quem chama | O quê |
|---|---|---|
| Ativar | site → `app.postMessage({msg:'salvarBio', bioToken})` | `auth.php?action=bio-enable` devolve um token; o Swift grava no Keychain com `.biometryCurrentSet` |
| Entrar | site → `app.postMessage({msg:'pedirFaceID'})` | Face ID libera o token → Swift chama `window.cicloBioLogin(token)` → `auth.php?action=bio-login` |
| Desativar | site → `app.postMessage({msg:'limparBio'})` | apaga o token do Keychain |

A **senha nunca toca o aparelho**. A sessão JWT dura 30 dias (`token_de()` em `db.php`) —
não reduza esse prazo, senão o Face ID passa a cair em 401 (foi exatamente o bug da
Live Activity do Bolão).

## Pré-requisitos (reaproveitando o que já existe)

- **App Store Connect:** criar app com bundle **`com.dprobaos.cicloadois`**
  (nome "V|D"). Categoria: Saúde e fitness.
- **Codemagic:**
  - Integração App Store Connect **"NeuroVoice ASC"** (a mesma dos outros apps).
  - Grupo de variáveis **`ios_signing`** com `CM_CERTIFICATE_PRIVATE_KEY`.
    ⚠️ O grupo é **por app** no Codemagic: se der `CM_CERTIFICATE_PRIVATE_KEY is not
    defined`, crie o grupo neste app reusando `bolao_ios_signing_key.pem`
    (script `add_var_locacao.mjs` serve de modelo).
  - Time de assinatura **`4P5D9V48GJ`** (já no `project.yml`).

## Passo a passo para o TestFlight

1. Suba `ios_ciclo_app/` num repositório Git (raiz = esta pasta) e dê push na **`main`**.
   ⚠️ **O iOS builda do Git remoto**: edição local só entra depois de commit + push.
2. Crie o app no App Store Connect com o bundle acima.
3. No Codemagic, conecte o repositório e confirme a integração e o grupo de variáveis.
4. Rode o workflow **"V|D iOS (TestFlight)"** (ou dê push na `main`).
5. O build sobe para o TestFlight (**teste interno** sai sem revisão). Para teste
   externo, preencha as "Test Information" e troque `submit_to_testflight: false → true`.

## Antes de submeter para revisão (checklist do playbook)

- [ ] **Excluir conta dentro do app** — já existe em Mais › Privacidade (5.1.1(v));
      grave o vídeo do fluxo e cite no campo *Notes* da submissão.
- [ ] **Testar a 1ª abertura em iPhone E iPad limpos** (crash na estreia = rejeição 2.1).
- [ ] **Privacidade / dados de saúde**: declarar no App Privacy que o app coleta dados de
      saúde e reprodução, vinculados à conta e **não usados para rastreamento**.
- [ ] **Sem menção a compra** dentro do app (não há assinatura neste app).
- [ ] `NSFaceIDUsageDescription` preenchido — já está no `project.yml`.
