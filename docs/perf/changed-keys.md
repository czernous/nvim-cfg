# Changed keys (stage 2a)

| Key | Before | Now | Why |
|---|---|---|---|
| `<leader>f` | LSP format, else Neoformat; ran Spotless (~1 s) in Gradle projects | project formatter program (conform.nvim) if on `$PATH`, else the language server — always instant; Java uses the project's Eclipse formatter file | owner: Spotless via Gradle felt slow |
| `<leader>F` | — | exact Spotless (`./gradlew spotlessApply` result), Gradle projects that use it | exact result on demand |
| `K` | LSP hover (buffer-local); silent in files with no language server | one global key: LSP documentation, Vim's own lookup in help/man, otherwise a message saying no server is running | failed silently in Kotlin files |
| `<leader>pv` | built-in explorer | same key; explorer loads on first use | `nvim .` now shows the start screen |
