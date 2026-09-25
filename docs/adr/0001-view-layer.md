# ADR 0001 — Camada de view: Lustre nativo vs templates HTML em runtime

- **Status:** Proposed
- **Data:** 2026-09-25
- **Decisor:** puppe1990
- **Relacionado:** #2 (esta decisão), #3 (kit), #4 (Drive/Frame), #17 (i18n/meta)
- **Referência externa:** amarra-cais `AGENTS.md` → "Template loader contract", "Amarra Views + Drive"

---

## Contexto

O `mastro` nasce como um fork do `refrakt` (convenções + geradores sobre
`wisp`/`mist`/`lustre`) para carregar o contrato **HTML-first** do
`amarra-cais`: Amarra Views + kit (`<.form>`, `<.input>`, …), **Drive**,
**Frame**, **Stream** e **Live**.

No `amarra-cais` (Go), esse contrato é implementado com `html/template`:
`view.Load` faz glob de `web/templates/` **no boot**, resolve
`layouts/*`, `pages/*` (com um nível de aninhamento), `partials/*`
(plano) e `components/*` (override do kit pelo stem do arquivo).
Componente desconhecido falha no boot.

O `refrakt`, por outro lado, renderiza HTML como **funções Lustre tipadas**
(`Element(Nil)`), sem templates em runtime, sem tag de componente e sem
override por arquivo.

Esse é um conflito direto com uma regra já escrita em
`.claude/rules/architecture.md`:

> **If Wisp or Lustre already does it, don't rebuild it.**
> Tabela: "HTML rendering | Lustre".

## Forças em jogo

| Força | Puxa para… |
| --- | --- |
| Fidelidade ao contrato Amarra (`<.component>`, override em HTML) | engine de templates em runtime |
| Regra do repo ("não reconstruir o Lustre") | Lustre nativo |
| Tipagem / falha em tempo de compilação (Gleam) | Lustre nativo |
| Restilizar a kit sem recompilar (designer edita HTML) | engine de templates |
| Esforço de construção e superfície de manutenção | Lustre nativo |
| Segurança de escaping | ambos (Lustre escapa por padrão) |

## Opções

### A. Lustre nativo (recomendado)

Lustre é o único renderer. O "contrato Amarra" é reinterpretado como
**biblioteca de componentes Gleam + registro de override**, e Drive/Frame/
Stream/Live são implementados como camada de transporte sobre `wisp`/`mist`.

- Layout nomeado → função de layout registrada por nome.
- Página com aninhamento → módulo de view por pasta (`web/views/blog/post.gleam`).
- Partial flat → módulo de componente.
- Override do kit → entrada no registro sobrescreve o componente shipped (por stem).
- Componente desconhecido → **erro de compilação** (mais forte que falha no boot);
  um registro em runtime valida entradas no boot para overrides dinâmicos.

Prós: idiomático, tipado, baixo esforço, alinhado à regra do repo, sem
superfície de parser/segurança nova. Contras: perde o `<.input>` em HTML e
a restilização sem recompilar.

### B. Engine de templates HTML em runtime (Go-template-like)

Implementar lexer/parser/avaliador para `{{ .X }}`, `{{ if }}`, `{{ range }}`,
`{{ define }}`/`{{ template }}`, um mapa de funções fixo, auto-escaping, e
expansão de `<.componente/>` com kit shipped + override por arquivo.

Prós: fidelidade máxima ao Amarra; designer restiliza a kit em HTML sem
recompilar. Contras: reimplementa um `html/template`; a tipagem do Gleam não
alcança os templates; escaping vira responsabilidade de segurança crítica;
esforço alto e manutenção contínua; contraria a regra do repo.

### C. Híbrido

Lustre para páginas/ilhas e um mini-motor apenas para componentes de kit
em HTML. Prós: meio-termo. Contras: dois modelos mentais, duas superfícies
de escaping, API inconsistente para o usuário.

## Decisão proposta

**Opção A.** Manter o Lustre como renderer único e entregar o contrato
observável (Drive, Frame, Stream, Live, kit, CSRF, flash) como bibliotecas
e middleware sobre `wisp`/`mist`. O `<.component>` HTML é substituído por
componentes Gleam em `mastro/kit` com registro de override.

Racional: preserva a regra "não reconstruir o Lustre", elimina uma classe
inteira de bugs de parsing/escaping e mantém a promessa do Gleam de
falhar na compilação. O que se perde (restilizar a kit editando HTML sem
recompilar) é aceitável num framework cujo público escreve Gleam.

> Se a restilização em HTML sem recompilar for requisito **duro**, a decisão
> muda para **B** e o cronograma de #3/#4 cresce de forma relevante.

## Consequências

- **#3 (kit)** é rescopada: componentes viram módulos `mastro/kit/*` +
  registro; override do app = registro sobrescreve o shipped. O critério
  "override por file stem HTML" vira "override por stem no registro".
- **#4 (Drive/Frame)** não muda: é protocolo de transporte (`Amarra-Drive`,
  `Amarra-Frame`, morph de `#amarra-main`), independente do renderer.
- **#5, #6, #7 (amarra.js/Stream/Live)** não mudam.
- **#17 (i18n/meta)** não muda.
- A kit deixa de ser "shipped markup" e passa a ser "shipped módulos".

## PoC (fecha #2)

Demonstrar, com testes headless:

1. layout nomeado (`app`, `landing`) selecionável por nome;
2. view de página com um nível de aninhamento (`blog/post`);
3. partial/componente flat reutilizável;
4. override do kit pelo app (stem `input` sobrepõe o shipped);
5. componente desconhecido tratado no boot/registro (erro cedo, não no request).

## Segurança

Em A, o escaping é o default do Lustre (`text`/`attribute`); HTML cru exige
API explícita (ex. `element.unsafe_raw`). Em B, auto-escaping e regras de
`unsafe` teriam que ser especificados e testados como superfície de segurança.

## Referências

- amarra-cais `AGENTS.md` (contrato de loader, kit, Drive).
- `.claude/rules/architecture.md` (Lustre owns HTML; não reconstruir).
- `docs/views.md` (como as views funcionam hoje).
