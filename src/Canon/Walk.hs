module Canon.Walk
  ( Language (..)
  , supportedLanguages
  , languageOfPath
  , findSupportedFiles
  ) where

import Canon.Ignore (IgnorePattern, isIgnored)
import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (splitDirectories, takeExtension, (</>))

data Language = Language
  { languageName :: Text
  , languageExtensions :: [String]
  }
  deriving (Eq, Show)

supportedLanguages :: [Language]
supportedLanguages = [Language "antlr4" [".g4"]]

languageOfPath :: FilePath -> Maybe Language
languageOfPath path = case [l | l <- supportedLanguages, takeExtension path `elem` languageExtensions l] of
  (l : _) -> Just l
  [] -> Nothing

findSupportedFiles :: [IgnorePattern] -> FilePath -> IO [FilePath]
findSupportedFiles patterns root = go []
  where
    go relative = do
      let directory = if null relative then root else root </> foldr1 (</>) relative
      entries <- sort <$> listDirectory directory
      concat <$> mapM (visit relative) entries
    visit relative entry = do
      let relative' = relative ++ [entry]
          segments = map T.pack (concatMap splitDirectories relative')
          path = root </> foldr1 (</>) relative'
      isDirectory <- doesDirectoryExist path
      if isDirectory
        then if isIgnored patterns True segments then pure [] else go relative'
        else
          pure
            [ path
            | languageOfPath entry /= Nothing
            , not (isIgnored patterns False segments)
            ]
