# Book Brain

Um companheiro de leitura nativo para macOS: copie um trecho no Kindle e converse sobre ele com o Codex em uma janela flutuante.

## Usar

1. Abra **Book Brain** e escolha **Add book**. Informe o título e o autor. Se tiver um PDF, escolha **Attach PDF (optional)…** antes de confirmar. Para completar o autor em livros antigos, use **Books → Edit title and author…**. O aplicativo tenta conectar à sessão local do Codex.
2. Clique em **Enable Kindle capture…**. No macOS 27 em inglês, abra **System Settings → Privacy & Security → Device Control and Data Access** e ligue **Book Brain**. Em versões anteriores, o painel se chama **Accessibility / Acessibilidade**. Se o interruptor já estiver ligado e o app ainda pedir acesso, encerre o Book Brain com **⌘Q** e reabra a mesma cópia do aplicativo.
3. No Kindle, selecione um trecho e pressione **⌘⇧B**. O Book Brain aciona o comando Copiar no Kindle e abre a prévia da nova seleção. Se a cópia incluir a página ou posição do Kindle, o atalho preenche **Chapter or page**. Você pode editar o campo. Se o novo trecho vier sem referência reconhecível, o campo fica vazio. Para usar a cópia manual, escolha **Copy** no Kindle e **Paste passage** no Book Brain.
4. Escreva sua pergunta e envie com **Enter**. Use **Shift+Enter** para inserir uma nova linha na pergunta. Também dá para perguntar sobre a obra sem selecionar um trecho.
5. Continue perguntando no mesmo chat, inclusive ao trazer outro trecho. **New chat** abre um chat vazio e guarda o anterior. Clique no título da conversa no topo do painel para reabrir um chat do livro. O menu **…** permite renomear ou excluir a conversa da biblioteca local.
6. Use **Books** para alternar entre leituras. Cada livro lembra a conversa selecionada. Cada conversa guarda suas perguntas, respostas, referência, trecho em foco e rascunho.

No topo da janela, **Appearance** permite escolher **System**, **Light** ou **Dark**. A escolha fica salva neste Mac. A interface está em inglês e o Codex responde no idioma da pergunta.

O botão de alfinete mantém a janela acima do Kindle. Fechar a janela mantém o app na barra de menus; **⌘Q** encerra o aplicativo. O atalho só funciona enquanto o Book Brain está em execução. Se outro aplicativo já usa ⌘⇧B, um aviso orienta a usar o botão ou a barra de menus.

Arraste uma borda para ajustar a janela até **300 × 280 pontos** ou use o botão **Compact window**. No formato compacto, a pergunta e o envio ficam fixos, e o trecho pode ser expandido para edição. **Expand window** restaura o tamanho anterior no mesmo monitor.

## Requisitos e compilação

- macOS 14 ou superior; Swift 6 / Xcode 16 ou superior para compilar.
- Codex CLI com suporte aos perfis de permissões do app-server. Versão validada: **0.167.0-alpha.3.2**, incluída no ChatGPT instalado no Mac de desenvolvimento.
- Uma sessão autenticada do Codex. Se necessário, execute `codex login` antes de abrir o app.

```bash
./scripts/build-app.sh
open "build/Book Brain.app"
```

O build gera um `.app` com assinatura ad hoc para uso local, na arquitetura do Mac que compila. Não é uma distribuição notarizada ou universal. Na primeira compilação, o Swift Package Manager baixa o MarkdownUI e suas dependências para renderizar as respostas.

O app procura `codex` no PATH, no pacote do ChatGPT/Codex e nas instalações usuais do Homebrew. Se não o encontrar, use **Locate Codex executable…** no menu de conexão. A autenticação continua sendo gerenciada pelo Codex; o Book Brain não lê nem copia tokens. O uso segue a conta e os limites configurados no Codex.

## O que esta versão faz

- Janela flutuante, ícone na barra de menus e atalho global.
- Trecho editável, referência opcional de capítulo/página e sugestões de perguntas.
- Respostas em streaming, cancelamento e reconexão.
- Conversas salvas por livro, com o trecho exato associado a cada pergunta concluída. A primeira pergunta dá nome à conversa até você escolher outro título.
- Rascunhos preservados após erro ou cancelamento; respostas parciais não entram no histórico.
- Cada pergunta continua na sessão do chat selecionado. As memórias locais do Codex podem personalizar exemplos e explicações.

O Codex recebe o título e o autor em todas as perguntas. Pode usar o que conhece da obra e explicar o trecho selecionado. Para perguntas sobre um PDF anexado, consulta a cópia do livro e cita a página física do arquivo. Quando faltar informação confiável, a instrução é pesquisar na web e incluir links para as fontes consultadas.

## Dados e limites

- A captura direta usa a permissão de Acessibilidade para enviar ⌘C ao processo do Kindle que estava em primeiro plano ao pressionar **⌘⇧B**. Ela atualiza o clipboard como uma cópia manual. O app exige uma nova publicação após o comando e mostra o trecho antes do envio. Uma seleção sem permissão de cópia não é importada.
- O conteúdo do clipboard é lido ao acionar o atalho ou **Paste passage**. Na cópia manual, o contador de alterações registrado quando o Kindle ganhou foco permite detectar uma cópia antiga. A pergunta fica suspensa até você copiar, editar ou escolher continuar com o contexto anterior.
- Ao enviar, o Codex recebe o título, o autor, a referência, o trecho atual e a pergunta. Ele usa o contexto da sessão retomada e pode usar e gerar memórias locais.
- Limites por pergunta: **12.000 caracteres no trecho** e **4.000 na pergunta**. O histórico integral fica disponível no Book Brain. O Codex gerencia a janela de contexto da sessão.
- Livros, trechos, perguntas, respostas e rascunhos ficam em `~/Library/Application Support/BookBrain/library.json`. O arquivo é texto legível, com permissão `0600`, em uma pasta criada com `0700`. Não há criptografia própria nem sincronização.
- O PDF selecionado é copiado para `~/Library/Application Support/BookBrain/PDFs/` e fica disponível a todos os chats daquele livro, mesmo que o original mude de lugar. O Codex pode buscar palavras no texto e solicitar páginas individuais. Páginas digitalizadas podem ser consultadas como imagem pelo número da página. Cada consulta envia ao Codex os trechos ou a página solicitada. PDFs bloqueados ou com restrição de cópia são recusados.
- Arquivos inválidos não são substituídos por uma biblioteca vazia. O app mostra o erro e bloqueia edições para preservar o original.
- **Delete…** e **Delete current book…** removem os respectivos registros da biblioteca do Book Brain após confirmação. Excluir um livro também remove a cópia local de seu PDF. O Codex mantém seu próprio histórico e suas memórias no Mac.

## Integração com o Codex

Swift/Foundation inicia um processo `codex app-server` via stdin/stdout. O aplicativo usa `initialize`, `account/read`, `config/read`, `thread/start`, `thread/resume` e `turn/start`, recebendo eventos JSONL.

A primeira resposta associa o chat a uma sessão persistente do Codex. O Book Brain guarda o identificador e o retoma na próxima pergunta, inclusive depois de fechar o aplicativo. Cada resposta libera a assinatura da sessão quando termina. O Codex processa conversas elegíveis para memória em segundo plano.

Na atualização, o histórico anterior de cada livro vira sua primeira conversa, com todos os trechos, respostas e rascunhos. Como as versões antigas não guardavam um identificador comum de sessão, a primeira pergunta de continuação fornece até seis trocas antigas completas, limitadas a 24.000 caracteres. A partir dela, o Codex retoma a sessão do chat.

Os overrides valem somente para o processo filho. O app habilita o uso e a geração de memórias pelo Codex. As ferramentas dedicadas de memória, o shell, a execução de código, os plugins, os conectores, o navegador, a descoberta de skills e os servidores MCP herdados ficam desabilitados. O perfil `book-brain` permite apenas leitura de caminhos mínimos do runtime e de uma pasta temporária vazia, sem rede para execução local. A pesquisa na web é feita pelo serviço do Codex. O app atende apenas consultas de PDF da conversa e do turno ativos. Outros pedidos de ferramentas ou aprovações são recusados, e um evento de execução inesperado encerra a sessão. O processo do Codex ainda precisa acessar sua autenticação e a rede para inferência.

O Book Brain usa **GPT-6.1 Terra** (`gpt-6.1-terra`) com raciocínio **Extra High** (`xhigh`) e modo **Fast** (`priority`) em cada pergunta. A configuração é específica das conversas do aplicativo. A API de perfis de permissões é experimental: atualizações do Codex podem exigir ajustes. Falhas são exibidas; não há fallback para permissões mais amplas.

Referências: [Codex App Server](https://learn.chatgpt.com/docs/app-server), [perfis de permissões](https://learn.chatgpt.com/docs/permissions).

## Desenvolvimento e validação

```bash
# Testes locais sem rede, credenciais ou conteúdo real de livros
swift test

# Testes opcionais com a sessão do Codex, incluindo PDF sintético e pesquisa na web
BOOK_BRAIN_LIVE_TEST=1 swift test

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
