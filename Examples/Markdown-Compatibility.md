---
title: Markdown compatibility
tags: [mori, markdown]
---

# Markdown compatibility

Mori supports common Markdown and GFM writing patterns, safe HTML, tables, task lists, code highlighting, footnotes, offline diagrams, and offline mathematics.

Setext heading
--------------

Inline math uses KaTeX syntax: $E = mc^2$.

Block mathematics:

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

Footnotes can contain continued text.[^notes]

> [!TIP]
> GitHub-style alerts are rendered with theme-aware colors.

[^notes]: The first line of a footnote.
    Indented continuation lines are included in the same note.

~~~mermaid
flowchart LR
    Source --> Preview
    Preview --> HTML
    Preview --> PDF
~~~

~~Strikethrough~~, **bold**, _italic_, `inline code`, ``code containing a ` backtick``, and [**formatted** links](https://example.com) work together.

[Reference links][guide], [collapsed references][], and shortcut-style [Mori] references are supported throughout the document, including inside quotes and lists.

[guide]: <docs/Guide File.md> "Local guide"
[collapsed references]: https://spec.commonmark.org/
[mori]: https://github.com/

- Unordered parent
  1. Ordered child
     - [x] Nested task
     - [ ] Another nested task
- Sibling item
