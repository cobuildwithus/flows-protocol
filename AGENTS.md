# AGENTS.md — Nouns Flows

> Standard instructions for ChatGPT Codex agents and other automated contributors.
> **TL;DR**: run `pnpm run test`, keep code formatted, include a gas snapshot if it changes.

---

## Tests

```bash
run: pnpm run test        # alias for `forge test -vvv`
```

- Treat any non‑zero exit status as failure.
- Do **not** start watch mode (`pnpm run dev`) in CI environments.

### Optional suites

| Command                | Purpose                          | When to run                       |
| ---------------------- | -------------------------------- | --------------------------------- |
| `pnpm run test-gas`    | Generates gas report & snapshot  | Include in PR if Solidity changes |
| `pnpm run dev`         | Watch mode test loop             | Local development only            |
| `pnpm run build:sizes` | Compile and print contract sizes | Use before mainnet deploys        |

---

## Code style

1. **Formatter**

   - Check: `pnpm run prettier:check`
   - Fix  : `pnpm run prettier:write`

2. **Solidity**

   - Compiler `>=0.8.24 <0.9.0`
   - Use NatSpec on all public/external functions.
   - Avoid `var`; prefer explicit types.

---

## Pull‑request message template

```
📋 **Summary**
<1–2 concise sentences>

🚦 **Tests**
<attach or paste success output of `pnpm run test`>

🔗 **Context**
<optional links to issue / discussion>
```

---
