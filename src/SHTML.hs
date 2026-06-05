{-# LANGUAGE OverloadedStrings #-}
module SHTML (shtmlToHtml) where

import Data.Char (isDigit)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Lucid (Html (), renderText, toHtml, toHtmlRaw)
import Lucid.Base (makeAttributes, makeElement)
import Text.TeXMath (readTeX, writeMathML, DisplayType(..))
import Text.XML.Light (showElement)

--------------------------------------------------------------------------------
-- Lexer
--------------------------------------------------------------------------------

data Token = LParen | RParen | LBracket | RBracket | Symbol Text | Str Text
    deriving (Show, Eq)

tokenize :: Text -> Either Text [Token]
tokenize = go . T.strip
  where
    go t
        | T.null t = Right []
        | T.head t == '('  = (LParen :) <$> go (T.strip (T.tail t))
        | T.head t == ')'  = (RParen :) <$> go (T.strip (T.tail t))
        | T.head t == '['  = (LBracket :) <$> go (T.strip (T.tail t))
        | T.head t == ']'  = (RBracket :) <$> go (T.strip (T.tail t))
        | T.head t == '"'  =
            case T.break (== '"') (T.tail t) of
                (str, rest)
                    | T.null rest -> Left "Unterminated string literal"
                    | otherwise   -> (Str str :) <$> go (T.strip (T.drop 1 rest))
        | T.head t == ';'  = go (T.strip (T.dropWhile (/= '\n') t))
        | otherwise =
            let (sym, rest) = T.break (\c -> c `elem` ("()\"[]\n\t\r " :: [Char])) t
            in if T.null sym
               then go (T.strip rest)
               else (Symbol sym :) <$> go (T.strip rest)

--------------------------------------------------------------------------------
-- S-expression parser
--------------------------------------------------------------------------------

data SExpr = SSymbol Text | SString Text | SNumber Text | SBool Bool | SList [SExpr] | SAttrs [SExpr]
    deriving (Show, Eq)

parseSExprs :: [Token] -> Either Text ([SExpr], [Token])
parseSExprs [] = Right ([], [])
parseSExprs (RParen : rest)  = Right ([], RParen : rest)
parseSExprs (RBracket : rest) = Right ([], RBracket : rest)
parseSExprs tokens = case parseOne tokens of
    Right (expr, rest)  -> case parseSExprs rest of
        Right (exprs, rest') -> Right (expr : exprs, rest')
        err                  -> err
    Left err             -> Left err

isNumber :: Text -> Bool
isNumber t = not (T.null t) && case T.unpack t of
    (c:cs) -> isDigit c || c == '-' && not (null cs) && all (\c -> isDigit c || c == '.') cs
    _      -> False

parseOne :: [Token] -> Either Text (SExpr, [Token])
parseOne (Str t    : rest) = Right (SString t, rest)
parseOne (Symbol t : rest)
    | t == "#t" || t == "#true"  = Right (SBool True, rest)
    | t == "#f" || t == "#false" = Right (SBool False, rest)
    | isNumber t                 = Right (SNumber t, rest)
    | otherwise                  = Right (SSymbol t, rest)
parseOne (LParen   : rest) = case parseSExprs rest of
    Right (elems, RParen : rest'') -> Right (SList elems, rest'')
    Right (_,       _)             -> Left "Expected ')'"
    Left err                       -> Left err
parseOne (LBracket : rest) = case parseSExprs rest of
    Right (elems, RBracket : rest'') -> Right (SAttrs elems, rest'')
    Right (_,       _)               -> Left "Expected ']'"
    Left err                         -> Left err
parseOne (RParen : _)    = Left "Unexpected ')'"
parseOne (RBracket : _)  = Left "Unexpected ']'"
parseOne []              = Left "Unexpected end of input"

--------------------------------------------------------------------------------
-- SHTML AST and conversion
--------------------------------------------------------------------------------

data SAst = TextNode Text | Element Text [(Text, Text)] [SAst]
    deriving (Show, Eq)

sExprToSAst :: SExpr -> Either Text SAst
sExprToSAst (SString t) = Right (TextNode t)
sExprToSAst (SNumber t) = Right (TextNode t)
sExprToSAst (SBool True)  = Right (TextNode "true")
sExprToSAst (SBool False) = Right (TextNode "false")
sExprToSAst (SSymbol _) = Left "Bare symbol outside element form"
sExprToSAst (SAttrs _)  = Left "Attribute vector used outside element form"
sExprToSAst (SList [])  = Left "Empty list"
sExprToSAst (SList (SSymbol tag : rest)) = case rest of
    (SAttrs pairs : more) -> do
        attrs    <- parseAttrsFlat pairs
        children <- mapM sExprToSAst more
        Right (Element tag attrs children)
    (SList (SSymbol "@" : pairs) : more) -> do
        attrs    <- mapM parseAttr pairs
        children <- mapM sExprToSAst more
        Right (Element tag attrs children)
    _ -> do
        children <- mapM sExprToSAst rest
        Right (Element tag [] children)
sExprToSAst (SList (other : _)) = Left $ "Expected tag name, got: "
    <> T.pack (show other)

parseAttr :: SExpr -> Either Text (Text, Text)
parseAttr (SList [SSymbol k, SString v]) = Right (k, v)
parseAttr (SList [SSymbol k]) = Right (k, "")
parseAttr other = Left $ "Invalid attribute: " <> T.pack (show other)

parseAttrsFlat :: [SExpr] -> Either Text [(Text, Text)]
parseAttrsFlat [] = Right []
parseAttrsFlat (SSymbol k : SString v : rest) = ((k, v) :) <$> parseAttrsFlat rest
parseAttrsFlat (SSymbol k : rest) = ((k, "") :) <$> parseAttrsFlat rest
parseAttrsFlat (other : _) = Left $ "Expected attribute key-value pair, got: "
    <> T.pack (show other)

--------------------------------------------------------------------------------
-- Lucid rendering
--------------------------------------------------------------------------------

voidElements :: [Text]
voidElements = ["area","base","br","col","embed","hr","img","input","link",
                "meta","param","source","track","wbr"]

renderSAst :: SAst -> Html ()
renderSAst (TextNode t) = toHtml t
renderSAst (Element "@" _ [Element "LaTeX" latexAttrs [TextNode t]]) =
    let displayType = case lookup "display" latexAttrs of
            Just "true" -> DisplayBlock
            _           -> DisplayInline
    in case readTeX t of
        Right exps -> toHtmlRaw $ T.pack $ showElement $ writeMathML displayType exps
        Left _     -> toHtml t
renderSAst (Element tag as cs)
    | tag `elem` voidElements && null cs = toHtmlRaw $ "<" <> tag <> renderAttrs as <> ">"
    | otherwise = makeElement tag (map (uncurry makeAttributes) as) (foldMap renderSAst cs)

renderAttrs :: [(Text, Text)] -> Text
renderAttrs = T.concat . map go
  where
    go (k, v) | T.null v  = " " <> k
              | otherwise  = " " <> k <> "=\"" <> escapeAttr v <> "\""
    escapeAttr = T.concatMap escapeChar
    escapeChar '"' = "&quot;"
    escapeChar '&' = "&amp;"
    escapeChar '<' = "&lt;"
    escapeChar '>' = "&gt;"
    escapeChar c   = T.singleton c

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

shtmlToHtml :: Text -> Either Text Text
shtmlToHtml input = do
    tokens  <- tokenize input
    (sexprs, rest) <- parseSExprs tokens
    if null rest
        then do
            sxmes <- mapM sExprToSAst sexprs
            Right $ TL.toStrict $ renderText $ foldMap renderSAst sxmes
        else Left $ "Extra tokens: " <> T.pack (show (take 5 rest))
