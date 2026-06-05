{-# LANGUAGE OverloadedStrings #-}
import           Data.List (sort, intercalate)
import           Data.Monoid (mappend)
import           Hakyll
import           Data.Time.Clock (getCurrentTime)
import           Data.Time.Format (formatTime, defaultTimeLocale)
import           SHTML (shtmlToHtml)
import qualified Data.Text as T
import           Text.Pandoc.Extensions (enableExtension, Extension(Ext_tex_math_single_backslash))
import           Text.Pandoc.Options (ReaderOptions(..), WriterOptions(..), HTMLMathMethod(..))


--------------------------------------------------------------------------------
fixMathML :: String -> String
fixMathML = T.unpack
          . T.replace "http://www.w3.org/1998/Math/MathML" "https://www.w3.org/TR/mathml4/"
          . T.pack


-------------------------------------------------------------------------------
shtmlCompiler :: Compiler (Item String)
shtmlCompiler = do
    item <- getResourceBody
    let body = T.pack $ itemBody item
    case shtmlToHtml body of
        Left err -> fail $ T.unpack err
        Right html -> makeItem (T.unpack html)


--------------------------------------------------------------------------------
tagsNavField :: String -> Tags -> Context String
tagsNavField key tags = field key $ \item -> do
    mRaw <- getMetadataField (itemIdentifier item) "tags"
    return $ case mRaw of
        Nothing -> ""
        Just raw ->
            let ts = sort $ map T.strip $ T.split (== ',') $ T.pack raw
                ts' = [T.unpack t | t <- ts, not (T.null t)]
            in if null ts' then ""
               else "Tags: " ++ intercalate ", " [tagLink t | t <- ts']
  where
    tagLink t = "<a href=\"/tags/" ++ t ++ ".html\">" ++ t ++ "</a>"


-------------------------------------------------------------------------------
currentDateField :: Context String
currentDateField = functionField "currentDate" $ \_ _ -> unsafeCompiler $ do
    now <- getCurrentTime
    return $ formatTime defaultTimeLocale "%B %e, %Y" now


-------------------------------------------------------------------------------
main :: IO ()
main = hakyll $ do
    match "images/*" $ do
        route   idRoute
        compile copyFileCompiler

    match "js/*" $ do
        route   idRoute
        compile copyFileCompiler

    tags <- buildTags "posts/*" (fromCapture "tags/*.html")
    let postCtx' = postCtx tags

    match (fromList ["about.rst", "contact.markdown"]) $ do
        route   $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/default.html" (tagsNavField "tags-nav" tags `mappend` defaultContext)
            >>= relativizeUrls

    tagsRules tags $ \tag pattern -> do
        let title = "Posts tagged \x201C" ++ tag ++ "\x201D"
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll pattern
            let ctx = constField "title" title
                      `mappend` currentDateField
                      `mappend` constField "date" " "
                      `mappend` constField "author" "Hakyll"
                      `mappend` listField "posts" (postCtx tags) (return posts)
                      `mappend` tagsNavField "tags-nav" tags
                      `mappend` defaultContext
            makeItem ""
                >>= loadAndApplyTemplate "templates/tag.html"    ctx
                >>= loadAndApplyTemplate "templates/default.html" ctx
                >>= relativizeUrls

    match "posts/*.markdown" $ do
        route $ setExtension "html"
        compile $ fmap (fmap fixMathML) mathPandocCompiler
            >>= loadAndApplyTemplate "templates/post.html"    postCtx'
            >>= loadAndApplyTemplate "templates/default.html" (tagsNavField "tags-nav" tags `mappend` postCtx')
            >>= relativizeUrls

    match "posts/*.ss" $ do
        route $ setExtension "html"
        compile $ fmap (fmap fixMathML) shtmlCompiler
            >>= loadAndApplyTemplate "templates/post.html"    postCtx'
            >>= loadAndApplyTemplate "templates/default.html" (tagsNavField "tags-nav" tags `mappend` postCtx')
            >>= relativizeUrls

    create ["archive.html"] $ do
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll "posts/*"
            let archiveCtx =
                    listField "posts" postCtx' (return posts) `mappend`
                    constField "title" "Archives"            `mappend`
                    constField "author" "Hakyll"              `mappend`
                    currentDateField                          `mappend`
                    tagsNavField "tags-nav" tags                              `mappend`
                    defaultContext
            makeItem ""
                >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
                >>= loadAndApplyTemplate "templates/default.html" archiveCtx
                >>= relativizeUrls

    match "index.html" $ do
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll "posts/*"
            let indexCtx =
                    listField "posts" postCtx' (return posts) `mappend`
                    currentDateField `mappend`
                    tagsNavField "tags-nav" tags `mappend`
                    defaultContext

            getResourceBody
                >>= applyAsTemplate indexCtx
                >>= loadAndApplyTemplate "templates/default.html" indexCtx
                >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler


--------------------------------------------------------------------------------
mathPandocCompiler :: Compiler (Item String)
mathPandocCompiler =
    let readerOpts = defaultHakyllReaderOptions
            { readerExtensions = enableExtension Ext_tex_math_single_backslash
                                   (readerExtensions defaultHakyllReaderOptions) }
        writerOpts = defaultHakyllWriterOptions
            { writerHTMLMathMethod = MathML }
    in pandocCompilerWith readerOpts writerOpts


-------------------------------------------------------------------------------
postCtx :: Tags -> Context String
postCtx tags =
    tagsField "tags" tags `mappend`
    dateField "date" "%B %e, %Y" `mappend`
    field "author" (\item -> do
        mAuthor <- getMetadataField (itemIdentifier item) "author"
        return $ maybe "Unknown" id mAuthor) `mappend`
    defaultContext
