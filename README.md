# Book Brain

Um companheiro de leitura nativo para macOS: copie um trecho no Kindle e converse sobre ele com o Codex em uma janela flutuante.

## Usar

1. Abra **Book Brain** e adicione o título do livro. O aplicativo tenta conectar à sessão local do Codex.
2. No Kindle, selecione um trecho e clique em **Copiar** no menu da seleção ou use **⌘C**.
3. Pressione **⌘⇧B** para abrir o Book Brain e trazer o texto copiado. Você também pode clicar em **Colar trecho** ou colar diretamente no campo.
4. Confira o trecho, escreva sua pergunta e envie com **⌘Return**.
5. Use **Livros** para alternar entre leituras. Cada livro tem seu próprio trecho, rascunho e histórico.

O botão de alfinete mantém a janela acima do Kindle. Fechar a janela mantém o app na barra de menus; **⌘Q** encerra o aplicativo. O atalho só funciona enquanto o Book Brain está em execução. Se outro aplicativo já usa ⌘⇧B, um aviso orienta a usar o botão ou a barra de menus.

## Requisitos e compilação

- macOS 14 ou superior; Swift 6 / Xcode 16 ou superior para compilar.
- Codex CLI com suporte aos perfis de permissões do app-server. Versão validada: **0.167.0-alpha.3.2**, incluída no ChatGPT instalado no Mac de desenvolvimento.
- Uma sessão autenticada do Codex. Se necessário, execute `codex login` antes de abrir o app.

```bash
./scripts/build-app.sh
open "build/Book Brain.app"
```

O build gera um `.app` com assinatura ad hoc para uso local, na arquitetura do Mac que compila. Não é uma distribuição notarizada ou universal. Não é necessário instalar dependências Swift externas.

O app procura `codex` no PATH, no pacote do ChatGPT/Codex e nas instalações usuais do Homebrew. Se não o encontrar, use **Localizar executável do Codex…** no menu de conexão. A autenticação continua sendo gerenciada pelo Codex; o Book Brain não lê nem copia tokens. O uso segue a conta e os limites configurados no Codex.

## O que esta versão faz

- Janela flutuante, ícone na barra de menus e atalho global.
- Trecho editável, referência opcional de capítulo/página e sugestões de perguntas.
- Respostas em streaming, cancelamento e reconexão.
- Histórico por livro com o trecho exato associado a cada pergunta concluída.
- Rascunhos preservados após erro ou cancelamento; respostas parciais não entram no histórico.
- Contexto limitado ao livro selecionado: trecho atual, pergunta e até seis trocas recentes completas, dentro de um orçamento de 24.000 caracteres de histórico.

Não acessa o livro inteiro, não modifica o Kindle e não importa arquivos protegidos. OCR e importação de PDF/EPUB não fazem parte deste protótipo. A cópia depende do conteúdo e das restrições do Kindle; o app não contorna limites de cópia.

## Dados e limites

- O conteúdo do clipboard é lido ao acionar **⌘⇧B** ou **Colar trecho**. Quando o Kindle ganha foco, o app registra apenas o contador de alterações do clipboard. Ao importar, aguarda brevemente a conclusão da cópia. Se o contador continuar igual ao da entrada no Kindle ou ao da última importação, o app avisa e suspende o envio até você copiar, editar ou escolher continuar com o contexto anterior.
- Ao enviar uma pergunta, o título, referência, trecho atual, pergunta e histórico recente selecionado são enviados ao Codex para processamento pelo provedor configurado. O app mostra esse aviso junto ao campo de envio.
- Limites por pergunta: **12.000 caracteres no trecho** e **4.000 na pergunta**. Textos grandes são rejeitados, não cortados silenciosamente. O histórico mais antigo continua salvo no app, mas pode ficar fora do contexto enviado.
- Livros, trechos, perguntas, respostas e rascunhos ficam em `~/Library/Application Support/BookBrain/library.json`. O arquivo é texto legível, com permissão `0600`, em uma pasta criada com `0700`. Não há criptografia própria nem sincronização.
- Arquivos inválidos não são substituídos por uma biblioteca vazia. O app mostra o erro e bloqueia edições para preservar o original.
- **Excluir livro** remove seu registro local após confirmação. Não apaga dados do Kindle nem constitui uma solicitação de exclusão ao provedor de IA.

## Integração com o Codex

Swift/Foundation inicia um processo `codex app-server` via stdin/stdout. O aplicativo usa `initialize`, `account/read`, `model/list`, `config/read`, `thread/start` e `turn/start`, recebendo eventos JSONL. Não usa portas de rede locais e não automatiza a interface do Codex.

Cada pergunta cria uma sessão efêmera com o contexto delimitado pelo app; a sessão é descarregada ao concluir. O histórico persistente é o arquivo local do Book Brain. Sessões efêmeras não alteram as políticas de retenção do provedor.

Os overrides valem somente para o processo filho. O app desabilita shell, execução de código, plugins, conectores, navegador, memória e descoberta de skills; desabilita individualmente os servidores MCP herdados. O perfil `book-brain` permite apenas leitura de caminhos mínimos do runtime e de uma pasta temporária vazia, sem acesso de rede para ferramentas. Pedidos de aprovação/ferramentas são recusados, e um evento de execução inesperado encerra a sessão. O processo do Codex ainda precisa acessar sua autenticação e a rede para inferência.

O app usa o modelo padrão retornado pelo Codex, sem fixar um modelo na aplicação. A API de perfis de permissões é experimental: atualizações do Codex podem exigir ajustes. Falhas são exibidas; não há fallback para permissões mais amplas.

Referências: [Codex App Server](https://learn.chatgpt.com/docs/app-server), [perfis de permissões](https://learn.chatgpt.com/docs/permissions).

## Desenvolvimento e validação

```bash
# Testes locais sem rede, credenciais ou conteúdo real de livros
swift test

# Teste opcional de integração: usa a sessão do Codex e um trecho sintético curto
BOOK_BRAIN_LIVE_TEST=1 swift test --filter CodexClientTests/testLiveCodexWithSyntheticPassage

# Formatação
swift format format --in-place --recursive Sources Tests Package.swift
python3 -m black Tests/BookBrainCoreTests/Fixtures/fake-codex.py
```

Os testes verificam persistência, arquivo corrompido, limites de contexto, histórico por livro, fragmentação de UTF-8, eventos de outra conversa, streaming, falha do servidor, timeouts, reconexão, cancelamento e recusa de ferramentas. A integração real foi validada no macOS com Xcode 27. O workflow do GitHub executa a suíte sem rede e compila o `.app`.

O teste visual do Kindle e do atalho depende de uma sessão do macOS desbloqueada. Compilação e teste de inferência não comprovam que um livro específico permite copiar trechos.

## Estrutura

- `Sources/BookBrain`: SwiftUI, janela AppKit, barra de menus, atalho Carbon e estado da aplicação.
- `Sources/BookBrainCore`: persistência, construção do contexto e cliente do Codex.
- `Tests/BookBrainCoreTests`: testes e processo simulado do app-server.
- `scripts/build-app.sh`: compilação e empacotamento local.

Projeto pessoal, sem afiliação com Amazon ou OpenAI.
