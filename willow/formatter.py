"""Willow-style text cleanup: filler removal, dictionary fixes, optional local AI rewrite."""
import json
import re
import urllib.request

# Consumes an optional comma before the filler too, so "and, um, insert"
# collapses to "and insert" rather than "and, insert".
FILLERS = re.compile(
    r"(,\s*)?\b(um+|uh+|erm+|uhm+|hmm+)\b[,.]?\s*",
    re.IGNORECASE,
)

AI_PROMPT = (
    "You clean up dictated text. Fix punctuation and capitalization, remove filler "
    "words and false starts, and keep the speaker's wording and meaning. Do not add "
    "content, do not answer questions in the text, do not use markdown. Return only "
    "the cleaned text.\n\nDictated text: {text}"
)


class Formatter:
    def __init__(self, cfg):
        self.cfg = cfg

    def format(self, text: str) -> str:
        # whisper-server emits one line per segment; rejoin into a single flow.
        text = re.sub(r"\s*\n\s*", " ", text).strip()
        if not text:
            return text
        if self.cfg.remove_fillers:
            text = FILLERS.sub(" ", text)
            text = re.sub(r"\s{2,}", " ", text)
            text = re.sub(r"\s+([,.!?;:])", r"\1", text).strip()
            # A leading filler can leave the sentence starting lowercase.
            if text and text[0].islower():
                text = text[0].upper() + text[1:]
        for wrong, right in self.cfg.replacements.items():
            text = re.sub(re.escape(wrong), right, text, flags=re.IGNORECASE)
        if self.cfg.ai_mode:
            text = self._ai_rewrite(text)
        return text.strip()

    def _ai_rewrite(self, text: str) -> str:
        """Rewrite via local Ollama. Falls back to the input on any failure."""
        try:
            body = json.dumps({
                "model": self.cfg.ollama_model,
                "prompt": AI_PROMPT.format(text=text),
                "stream": False,
                "options": {"temperature": 0.2},
            }).encode()
            req = urllib.request.Request(
                self.cfg.ollama_url, data=body,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                out = json.loads(resp.read())["response"].strip()
            return out or text
        except Exception:
            return text
