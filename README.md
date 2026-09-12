# PISCOU, COPIOU

## Instalação no Intel

**[Baixar para iMac Intel (.dmg)](https://github.com/x723235/piscou-copiou/releases/download/v0.1.0/Piscou-Copiou-Intel.dmg)**

Abra o DMG e arraste o app para Applications. Ou, com Homebrew instalado:

```sh
brew install --cask x723235/tap/piscou-copiou
```

Tap próprio: https://github.com/x723235/homebrew-tap

Baixe `Piscou-Copiou-Intel-macOS13.zip` na seção Releases, extraia e copie
`PISCOU, COPIOU.app` para Aplicativos. Requer macOS 13 Ventura ou superior.
Build local com assinatura ad hoc, sem notarização Apple. O Gatekeeper pode
bloquear a abertura; não desative as proteções do sistema.

Para compilar: `zsh scripts/build-intel.sh`.
O build Intel não comprova funcionamento em um iMac físico.

Limitações atuais: copia arquivos novos diretamente nas pastas selecionadas;
não é sincronização bidirecional. Arquivos existentes ao iniciar não são copiados.
A cópia do Photo Booth ainda precisa de validação ponta a ponta com mídia real;
a seleção de `Originals` por si só não comprova que todas as capturas ficam ali.

App nativo de barra de menus para macOS. A janela permite adicionar, ligar,
desligar e remover as pastas observadas. O Desktop vem ligado por padrão.

- `~/Desktop` — incluindo screenshots e gravações de tela novas;
- qualquer pasta escolhida em **Adicionar pasta…**, incluindo Photo Booth/Originals.

O Photo Booth deve apontar para `~/Pictures/Photo Booth Library/Originals`.
Os arquivos são copiados byte por byte com `FileManager.copyItem`, sem
recompressão ou conversão.

Os originais nunca são movidos nem apagados. Cada item novo é copiado para
`~/TRANSFER MAC M3 14`. Se já houver um arquivo com o mesmo nome, o app cria
uma cópia com sufixo numérico, sem sobrescrever nada.

Na primeira abertura, os arquivos que já existiam viram a linha de base. Só o
que aparecer depois é transferido automaticamente. O menu tem **Verificar
agora** para conferir novamente sem esperar o próximo ciclo de observação.

## Gerar o app

```sh
cd "/Users/rafael/Documents/Transfer Watcher"
zsh scripts/build-app.sh
open "build/PISCOU, COPIOU.app"
```

O app de desenvolvimento recebe assinatura local ad hoc. Ele não está
notarizado nem é uma distribuição pública.

## Rodar pelo código

```sh
cd "/Users/rafael/Documents/Transfer Watcher"
swift run
```

Para gerar o executável otimizado:

```sh
swift build -c release
```
