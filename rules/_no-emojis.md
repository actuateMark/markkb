# No Emojis Rule Set

## 🚫 Prohibited Usage
- **No emojis before section headers** (e.g. 😄 # Section Title is invalid)
- **No markdown formatting** in plain text sections
- **No decorative emojis** in code blocks or examples
- **No redundant emojis** in bullet points (e.g. • 😊)
- **No emoji-based emphasis** (e.g. 😱 Important note instead of *Important note*)

## 📌 Exceptions
- Emojis allowed in:
  - Code examples (e.g. `😄 print("Hello")`)
  - Visual metaphors (e.g. 📁 for directories)
  - API response examples (e.g. 🚀 200 OK)

## 📝 Enforcement
- All markdown files must pass `markdownlint` with rules:
  - `no-multiple-space` (for emoji spacing)
  - `no-badgers` (prevents emoji-based emphasis)
  - `no-missed-space` (prevents emoji adjacency)

## 📚 Reference
- [Knowledgebase Rules](#knowledgebase-rules) (/_rules.md)
- [Workflow Checklist](#weekly-workflow-checklist) (/_workflow-checklist.md)

> This rule set ensures professional, consistent documentation without unnecessary visual clutter.