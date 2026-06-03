{-# LANGUAGE OverloadedStrings #-}
module SXML (sxmlToHtml) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Lucid.Base (Html (), Attribute, With (..), makeAttribute, makeElement, renderText, toHtml)

import Prelude

--------------------------------------------------------------------------------
-- Lexer
--------------------------------------------------------------------------------

data Token = LParen | RParen | Symbol Text | Str Text
    deriving (Show, Eq)

tokenize :: Text -> Either Text [Token]
tokenize = go . T.strip
  where
    go t
        | T.null t = Right []
        | T.head t == '('  = (LParen :) <$> go (T.strip (T.tail t))
        | T.head t == ')'  = (RParen :) <$> go (T.strip (T.tail t))
        | T.head t == '"'  =
            case T.break (== '"') (T.tail t) of
                (str, rest)
                    | T.null rest -> Left "Unterminated string literal"
                    | otherwise   -> (Str str :) <$> go (T.strip (T.drop 1 rest))
        | T.head t == ';'  = go (T.strip (T.dropWhile (/= '\n') t))
        | otherwise =
            let (sym, rest) = T.break (\c -> c `elem` ("()\"@; \t\n\r" :: [Char])) t
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
    (SList (SSymbol "@" : pairs) : more) -> do
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
    with (makeElement tag (foldMap renderSXML cs)) (map (uncurry makeAttribute) as)

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
            Right $ TL.toStrict $ renderText $ foldMap renderSXML sxmes
        else Left $ "Extra tokens: " <> T.pack (Prelude.show (take 5 rest))
