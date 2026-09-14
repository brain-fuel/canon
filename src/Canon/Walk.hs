module Canon.Walk
  ( Walked (..)
  , findSupportedFiles
  , walkProject
  , grammarExtension
  ) where

import Canon.Ignore (IgnorePattern, isIgnored)
import Data.List (sort)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (splitDirectories, takeExtension, (</>))

data Walked = Walked
  { walkedFiles :: [FilePath]
  , walkedProjects :: [FilePath]
  }
  deriving (Eq, Show)

grammarExtension :: String
grammarExtension = ".g4"

findSupportedFiles :: [IgnorePattern] -> FilePath -> IO [FilePath]
findSupportedFiles patterns root = walkedFiles <$> walkProject patterns [grammarExtension] "canon.yaml" root

walkProject :: [IgnorePattern] -> [String] -> FilePath -> FilePath -> IO Walked
walkProject patterns extensions marker root = go []
  where
    go relative = do
      let directory = joined relative
      entries <- sort <$> listDirectory directory
      results <- mapM (visit relative) entries
      pure (Walked (concatMap walkedFiles results) (concatMap walkedProjects results))
    visit relative entry = do
      let relative' = relative ++ [entry]
          segments = map T.pack (concatMap splitDirectories relative')
          path = joined relative'
      isDirectory <- doesDirectoryExist path
      if isDirectory
        then
          if isIgnored patterns True segments
            then pure (Walked [] [])
            else do
              nested <- doesFileExist (path </> marker)
              if nested then pure (Walked [] [path]) else go relative'
        else
          pure
            ( Walked
                [ path
                | takeExtension entry `elem` extensions
                , not (isIgnored patterns False segments)
                ]
                []
            )
    joined relative = if null relative then root else root </> foldr1 (</>) relative
