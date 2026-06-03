# SXML Posts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) for syntax tracking.

**Goal:** Add support for writing blog posts in SXML format, rendered to HTML via Lucid.

**Architecture:** A custom lexer+parser converts SXML text into an intermediate ADT, which Lucid renders to HTML. A custom Hakyll compiler replaces `pandocCompiler` for `.sxml` files, keeping YAML front matter for metadata.

**Tech Stack:** Hakyll, Lucid, custom s-expression parser

---

### Task 1: Add `lucid` dependency and `src/` to build

**Files:**
- Modify: `blog.cabal`

- [ ] **Edit `blog.cabal`**

Change the `executable site` section:

From:
```
executable site
  main-is:          site.hs
  build-depends:    base == 4.*
                  , hakyll == 4.16.*
                  , time
                  , process
                  , filepath
                  , temporary
                  , text
                  , directory
                  , pandoc
                  , pandoc-sidenote
  ghc-options:      -threaded -rtsopts -with-rtsopts=-N
  default-language: Haskell2010
```

To:
```
executable site
  main-is:          site.hs
  hs-source-dirs:   ., src
  build-depends:    base == 4.*
                  , hakyll == 4.16.*
                  , time
                  , process
                  , filepath
                  , temporary
                  , text
                  , directory
                  , pandoc
                  , pandoc-sidenote
                  , lucid
  ghc-options:      -threaded -rtsopts -with-rtsopts=-N
  default-language: Haskell2010
  other-modules:    SXML
```

- [ ] **Build test**

Run:
```bash
cabal build 2>&1 | tail -20
```

Expected: fails with "Module `SXML' does not exist" — that's fine, the dep resolution should succeed.

---

### Task 2: Create `src/SXML.hs`

**Files:**
- Create: `src/SXML.hs`

- [ ] **Write the SXML module**

Create `src/SXML.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module SXML (sxmlToHtml) where

import Data.Text (Text)
import qualified Data.Text as T
import Lucid (Html (), Attribute, makeAttribute, makeElement, renderText, toHtml)

import Prelude

--------------------------------------------------------------------------------
-- Lexer
--------------------------------------------------------------------------------

data Token = LParen | RParen | AtSign | Symbol Text | Str Text
    deriving (Show, Eq)

tokenize :: Text -> Either Text [Token]
tokenize = go . T.strip
  where
    go t
        | T.null t = Right []
        | T.head t == '('  = (LParen :) <$> go (T.strip (T.tail t))
        | T.head t == ')'  = (RParen :) <$> go (T.strip (T.tail t))
        | T.head t == '@'  = (AtSign :) <$> go (T.strip (T.tail t))
        | T.head t == '"'  =
            case T.break (== '"') (T.tail t) of
                (str, rest)
                    | T.null rest -> Left "Unterminated string literal"
                    | otherwise   -> (Str str :) <$> go (T.strip (T.drop 1 rest))
        | T.head t == ';'  = go (T.strip (T.dropWhile (/= '\n') t))
        | otherwise =
            let (sym, rest) = T.break (\c -> c `elem` "()\"@; \t\n\r") t
            in if T.null sym
               then go (T.strip rest)
               else (Symbol sym :) <$> go (T.strip rest)

--------------------------------------------------------------------------------
-- S-expression parser
--------------------------------------------------------------------------------

data SExpr = SSymbol Text | SString Text | SList [SExpr]
    deriving (Show, Eq)

parseSExprs :: [Token] -> Either Text ([SExpr], [Token])
parseSExprs [] = Right ([], [])
parseSExprs (RParen : rest) = Right ([], RParen : rest)
parseSExprs tokens = case parseOne tokens of
    Right (expr, rest)  -> case parseSExprs rest of
        Right (exprs, rest') -> Right (expr : exprs, rest')
        err                  -> err
    Left err             -> Left err

parseOne :: [Token] -> Either Text (SExpr, [Token])
parseOne (Str t    : rest) = Right (SString t, rest)
parseOne (Symbol t : rest) = Right (SSymbol t, rest)
parseOne (LParen   : rest) = case parseSExprs rest of
    Right (elems, RParen : rest'') -> Right (SList elems, rest'')
    Right (_,       _)             -> Left "Expected ')'"
    Left err                       -> Left err
parseOne (AtSign : _)    = Left "Unexpected '@' outside element"
parseOne (RParen : _)    = Left "Unexpected ')'"
parseOne []              = Left "Unexpected end of input"

--------------------------------------------------------------------------------
-- SXML AST and conversion
--------------------------------------------------------------------------------

data SXML = TextNode Text | Element Text [(Text, Text)] [SXML]
    deriving (Show, Eq)

sExprToSXML :: SExpr -> Either Text SXML
sExprToSXML (SString t) = Right (TextNode t)
sExprToSXML (SSymbol _) = Left "Bare symbol outside element form"
sExprToSXML (SList [])  = Left "Empty list"
sExprToSXML (SList (SSymbol tag : rest)) = case rest of
    (SList (AtSign : pairs) : more) -> do
        attrs    <- mapM parseAttr pairs
        children <- mapM sExprToSXML more
        Right (Element tag attrs children)
    _ -> do
        children <- mapM sExprToSXML rest
        Right (Element tag [] children)
sExprToSXML (SList (other : _)) = Left $ "Expected tag name, got: "
    <> T.pack (Prelude.show other)

parseAttr :: SExpr -> Either Text (Text, Text)
parseAttr (SList [SSymbol k, SString v]) = Right (k, v)
parseAttr other = Left $ "Invalid attribute: " <> T.pack (Prelude.show other)

--------------------------------------------------------------------------------
-- Lucid rendering
--------------------------------------------------------------------------------

renderSXML :: SXML -> Html ()
renderSXML (TextNode t)        = toHtml t
renderSXML (Element tag as cs) =
    makeElement tag (map (uncurry makeAttribute) as) (foldMap renderSXML cs)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

sxmlToHtml :: Text -> Either Text Text
sxmlToHtml input = do
    tokens  <- tokenize input
    (sexprs, rest) <- parseSExprs tokens
    if Prelude.null rest
        then do
            sxmes <- mapM sExprToSXML sexprs
            Right $ renderText $ foldMap renderSXML sxmes
        else Left $ "Extra tokens: " <> T.pack (Prelude.show (take 5 rest))
```

---

### Task 3: Wire SXML compiler into `site.hs`

**Files:**
- Modify: `site.hs`

- [ ] **Add import for SXML and new types**

Add to the top of `site.hs` after the existing imports:

```haskell
import           SXML (sxmlToHtml)
import           Data.Text (Text)
import qualified Data.Text as T
```

- [ ] **Add SXML compiler function before `main`**

Add before `main`:

```haskell
sxmlCompiler :: Compiler (Item String)
sxmlCompiler = do
    item <- getResourceBody
    let body = T.pack $ itemBody item
    case sxmlToHtml body of
        Left err -> fail $ T.unpack err
        Right html -> return $ fmap (const $ T.unpack html) item
```

- [ ] **Change the existing `match "posts/*"` to `match "posts/*.markdown"`**

This prevents the rule from trying to compile `.sxml` files with pandoc.

Change:
```haskell
    match "posts/*" $ do
```
To:
```haskell
    match "posts/*.markdown" $ do
```

- [ ] **Add SXML post matching**

Add after the revised markdown rule:

```haskell
    match "posts/*.sxml" $ do
        route $ setExtension "html"
        compile $ sxmlCompiler
            >>= loadAndApplyTemplate "templates/post.html"    postCtx
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls
```

---

### Task 4: Build and verify

**Files:**
- Create: `posts/2026-06-03-hello-sxml.sxml`
- Then `cabal build` and `cabal run site build`

- [ ] **Create a test SXML post**

Create `posts/2026-06-03-hello-sxml.sxml`:

```sxml
---
title: Hello SXML
author: Iris Lennon
date: 2026-06-03
---

(h1 "Hello from SXML")
(p "This post was written using " (em "SXML") " syntax and rendered via " (em "Lucid") ".")
(p (@ (class "highlight")) "It supports attributes too.")
```

- [ ] **Build the project**

```bash
cabal build
```

- [ ] **Generate the site**

```bash
cabal run site build
```

- [ ] **Verify the output**

```bash
ls -la _site/posts/hello-sxml.html
cat _site/posts/hello-sxml.html
```

Expected: the post HTML should contain the rendered SXML content inside the template structure.
