# SXML Posts with Lucid Rendering

## Goal

Allow blog posts to be written in SXML syntax (instead of Markdown), with YAML front matter for metadata, using Lucid to render SXML to HTML.

## File Format

Posts use `.sxml` extension under `posts/`, with the same YAML front matter as existing Markdown posts:

```sxml
---
title: My Post
author: Iris Lennon
date: 2026-06-03
---

(h1 "Hello, World")
(p "This is a paragraph with " (em "emphasis") ".")
```

The SXML body supports:
- Text nodes (quoted strings)
- Element nodes: `(tag-name content...)`
- Attributes: `(tag-name (@ (attr "val")) content...)`
- Nested elements: `(div (p "text") (p "more"))`
- Self-closing tags: `(br)`, `(img (@ (src "foo.png")))`

## Architecture

```
.sxml file
  │
  ▼
Lexer (tokenize s-expressions)
  │
  ▼
Parser (s-expr → SXML AST)
  │
  ▼
SXML → Lucid Html () converter
  │
  ▼
renderText (Lucid)
  │
  ▼
HTML Text → Hakyll Item
```

### Components (all in a single Haskell module)

1. **SXML Parser** — tokenizes and parses SXML text into an ADT
2. **Lucid Renderer** — converts the SXML AST to Lucid's `Html ()` type
3. **Hakyll Compiler** — a custom compiler that reads `.sxml` files, extracts YAML front matter, parses the body, renders to HTML, and applies templates

## Dependencies (to add to `blog.cabal`)

- `lucid` — HTML rendering
- `megaparsec` (optional, for parsing — or write a simple recursive descent parser)

Actually, a lightweight s-expression parser can be written without megaparsec. The SXML subset is small enough for a simple hand-written parser (≈100 lines). This avoids adding a parsing dependency.

## SXML → Lucid Mapping

| SXML | Lucid |
|------|-------|
| `(p "text")` | `p_ "text"` |
| `(div (p "a") (p "b"))` | `div_ (p_ "a" >> p_ "b")` |
| `(a (@ (href "url")) "link")` | `a_ [href_ "url"] "link"` |
| `(br)` | `br_` |
| `(img (@ (src "x.png")))` | `img_ [src_ "x.png"]` |
| `(p "hello " (em "world"))` | `p_ ("hello " >> em_ "world")` |

## Hakyll Integration

A new compiler function replaces `pandocCompiler` for `posts/*`:

```haskell
match "posts/*" $ do
    route $ setExtension "html"
    compile $ sxmlCompiler
        >>= loadAndApplyTemplate "templates/post.html"    postCtx
        >>= loadAndApplyTemplate "templates/default.html" postCtx
        >>= relativizeUrls
```

The `sxmlCompiler` reads the file, splits YAML front matter from SXML body, parses the body, renders via Lucid, and returns an `Item String` with the final HTML.

## Non-Goals

- Do not modify existing Markdown posts or other compilers
- Do not change templates
- Do not replace pandoc for non-post content (about.rst, contact.markdown)
- Do not add SXML support to the rest of the site
