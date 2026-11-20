-- | The walk finds supported files and stops at nested projects and ignored directories, so a check
-- never reads what is not the project's own.
module Canon.Walk
  ( Walked (..)
  , findSupportedFiles
  , walkProject
  , walkProjectExcluding
  , grammarExtension
  ) where

import Canon.Ignore (IgnorePattern, isIgnored)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import Data.List (sort)
import System.FilePath (splitDirectories, takeExtension, (</>))

-- | The files found and the nested projects skipped.
data Walked = Walked
  { walkedFiles :: [FilePath]
  , walkedProjects :: [FilePath]
  }
  deriving (Eq, Show)

-- | The extension of grammar files, which every project supports.
grammarExtension :: String
grammarExtension = ".g4"

-- | Finds files by extension under a directory, honouring ignores.
findSupportedFiles :: [IgnorePattern] -> FilePath -> IO [FilePath]
findSupportedFiles patterns root = walkedFiles <$> walkProject patterns ((== grammarExtension) . takeExtension) "canon.yaml" root

-- | Walks a project root, keeping the files the predicate accepts by name and stopping at
-- directories that hold their own configuration.
walkProject :: [IgnorePattern] -> (FilePath -> Bool) -> FilePath -> FilePath -> IO Walked
walkProject = walkProjectExcluding Set.empty

-- | Walks a project root as walkProject does, also skipping the paths given, as segments from the
-- root: those git ignores, so a project's generated files need not be listed twice.
-- ref:DEC-honour-gitignore
walkProjectExcluding :: Set [Text] -> [IgnorePattern] -> (FilePath -> Bool) -> FilePath -> FilePath -> IO Walked
walkProjectExcluding excluded patterns supported marker root = go []
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
          if isIgnored patterns True segments || Set.member segments excluded
            then pure (Walked [] [])
            else do
              nested <- doesFileExist (path </> marker)
              if nested then pure (Walked [] [path]) else go relative'
        else
          pure
            ( Walked
                [ path
                | supported entry
                , not (isIgnored patterns False segments)
                , not (Set.member segments excluded)
                ]
                []
            )
    joined relative = if null relative then root else root </> foldr1 (</>) relative
