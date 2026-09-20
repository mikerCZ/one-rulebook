# Global instructions

Codex loads its global instructions from `~/.codex/AGENTS.md`, not from this file — measured
5.9.2026 with `codex debug prompt-input` from three working directories, where a marker added
here never reached the model and a marker in `~/.codex/AGENTS.md` always did.

This stub exists so the importer does not recreate a full, path-rewritten copy in its place.
Edit `~/.codex/AGENTS.codex.md` or `~/.claude/CLAUDE.md` instead.
