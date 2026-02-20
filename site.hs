--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Hakyll
import           Data.Time.Clock (getCurrentTime)
import           Data.Time.Format (formatTime, defaultTimeLocale)
import           System.Process (readProcess)
import           System.FilePath (takeBaseName, takeFileName, dropExtension, (</>))
import           System.IO.Temp (withTempDirectory)
import           Control.Monad (void)
import           Data.List (isInfixOf)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import           System.Environment (lookupEnv)
import           System.Directory (removeDirectoryRecursive)
import           Control.Exception (try, SomeException)


--------------------------------------------------------------------------------
-- | Pollen compiler - converts .html.pm files to HTML using raco pollen
-- Supports YAML frontmatter for Hakyll metadata
pollenCompiler :: Compiler (Item String)
pollenCompiler = do
    -- Get the source file path
    identifier <- getUnderlying
    let srcPath = toFilePath identifier
        fileName = takeFileName srcPath

    -- Read the raw content with metadata
    rawContent <- getResourceString
    let content = itemBody rawContent

    -- Split YAML header from Pollen content
    let (yamlHeader, pollenContent) = splitYamlHeader content

    -- Compile Pollen content
    bodyContent <- unsafeCompiler $ withTempDirectory "/tmp" "pollen" $ \tmpDir -> do
        -- Write Pollen content (without YAML) to temp file
        let tmpPm = tmpDir </> fileName
        writeFile tmpPm pollenContent

        -- Run raco pollen render to generate HTML
        void $ readProcess "raco" ["pollen", "render", tmpPm] ""

        -- Read the generated HTML
        -- Pollen replaces .html.pm with .html
        let htmlFile = tmpDir </> takeBaseName fileName
        htmlContent <- readFile htmlFile

        -- Extract body content from Pollen HTML output
        return $ extractPollenBody htmlContent

    makeItem bodyContent

-- | Split YAML header from content
-- Returns (yamlHeader, remainingContent)
splitYamlHeader :: String -> (String, String)
splitYamlHeader content =
    let ls = lines content
    in case ls of
        ("---":rest) ->
            let (yaml, afterYaml) = break (== "---") rest
                remaining = case afterYaml of
                    (_:r) -> dropWhile (\c -> c == '\n' || c == '\r') $ unlines r
                    [] -> ""
            in (unlines ("---" : yaml ++ ["---"]), remaining)
        _ -> ("", content)

-- | Extract body content from Pollen HTML output
-- Pollen generates complete HTML documents, we want just the body content
extractPollenBody :: String -> String
extractPollenBody html =
    case extractBodyTag html of
        Just bodyContent -> bodyContent
        Nothing -> html  -- Fallback to whole HTML if extraction fails

-- | Extract content between <body> and </body>
extractBodyTag :: String -> Maybe String
extractBodyTag html =
    let openTag = "<body"
        closeTag = "</body>"
    in case findSubstring openTag html of
        Nothing -> Nothing
        Just startIdx ->
            let afterOpen = drop startIdx html
                -- Find the closing > of the opening body tag
                afterOpenTag = dropWhile (/= '>') afterOpen
                contentStart = drop 1 afterOpenTag  -- Skip the >
                -- Find the closing </body> tag
                (content, _) = breakAtCloseTag contentStart
            in Just content
    where
        breakAtCloseTag :: String -> (String, String)
        breakAtCloseTag [] = ([], [])
        breakAtCloseTag str
            | closeTag `isPrefixOf` str = ([], drop (length closeTag) str)
            | otherwise = let (rest, remaining) = breakAtCloseTag (tail str)
                         in (head str : rest, remaining)

        closeTag = "</body>"

        isPrefixOf :: String -> String -> Bool
        isPrefixOf prefix str = take (length prefix) str == prefix

        findSubstring :: String -> String -> Maybe Int
        findSubstring sub str = findAt 0 str
            where
                findAt _ [] = Nothing
                findAt idx xs
                    | take (length sub) xs == sub = Just idx
                    | otherwise = findAt (idx + 1) (tail xs)

--------------------------------------------------------------------------------
main :: IO ()
main = do
    -- Always clear cache to force full rebuild
    putStrLn "Full rebuild mode: clearing cache..."
    _ <- try (removeDirectoryRecursive "_cache") :: IO (Either SomeException ())

    hakyll $ do
        match "images/*" $ do
            route   idRoute
            compile copyFileCompiler

        match "js/*" $ do
            route   idRoute
            compile copyFileCompiler

        -- match "css/*" $ do
        --     route   idRoute
        --     compile compressCssCompiler

        match (fromList ["about.rst", "contact.markdown"]) $ do
            route   $ setExtension "html"
            compile $ pandocCompiler
                >>= loadAndApplyTemplate "templates/default.html" defaultContext
                >>= relativizeUrls

        -- Regular markdown posts
        match "posts/*.markdown" $ do
            route $ setExtension "html"
            compile $ pandocCompiler
                >>= loadAndApplyTemplate "templates/post.html"    postCtx
                >>= loadAndApplyTemplate "templates/default.html" postCtx
                >>= relativizeUrls

        -- Pollen x-expressions posts
        match "posts/*.html.pm" $ do
            route $ customRoute $ \ident ->
                let path = toFilePath ident
                    -- Drop both .pm and .html extensions
                    base = dropExtension (dropExtension path)
                in base ++ ".html"
            compile $ pollenCompiler
                >>= loadAndApplyTemplate "templates/post.html"    postCtx
                >>= loadAndApplyTemplate "templates/default.html" postCtx
                >>= relativizeUrls

        create ["archive.html"] $ do
            route idRoute
            compile $ do
                posts <- recentFirst =<< loadAll ("posts/*.markdown" .||. "posts/*.html.pm")
                let dateFunc _ _ = unsafeCompiler $ do
                        now <- getCurrentTime
                        return $ formatTime defaultTimeLocale "%B %e, %Y" now
                    archiveCtx =
                        listField "posts" postCtx (return posts) `mappend`
                        constField "title" "Archives"            `mappend`
                        functionField "currentDate" dateFunc     `mappend`
                        defaultContext
                makeItem ""
                    >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
                    >>= loadAndApplyTemplate "templates/default.html" archiveCtx
                    >>= relativizeUrls


        match "index.html" $ do
            route idRoute
            compile $ do
                posts <- recentFirst =<< loadAll ("posts/*.markdown" .||. "posts/*.html.pm")
                let indexCtx =
                        listField "posts" postCtx (return posts) `mappend`
                        defaultContext

                getResourceBody
                    >>= applyAsTemplate indexCtx
                    >>= loadAndApplyTemplate "templates/default.html" indexCtx
                    >>= relativizeUrls

        match "templates/*" $ compile templateBodyCompiler


--------------------------------------------------------------------------------
postCtx :: Context String
postCtx =
    dateField "date" "%B %e, %Y" `mappend`
    defaultContext
