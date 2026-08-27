# Mermaid diagrams

## Sequence diagram

```mermaid
sequenceDiagram
    participant User
    participant Mirror
    participant Preview
    User->>Mirror: Edit Markdown
    Mirror->>Preview: Render diagram
    Preview-->>User: Show result
```

## Flowchart

```mermaid
flowchart LR
    A[Markdown source] --> B{Diagram block?}
    B -- Yes --> C[Mermaid renderer]
    B -- No --> D[Markdown renderer]
    C --> E[Live preview]
    D --> E
```
